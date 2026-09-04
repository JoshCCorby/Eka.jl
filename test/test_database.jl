function with_test_database(f; table="compositions", rows=Tuple[])
    mktempdir() do directory
        path = joinpath(directory, "test.db")
        db = SQLite.DB(path)
        try
            name = EkaCompositions.quote_identifier(table)
            DBInterface.execute(db, "CREATE TABLE $name (composition TEXT, score REAL)")
            for row in rows
                DBInterface.execute(db, "INSERT INTO $name VALUES (?, ?)", row)
            end
        finally
            DBInterface.close!(db)
        end
        f(path)
    end
end

@testset "Database and ranking" begin
    before = read(FIXTURE)
    all_results = query_compositions(FIXTURE; threshold=0)
    @test length(all_results) == length(FixtureData.ROWS) == 12
    @test eltype(all_results) == Tuple{Composition,Float64}
    @test (@inferred EkaCompositions.parse_scored_row("MgZn", 0.4)) == (Composition("MgZn"), 0.4)
    filters = EkaCompositions.query_filters(["Mg"], [2], 0.01)
    @test (@inferred EkaCompositions.matches_filters(Composition("MgZn"), filters))
    @test issorted(all_results; by=r -> (-r[2], formula(r[1])))
    @test first(all_results) == (Composition("Al2Ba2O7Si1"), 0.74232)

    results = query_compositions(FIXTURE; elements=["Al", "Si", "O"], nary=[4])
    @test length(results) == 5
    @test all(r -> all(e -> e in species(r[1]), ("Al", "Si", "O")) && length(r[1]) == 4, results)
    @test results == query_compositions(FIXTURE; elements=["O", "Si", "Al"], nary=[4])
    @test results == query_compositions(FIXTURE; elements=["O", "Al", "Si", "Al"], nary=[4, 4])
    @test isempty(query_compositions(FIXTURE; elements=["Al", "Si", "O"], nary=[2]))
    @test length(query_compositions(FIXTURE; nary=[3])) == 2
    @test length(query_compositions(FIXTURE; nary=[2, 3])) == 7
    @test isempty(query_compositions(FIXTURE; nary=Int[]))
    @test query_compositions(FIXTURE; elements=String[]) == query_compositions(FIXTURE)
    @test isempty(query_compositions(FIXTURE; elements=["Og"]))
    @test formula.(first.(query_compositions(FIXTURE; elements=["N"]))) == ["Cl1N1O1"]

    for threshold in (0.0, 0.3, 0.4, 0.5, 0.75)
        lower = query_compositions(FIXTURE; elements=["Mg", "Zn"], nary=[2], threshold)
        higher = query_compositions(FIXTURE; elements=["Mg", "Zn"], nary=[2], threshold=threshold + 0.1)
        @test issubset(Set(higher), Set(lower))
        @test all(r -> r[2] >= threshold, lower)
    end
    @test count(r -> r[2] == 0.3, query_compositions(FIXTURE; threshold=0.3)) == 2
    @test formula.(first.(filter(r -> r[2] == 0.5, all_results))) == ["Cl1N1O1", "Cl1Na1O1"]
    @test count(r -> r[1] == Composition("MgZn"), all_results) == 2
    @test_throws ArgumentError query_compositions(FIXTURE; elements=["Xx"])
    @test_throws ArgumentError query_compositions(FIXTURE; elements=["Mg'; DROP TABLE compositions; --"])
    @test_throws ArgumentError query_compositions(FIXTURE; elements="Mg")
    @test_throws ArgumentError query_compositions(FIXTURE; nary=2)
    for nary in ([0], [-1], [119], [2.5], [true])
        @test_throws ArgumentError query_compositions(FIXTURE; nary)
    end
    for threshold in (NaN, Inf, -Inf, true, "0.3")
        @test_throws ArgumentError query_compositions(FIXTURE; threshold)
    end
    @test before == read(FIXTURE)

    mktempdir() do directory
        missing = joinpath(directory, "missing.db")
        @test_throws r"database file does not exist" query_compositions(missing)
        @test !ispath(missing)
        @test_throws ArgumentError query_compositions(directory)
        invalid = joinpath(directory, "invalid.db")
        write(invalid, "not SQLite")
        @test_throws r"not a valid SQLite" query_compositions(invalid)
        write(invalid, "SQLite format 3\0" * repeat("x", 200))
        @test_throws r"cannot query SQLite" query_compositions(invalid)

        fresh = FixtureData.build_fixture(joinpath(directory, "rebuilt.db"))
        @test query_compositions(fresh) == query_compositions(FIXTURE)
        @test_throws ArgumentError FixtureData.build_fixture(fresh)

        db = SQLite.DB(joinpath(directory, "wrong-schema.db"))
        try
            DBInterface.execute(db, "CREATE TABLE unrelated (name TEXT)")
        finally
            DBInterface.close!(db)
        end
        @test_throws r"composition and score" query_compositions(joinpath(directory, "wrong-schema.db"))

        mixed_case = joinpath(directory, "mixed-case.db")
        db = SQLite.DB(mixed_case)
        try
            DBInterface.execute(db, "CREATE TABLE data (Composition TEXT, Score REAL)")
            DBInterface.execute(db, "INSERT INTO data VALUES (?, ?)", ("MgZn", 0.4))
        finally
            DBInterface.close!(db)
        end
        @test query_compositions(mixed_case) == [(Composition("MgZn"), 0.4)]
    end

    with_test_database(; table="odd\"; DROP TABLE harmless; --", rows=[("MgZn", 0.4)]) do path
        @test query_compositions(path) == [(Composition("MgZn"), 0.4)]
    end
    with_test_database() do path
        @test isempty(query_compositions(path))
        db = SQLite.DB(path)
        try
            DBInterface.execute(db, "CREATE TABLE another (composition TEXT, score REAL)")
        finally
            DBInterface.close!(db)
        end
        @test_throws r"ambiguous database schema" query_compositions(path)
    end
    for row in (("Xx2", 0.5), (missing, 0.5), ("MgZn", missing), ("MgZn", "invalid"), ("MgZn", Inf))
        with_test_database(; rows=[row]) do path
            @test_throws ArgumentError query_compositions(path)
        end
    end

    # Storage/insertion order cannot affect ranking.
    with_test_database(; rows=reverse(FixtureData.ROWS)) do path
        @test query_compositions(path) == query_compositions(FIXTURE)
    end
end
