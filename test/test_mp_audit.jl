function mp_test_snapshot(dir, body; overrides=Dict{String,Any}())
    snapshot = joinpath(dir, "snapshot")
    mkdir(snapshot)
    bytes = Eka.MP_AUDIT_HEADER * "\n" * body
    write(joinpath(snapshot, "records.tsv"), bytes)
    documents = Dict{String,Any}[]
    for line in split(chomp(body), '\n'; keepempty=false)
        fields = split(line, '\t')
        if length(fields) != 5
            push!(documents, Dict("material_id" => "mp-malformed", "composition" => Dict("Ca" => 1,
                "Ti" => 1, "O" => 3), "formula_pretty" => "synthetic", "theoretical" => false,
                "database_IDs" => Dict{String,Vector{String}}(), "deprecated" => false))
            continue
        end
        id, formula_value, flag, sources, issue = fields
        composition = if issue == "fractional_counts"
            Dict("O" => 1.5)
        elseif formula_value == "."
            nothing
        else
            Dict(match.captures[1] =>
                    (isempty(match.captures[2]) ? 1 : parse(Int, match.captures[2]))
                for match in eachmatch(r"([A-Z][a-z]?)([0-9]*)", formula_value))
        end
        database_ids = Dict{String,Vector{String}}()
        if sources != "."
            for entry in split(sources, ';')
                source, source_id = split(entry, ':'; limit=2)
                push!(get!(database_ids, source, String[]), source_id)
            end
        end
        push!(documents, Dict("material_id" => id, "composition" => composition,
            "formula_pretty" => "synthetic", "theoretical" =>
                flag == "unknown" ? nothing : flag == "true",
            "database_IDs" => database_ids, "deprecated" => false))
    end
    raw = join((JSON3.write(document) for document in documents), '\n') *
        (isempty(documents) ? "" : "\n")
    write(joinpath(snapshot, "records.jsonl"), raw)
    metadata = Dict{String,Any}("schema_version" => 1, "database_version" => "synthetic-v1",
        "query_include_gnome" => false, "query_deprecated" => false,
        "query_elements" => ["O"], "query_num_elements" => 3, "is_synthetic" => true,
        "dataset" => "Materials Project",
        "endpoint" => "https://api.materialsproject.org/materials/summary/",
        "scope" => "oxygen-containing ternaries; not oxidation-state-validated oxides",
        "fields" => Eka.MP_SNAPSHOT_FIELDS, "retrieved_at_utc" => "2026-01-01T00:00:00+00:00",
        "mp_api_version" => "synthetic", "python_version" => "3.11.0",
        "exporter_sha256" => repeat("0", 64),
        "normalization" => "exact positive integral element counts only; Julia reduces ratios",
        "date_policy" => "no first-discovery dates inferred from database timestamps",
        "terms_url" => "https://materialsproject.org/about/terms",
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
            Dict("redistribution_status" => ""), Dict("dataset" => "Elsewhere"),
            Dict("fields" => ["material_id"]), Dict("exporter_sha256" => "unknown"))
        mktempdir() do dir
            snapshot = mp_test_snapshot(dir, body; overrides)
            @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
            @test !ispath(joinpath(dir, "audit"))
        end
    end
    for missing_key in ("dataset", "endpoint", "fields", "retrieved_at_utc",
            "mp_api_version", "python_version", "exporter_sha256", "terms_url")
        mktempdir() do dir
            snapshot = mp_test_snapshot(dir, body)
            metadata = TOML.parsefile(joinpath(snapshot, "snapshot.toml"))
            delete!(metadata, missing_key)
            open(joinpath(snapshot, "snapshot.toml"), "w") do io
                TOML.print(io, metadata; sorted=true)
            end
            @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
        end
    end
    mktempdir() do dir
        snapshot = mp_test_snapshot(dir, body)
        raw_path = joinpath(snapshot, "records.jsonl")
        documents = [JSON3.read(line, Dict{String,Any}) for line in eachline(raw_path)]
        documents[1]["theoretical"] = true
        raw = join((JSON3.write(document) for document in documents), '\n') * "\n"
        write(raw_path, raw)
        metadata = TOML.parsefile(joinpath(snapshot, "snapshot.toml"))
        metadata["jsonl_sha256"] = bytes2hex(sha256(raw))
        open(joinpath(snapshot, "snapshot.toml"), "w") do io
            TOML.print(io, metadata; sorted=true)
        end
        @test_throws ArgumentError audit_mp_snapshot(snapshot, joinpath(dir, "audit"))
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
