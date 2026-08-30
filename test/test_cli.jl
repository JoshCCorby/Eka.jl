function run_cli(args)
    out, err = IOBuffer(), IOBuffer()
    status = main(args; out, err)
    return status, String(take!(out)), String(take!(err))
end

@testset "Ranking, import, and audit commands" begin
    status, output, errors = run_cli(["-d", FIXTURE, "-e", "Mg", "Zn", "-n", "2", "--rank", "similarity", "--reference", "MgZn"])
    @test status == 0 && isempty(errors)
    @test startswith(output, "# Composition, Score, Similarity\nMg1Zn1   0.30000   1.00000\n")
    strict = run_cli(["-d", FIXTURE, "-n", "2", "--threshold", "0.3", "--strict-threshold"])
    @test strict[1] == 0 && !occursin("0.30000", strict[2])
    for extras in (["--rank", "similarity"], ["--reference", "MgZn"], ["--rank", "unknown"], ["--rank", "similarity", "--reference", "Xx"])
        status, output, errors = run_cli(vcat(["-d", FIXTURE], extras))
        @test status == 2 && isempty(output) && occursin("error:", errors)
    end
    for command in ("import", "validate")
        status, output, errors = run_cli([command, "--help"])
        @test status == 0 && isempty(errors) && occursin("--database", output)
        @test run_cli([command])[1] == 2
    end
    status, output, errors = run_cli(["validate", "-d", FIXTURE])
    @test status == 0 && isempty(errors)
    @test occursin("Validated 12 records", output)
    mktempdir() do dir
        legacy = build_legacy_fixture(joinpath(dir, "legacy.db"))
        status, output, errors = run_cli(["-d", legacy, "-n", "4"])
        @test status == 0 && occursin("ionic compositions only", errors)
        @test startswith(output, "# Composition, Score\n")
        @test occursin("no source tables", run_cli(["-d", legacy, "-n", "6"])[3])
        input = joinpath(dir, "scored.tsv")
        destination = joinpath(dir, "output.db")
        write(input, "composition\tscore\nMg2Zn\t0.4\nNaCl\t1.1\n")
        args = ["import", "--input", input, "-d", destination, "--source", "test v1"]
        status, output, errors = run_cli(args)
        @test status == 0 && isempty(errors)
        @test occursin("Imported 2 records", output)
        @test validate_database(destination).rows == 2
        @test run_cli(args)[1] == 2
        invalid = joinpath(dir, "unsupported.db")
        db = SQLite.DB(invalid)
        try
            DBInterface.execute(db, "CREATE TABLE compositions (composition TEXT, score REAL)")
            DBInterface.execute(db, "INSERT INTO compositions VALUES (?, ?)", ("DyD2", 0.8))
        finally
            DBInterface.close!(db)
        end
        status, output, errors = run_cli(["validate", "-d", invalid, "--report"])
        @test status == 2 && isempty(errors)
        @test occursin("1 invalid or unsupported", output)
        @test occursin("unsupported_symbol", output)
    end
end

@testset "CLI" begin
    status, output, errors = run_cli(["-d", FIXTURE, "-e", "Al", "Si", "O", "-n", "4"])
    @test status == 0
    @test isempty(errors)
    @test output == """
    # Composition, Score
    Al2Ba2O7Si1   0.74232
    Al2O12Si3Zn3   0.48140
    Al1Li1O12Si5   0.41613
    Al2Ba3O14Si4   0.39355
    Al2O14Si4Sr3   0.34611
    """
    @test run_cli(["--database", FIXTURE, "--elements", "O", "Si", "Al", "--nary", "4"])[2] == output
    @test run_cli(["-d", FIXTURE])[2] == "# Composition, Score\nCl1N1O1   0.50000\nCl1Na1O1   0.50000\n"
    @test run_cli(["-d", FIXTURE, "-n", "2", "3", "--threshold", "0.5"])[2] == run_cli(["-d", FIXTURE])[2]
    @test run_cli(["-d", FIXTURE, "-n"])[2] == "# Composition, Score\n"
    @test run_cli(["-d", FIXTURE, "-e"])[2] == run_cli(["-d", FIXTURE])[2]
    @test run_cli(["-d", FIXTURE, "--threshold", "2"])[2] == "# Composition, Score\n"

    status, output, errors = run_cli(["--help"])
    @test status == 0 && isempty(errors)
    @test occursin("--database", output) && occursin("--threshold", output)
    @test occursin("-h, --help", output)
    for args in (String[], ["-d", FIXTURE, "-e", "Xx"], ["-d", FIXTURE, "-n", "0"], ["-d", FIXTURE, "-n", "two"], ["-d", FIXTURE, "--threshold", "NaN"], ["-d", FIXTURE, "--unknown"])
        status, output, errors = run_cli(args)
        @test status == 2
        @test isempty(output)
        @test occursin("eka: error:", errors)
    end
    mktempdir() do directory
        status, output, errors = run_cli(["-d", joinpath(directory, "missing.db")])
        @test status == 2 && isempty(output)
        @test occursin("database file does not exist", errors)
    end

    # Exercise the actual process entry point and its exit status, not just main().
    root = dirname(@__DIR__)
    entry = joinpath(root, "bin", "eka")
    command = `$(Base.julia_cmd()) --startup-file=no --project=$root $entry -d $FIXTURE -n 4 -e Al Si O`
    @test read(command, String) == run_cli(["-d", FIXTURE, "-n", "4", "-e", "Al", "Si", "O"])[2]
    failure = run(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no --project=$root $entry -d $FIXTURE -e Xx`); stdout=devnull, stderr=devnull))
    @test failure.exitcode == 2
end
