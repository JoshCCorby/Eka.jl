function mp_test_snapshot(dir, body; overrides=Dict{String,Any}())
    snapshot = joinpath(dir, "snapshot")
    mkdir(snapshot)
    bytes = Eka.MP_AUDIT_HEADER * "\n" * body
    write(joinpath(snapshot, "records.tsv"), bytes)
    # Synthetic provenance carrier; parser/normalizer is independently tested in Python.
    raw = "{\"is_synthetic\":true}\n"
    write(joinpath(snapshot, "records.jsonl"), raw)
    metadata = Dict{String,Any}("schema_version" => 1, "database_version" => "synthetic-v1",
        "query_include_gnome" => false, "query_deprecated" => false,
        "query_elements" => ["O"], "query_num_elements" => 3, "is_synthetic" => true,
        "redistribution_status" => "synthetic test fixture", "record_count" => count(==('\n'), body),
        "records_sha256" => bytes2hex(sha256(bytes)), "jsonl_sha256" => bytes2hex(sha256(raw)))
    merge!(metadata, overrides)
    open(joinpath(snapshot, "snapshot.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    return snapshot
end

@testset "MP legacy and alphabetic material IDs" begin
    mktempdir() do dir
        body = "mp-1\tMgAl2O4\tfalse\ticsd:synthetic\t.\n" *
            "mp-aaaaaaft\tMg2Al4O8\ttrue\t.\t.\n" *
            "mp-fu\tCaTiO3\ttrue\t.\t.\n"
        snapshot = mp_test_snapshot(dir, body)
        result = audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
        @test result.summary["total_records"] == 3
        @test result.summary["unique_compositions"] == 2
        group = only(filter(c -> c.composition == "Al2Mg1O4", result.compositions))
        @test group.material_ids == "mp-1;mp-aaaaaaft"
        @test group.label == "positive"
        @test occursin("mp-aaaaaaft", read(joinpath(dir, "audit", "compositions.tsv"), String))
    end
    for id in ("mp-", "mp-abc123", "mp-FT", "mvc-149", "mp-149-extra", "mp-١٤٩")
        mktempdir() do dir
            snapshot = mp_test_snapshot(dir, "$id\tCaTiO3\tfalse\t.\t.\n")
            output = joinpath(dir, "audit")
            @test_throws ArgumentError audit_mp_snapshot(snapshot, output)
            @test !ispath(output)
        end
    end
end

@testset "MP snapshot composition/provenance audit" begin
    body = "mp-1\tMgAl2O4\tfalse\ticsd:synthetic\t.\n" *
        "mp-2\tMg2Al4O8\ttrue\t.\t.\n" *
        "mp-3\tCaTiO3\ttrue\t.\t.\n" *
        "mp-4\tBaTiO3\tunknown\t.\t.\n" *
        "mp-5\tBa2Ti2O6\ttrue\t.\t.\n" *
        "mp-6\tMgO\tfalse\ticsd:synthetic\t.\n" *
        "mp-7\tNaClF\ttrue\t.\t.\n" *
        "mp-8\t.\tfalse\ticsd:synthetic\tfractional_counts\n" *
        "mp-9\tXxTiO3\ttrue\t.\t.\n" *
        "mp-10\tNa2SiO3\tfalse\ticsd:synthetic\t.\n" *
        "mp-11\tLi2SiO3\tfalse\ticsd:synthetic\t.\n" *
        "mp-12\tK2SiO3\tfalse\ticsd:synthetic\t.\n" *
        "mp-13\tCaSiO3\tfalse\ticsd:synthetic\t.\n"
    mktempdir() do dir
        snapshot = mp_test_snapshot(dir, body)
        output = joinpath(dir, "audit")
        result = audit_mp_snapshot(snapshot, output)
        s = result.summary
        @test s["total_records"] == 13
        @test s["included_records"] == 9 && s["excluded_records"] == 4
        @test s["unique_compositions"] == 7 && s["collapsed_extra_records"] == 2
        @test s["positive_compositions"] == 5
        @test s["unlabelled_compositions"] == 1 && s["unresolved_compositions"] == 1
        @test s["mixed_flag_compositions"] == 1
        @test s["positive_holdout_20_percent_floor"] == 1 && s["has_minimum_pilot_data"]
        @test s["records_missing_flag"] == 1
        @test s["exclusion_reasons"]["outside_oxygen_ternary_scope"] == 2
        @test s["exclusion_reasons"]["unsupported_formula"] == 1
        @test s["exclusion_reasons"]["normalization_issue"] == 1
        group = only(filter(c -> c.composition == "Al2Mg1O4", result.compositions))
        @test group.label == "positive" && group.material_ids == "mp-1;mp-2"
        @test only(filter(c -> c.composition == "Ba1O3Ti1", result.compositions)).label == "unresolved"
        @test occursin("Synthetic software fixture", read(joinpath(output, "audit.md"), String))
        @test TOML.parsefile(joinpath(output, "audit.toml")) == s
        @test Set(readdir(output)) == Set(["audit.md", "audit.toml", "compositions.tsv", "excluded.tsv", "snapshot.toml"])
        original = Dict(f => read(joinpath(output, f)) for f in readdir(output))
        @test_throws ArgumentError audit_mp_snapshot(snapshot, output)
        @test all(read(joinpath(output, f)) == bytes for (f, bytes) in original)
        audit_mp_snapshot(snapshot, joinpath(dir, "rerun"))
        @test all(read(joinpath(dir, "rerun", f)) == bytes for (f, bytes) in original)
        @test run_cli(["audit-mp", "--snapshot", snapshot, "--output", joinpath(dir, "cli")])[1] == 0
        @test run_cli(["audit-mp", "--snapshot", snapshot, "--output", output])[1] == 2
        write(joinpath(snapshot, "records.tsv"), "tampered")
        @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "bad"))
        @test !ispath(joinpath(dir, "bad"))
    end
    @test run_cli(["audit-mp", "--help"])[1] == 0
    @test run_cli(["audit-mp"])[1] == 2
    for overrides in (Dict("schema_version" => 2), Dict("query_include_gnome" => true),
            Dict("record_count" => 100), Dict("jsonl_sha256" => "bad"),
            Dict("query_elements" => ["F"]), Dict("is_synthetic" => "false"),
            Dict("redistribution_status" => ""))
        mktempdir() do dir
            snapshot = mp_test_snapshot(dir, body; overrides)
            @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
            @test !ispath(joinpath(dir, "audit"))
        end
    end
    for bad in ("mp-1\tCaTiO3\tfalse\t.\t.\nmp-1\tCaTiO3\tfalse\t.\t.\n",
            "mp-1\tCaTiO3\t0\t.\t.\n", "mp-1\tCaTiO3\ttrue\t.\n", "")
        mktempdir() do dir
            snapshot = mp_test_snapshot(dir, bad)
            @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
        end
    end
    mktempdir() do dir
        snapshot = mp_test_snapshot(dir, "mp-1\tMgO\tfalse\t.\t.\n")
        result = audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
        @test result.summary["unique_compositions"] == 0
        @test !result.summary["has_minimum_pilot_data"]
    end
end
