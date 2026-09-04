function synthetic_document(id="mp-1"; composition=Dict("Al" => 2, "Mg" => 1, "O" => 4),
        theoretical=false, database_IDs=Dict("icsd" => ["synthetic"]), deprecated=false)
    return (material_id=id, composition=composition, formula_pretty="synthetic",
        theoretical=theoretical, database_IDs=database_IDs, deprecated=deprecated)
end

@testset "Julia synthetic MP snapshot writer" begin
    mktempdir() do dir
        target = joinpath(dir, "snapshot")
        write_synthetic_mp_snapshot([
            synthetic_document("mp-aaaaaaft"; theoretical=true),
            synthetic_document(),
        ], target; database_version="fixture-v2")
        metadata = TOML.parsefile(joinpath(target, "snapshot.toml"))
        @test metadata["schema_version"] == 2
        @test metadata["producer_language"] == "Julia" && metadata["is_synthetic"]
        @test metadata["record_count"] == 2
        @test metadata["records_sha256"] == bytes2hex(sha256(read(joinpath(target, "records.tsv"))))
        @test metadata["jsonl_sha256"] == bytes2hex(sha256(read(joinpath(target, "records.jsonl"))))
        @test [JSON3.read(line).material_id for line in eachline(joinpath(target, "records.jsonl"))] ==
            ["mp-1", "mp-aaaaaaft"]
        @test_throws ArgumentError write_synthetic_mp_snapshot([synthetic_document()], target;
            database_version="fixture-v2")
        result = audit_mp_snapshot(target, joinpath(dir, "audit"))
        @test result.summary["positive_compositions"] == 1
    end
    mktempdir() do dir
        target = joinpath(dir, "snapshot")
        for documents in ([], [synthetic_document(), synthetic_document(; theoretical=true)],
                [synthetic_document(; deprecated=true)], [synthetic_document("invalid")],
                [synthetic_document(; composition=Dict("O" => NaN))])
            @test_throws ArgumentError write_synthetic_mp_snapshot(documents, target;
                database_version="fixture-v2")
            @test !ispath(target)
        end
        for (composition, reason) in ((Dict("Li" => 1.5), "fractional_counts"),
                (Dict("O" => 0), "invalid_counts"), (Dict("O" => true), "invalid_counts"),
                (Dict("Fe2+" => 1), "unsupported_species"), (Dict{String,Int}(), "missing_composition"))
            @test Eka.mp_snapshot_formula(composition) == (".", reason)
        end
    end
end
