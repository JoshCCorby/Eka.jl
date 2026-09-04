include(joinpath(@__DIR__, "..", "scripts", "inspect_external_scores.jl"))

@testset "External score coverage inspection" begin
    mktempdir() do dir
        database = build_legacy_fixture(joinpath(dir, "legacy.db"))
        original = read(database)
        audit = joinpath(dir, "compositions.tsv")
        write(audit, "composition\tchemical_system\tlabel\n" *
            "NaClO\tCl-Na-O\tpositive\n" *
            "LiNaO\tLi-Na-O\tunlabelled\n" *
            "BaTiO3\tBa-O-Ti\tunresolved\n")
        output = IOBuffer()
        report = InspectExternalScores.inspect(database, audit; out=output)
        @test report.result.rows == 1 && report.result.in_scope == 1
        @test report.covered["positive"] == 1
        @test occursin("positive: 1/1 = 100.00%", String(take!(output)))
        @test read(database) == original
        @test_throws ArgumentError InspectExternalScores.read_scores(database; table="data2")
        @test_throws ArgumentError InspectExternalScores.read_scores(database; table="missing")
    end
end
