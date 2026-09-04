const LEGACY_ROWS = Dict(
    "data2" => [("Mg2Zn", 0.3), ("Zn3Mg", 0.4), ("NCl", 0.5), ("NaCl", 0.5)],
    "data3" => [("NaClO", 0.7)],
    "data4ionic" => [("Al2Ba2O7Si1", 0.74232), ("Al2Ba3O14Si4", 0.39355)],
    "data5ionic" => [("MgZnAlSiO", 0.8)],
)

function build_legacy_fixture(path)
    db = SQLite.DB(path)
    try
        for name in sort!(collect(keys(LEGACY_ROWS)))
            n = EkaCompositions.LEGACY_TABLES[name]
            columns = ["composition TEXT"]
            append!(columns, ["ele$i TEXT" for i in 1:n])
            append!(columns, ["int$i INTEGER" for i in 1:n])
            push!(columns, "score REAL")
            DBInterface.execute(db, "CREATE TABLE $name ($(join(columns, ", ")))")
            for (raw, score) in LEGACY_ROWS[name]
                c = Composition(raw)
                values = (raw, first.(c.terms)..., last.(c.terms)..., score)
                DBInterface.execute(db, "INSERT INTO $name VALUES ($(join(fill("?", length(values)), ", ")))", values)
            end
        end
    finally
        DBInterface.close!(db)
    end
    path
end

@testset "Legacy production schema" begin
    mktempdir() do dir
        path = build_legacy_fixture(joinpath(dir, "legacy.db"))
        original = read(path)
        @test database_info(path).schema == :legacy
        @test count(t -> t.ionic_only, database_info(path).tables) == 2
        @test validate_database(path).rows == 8
        @test length(query_compositions(path)) == 8
        for n in 2:5
            results = query_compositions(path; nary=[n])
            @test all(r -> length(r[1]) == n, results)
        end
        @test length(query_compositions(path; nary=[2, 3])) == 5
        @test isempty(query_compositions(path; nary=[1, 6]))
        @test isempty(query_compositions(path; nary=Int[]))
        @test formula.(first.(query_compositions(path; elements=["N"]))) == ["Cl1N1"]
        @test length(query_compositions(path; elements=["Al", "O", "Si"], nary=[4])) == 2
        @test query_compositions(path; elements=["Al", "O", "Si"]) == query_compositions(path; elements=["Si", "O", "Al"])
        @test length(query_compositions(path; elements=["Mg", "Zn"], nary=[2], threshold=0.3)) == 2
        @test length(query_compositions(path; elements=["Mg", "Zn"], nary=[2], threshold=0.3, inclusive=false)) == 1
        @test_throws ArgumentError query_compositions(path; elements=["Zn' OR 1=1 --"])
        @test original == read(path)
        # The connection itself, not merely a convention, prevents writes.
        @test_throws ArgumentError EkaCompositions.with_database(path) do db
            DBInterface.execute(db, "DELETE FROM data2")
        end
        @test original == read(path)

        db = SQLite.DB(path)
        try
            DBInterface.execute(db, "UPDATE data2 SET int1 = 7 WHERE composition = ?", ("Mg2Zn",))
        finally
            DBInterface.close!(db)
        end
        @test_throws r"disagree" query_compositions(path; elements=["Mg", "Zn"], nary=[2])
        @test_throws r"data2, scan row" validate_database(path)
        audit = validate_database(path; strict=false, max_issues=1)
        @test audit.rows == 8 && audit.valid_rows == 7 && audit.invalid_rows == 1
        @test length(audit.issues) == 1 && audit.issues[1].table == "data2"
        @test audit.categories[:inconsistent_columns] == 1
        @test_throws ArgumentError validate_database(path; max_issues=-1)
        # SQL filters intentionally do not audit unrelated rows.
        @test length(query_compositions(path; elements=["Al"], nary=[4])) == 2
    end
    mktempdir() do dir
        path = joinpath(dir, Sys.iswindows() ? "sp ace%#λ.db" : "sp ace%?#λ.db")
        cp(FIXTURE, path)
        @test query_compositions(path) == query_compositions(FIXTURE)
    end
    with_test_database(; table="data2") do path
        @test_throws r"requires ele1" query_compositions(path)
    end
    with_test_database(; rows=[("Dy1D2", 0.8), ("MgZn", 0.5)]) do path
        @test_throws r"invalid element symbol" query_compositions(path)
        audit = validate_database(path; strict=false)
        @test audit.invalid_rows == 1 && audit.valid_rows == 1
        @test audit.categories[:unsupported_symbol] == 1
        @test occursin("Dy1D2", only(audit.issues).error)
        @test isempty(validate_database(path; strict=false, max_issues=0).issues)
    end
end
