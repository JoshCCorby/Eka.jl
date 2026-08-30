using SHA

function read_metadata(path)
    Eka.with_database(path) do db
        Dict(String(r.key) => String(r.value) for r in DBInterface.execute(db, "SELECT key, value FROM import_metadata"))
    end
end

@testset "Validated imports" begin
    mktempdir() do dir
        destination = joinpath(dir, "import.db")
        result = import_compositions((("Zn2Mg4", 0.4), (Composition("NaCl"), 1.2)), destination; source="hand-authored v1")
        @test result.rows == 2
        @test length(result.records_sha256) == 64
        @test validate_database(destination).rows == 2
        @test query_compositions(destination) == [(Composition("NaCl"), 1.2), (Composition("Mg2Zn"), 0.4)]
        @test read_metadata(destination)["source"] == "hand-authored v1"
        @test read_metadata(destination)["records_sha256"] == result.records_sha256
        Eka.with_database(destination) do db
            @test first(DBInterface.execute(db, "SELECT source_formula FROM compositions WHERE source_row = 1")).source_formula == "Zn2Mg4"
        end
        before = read(destination)
        @test_throws r"refusing to overwrite" import_compositions([("MgZn", 1.0)], destination; source="x")
        @test read(destination) == before

        duplicate = [("MgZn", 0.4), ("Zn2Mg2", 0.5)]
        failed = joinpath(dir, "failed.db")
        contents = readdir(dir)
        @test_throws r"source row 2: duplicate" import_compositions(duplicate, failed; source="x")
        @test !ispath(failed)
        @test readdir(dir) == contents
        kept = import_compositions(duplicate, joinpath(dir, "kept.db"); source="x", duplicates=:keep)
        @test kept.rows == 2
        @test first.(query_compositions(kept.path)) == [Composition("MgZn"), Composition("MgZn")]
        for rows in ([ ("MgZn", 0.4), ("Xx", 0.5) ], [("MgZn", NaN)], [("MgZn", Inf)], [("MgZn", missing)], [("MgZn", "0.3")], [("MgZn", true)], [], [("MgZn",)], [("MgZn", 0.3, "extra")])
            contents = readdir(dir)
            @test_throws ArgumentError import_compositions(rows, failed; source="x")
            @test !ispath(failed)
            @test readdir(dir) == contents
        end
        @test_throws ArgumentError import_compositions(duplicate, failed; source="")
        @test_throws ArgumentError import_compositions(duplicate, failed; source="x", duplicates=:unknown)
        @test_throws ArgumentError import_compositions(duplicate, joinpath(dir, "missing", "x.db"); source="x")

        input = joinpath(dir, "input.tsv")
        raw = "composition\tscore\r\nZn2Mg4\t0.4\r\nNaCl\t1.2\r\n"
        write(input, raw)
        imported = import_tsv(input, joinpath(dir, "tsv.db"); source="synthetic TSV v1")
        @test query_compositions(imported.path) == query_compositions(destination)
        @test read_metadata(imported.path)["source_sha256"] == bytes2hex(sha256(raw))
        @test imported.records_sha256 == result.records_sha256
        @test read(input, String) == raw
        @test_throws ArgumentError import_tsv(input, input; source="x")
        @test read(input, String) == raw
        for invalid in ("", "composition,score\nMgZn,0.4\n", "composition\tscore\n", "composition\tscore\nMgZn\tbad\n", "composition\tscore\nMgZn\t0.4\textra\n", "composition\tscore\nMgZn\t0.4\n\n")
            write(input, invalid)
            contents = readdir(dir)
            @test_throws ArgumentError import_tsv(input, failed; source="x")
            @test !ispath(failed)
            @test readdir(dir) == contents
        end
        @test_throws ArgumentError import_tsv(joinpath(dir, "missing.tsv"), failed; source="x")

        # A destination appearing during streaming must not be overwritten either.
        raced = joinpath(dir, "raced.db")
        records = (begin
            write(raced, "concurrently created file")
            ("MgZn", 0.4)
        end for _ in 1:1)
        contents = Set(readdir(dir))
        @test_throws Exception import_compositions(records, raced; source="race test")
        @test read(raced, String) == "concurrently created file"
        @test Set(readdir(dir)) == union(contents, Set(["raced.db"]))
    end
end
