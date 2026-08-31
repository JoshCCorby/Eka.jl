const MP_AUDIT_HEADER = "material_id\tcomposition\ttheoretical\tsource_ids\tnormalization_issue"

"""
    audit_mp_snapshot(snapshot, output)

Audit a snapshot produced by scripts/export_mp_pilot.py. Group material records
by canonical composition before any future split. Labels are `positive` (any
explicit theoretical=false), `unlabelled` (all true), or `unresolved` (otherwise).
Missing provenance never becomes a negative. No ranking or discovery claim is made.
"""
function audit_mp_snapshot(snapshot::AbstractString, output::AbstractString)
    target = abspath(output)
    (ispath(target) || islink(target)) && throw(ArgumentError("refusing to overwrite existing audit: $target"))
    isdir(dirname(target)) || throw(ArgumentError("audit parent directory does not exist"))
    metadata_bytes = read(joinpath(snapshot, "snapshot.toml"))
    metadata = try
        TOML.parse(String(copy(metadata_bytes)))
    catch error
        error isa TOML.ParserError || rethrow()
        throw(ArgumentError("invalid snapshot.toml"))
    end
    get(metadata, "schema_version", nothing) === 1 || throw(ArgumentError("unsupported MP snapshot schema"))
    get(metadata, "query_include_gnome", nothing) === false || throw(ArgumentError("snapshot must explicitly exclude GNoME"))
    get(metadata, "query_deprecated", nothing) === false || throw(ArgumentError("snapshot must explicitly exclude deprecated records"))
    get(metadata, "query_elements", nothing) == ["O"] || throw(ArgumentError("snapshot must query oxygen"))
    get(metadata, "query_num_elements", nothing) === 3 || throw(ArgumentError("snapshot must query ternaries"))
    get(metadata, "is_synthetic", nothing) isa Bool || throw(ArgumentError("snapshot must declare is_synthetic"))
    for key in ("database_version", "redistribution_status")
        value = get(metadata, key, nothing)
        value isa String && !isempty(strip(value)) || throw(ArgumentError("snapshot must declare $key"))
    end
    records_bytes = read(joinpath(snapshot, "records.tsv"))
    bytes2hex(sha256(records_bytes)) == get(metadata, "records_sha256", nothing) ||
        throw(ArgumentError("records.tsv SHA-256 does not match snapshot metadata"))
    # Bind the derived TSV to a preserved selected-API-record snapshot. This checks
    # integrity, not authenticity or legal permission to redistribute the source.
    raw_bytes = read(joinpath(snapshot, "records.jsonl"))
    bytes2hex(sha256(raw_bytes)) == get(metadata, "jsonl_sha256", nothing) ||
        throw(ArgumentError("records.jsonl SHA-256 does not match snapshot metadata"))
    rows = benchmark_table(records_bytes, MP_AUDIT_HEADER, "MP snapshot")
    isempty(rows) && throw(ArgumentError("snapshot is empty"))
    count_value = get(metadata, "record_count", nothing)
    count_value isa Integer && !(count_value isa Bool) && count_value == length(rows) ||
        throw(ArgumentError("snapshot record_count does not match records.tsv"))
    seen = Set{String}()
    grouped = Dict{Composition,Vector{NamedTuple}}()
    excluded = NamedTuple[]
    reason_counts = Dict{String,Int}()
    for (id, raw_formula, flag, sources, issue) in rows
        # Accept legacy numeric IDs and modern AlphaIDs, preserving source spelling.
        occursin(r"\Amp-(?:[0-9]+|[a-z]+)\z", id) || throw(ArgumentError("invalid material_id: $id"))
        id in seen && throw(ArgumentError("duplicate material_id: $id"))
        push!(seen, id)
        flag in ("true", "false", "unknown") || throw(ArgumentError("invalid theoretical flag for $id"))
        reason, composition = nothing, nothing
        if issue != "."
            reason = "normalization_issue"
        else
            try
                composition = Composition(raw_formula)
            catch error
                error isa ArgumentError || rethrow()
                reason = "unsupported_formula"
            end
            if composition !== nothing && !(length(composition) == 3 && "O" in species(composition))
                reason = "outside_oxygen_ternary_scope"
            end
        end
        if reason !== nothing
            reason_counts[reason] = get(reason_counts, reason, 0) + 1
            push!(excluded, (material_id=String(id), composition=String(raw_formula),
                reason=reason, normalization_issue=String(issue)))
            continue
        end
        push!(get!(grouped, composition, NamedTuple[]),
            (material_id=String(id), theoretical=String(flag), source_ids=String(sources)))
    end
    compositions = NamedTuple[]
    for c in sort!(collect(keys(grouped)); by=formula)
        records = sort!(grouped[c]; by=r -> r.material_id)
        n_exp = count(r -> r.theoretical == "false", records)
        n_theory = count(r -> r.theoretical == "true", records)
        n_unknown = length(records) - n_exp - n_theory
        label = n_exp > 0 ? "positive" : n_unknown > 0 ? "unresolved" : "unlabelled"
        push!(compositions, (composition=formula(c), chemical_system=chemical_system(c),
            label=label, record_count=length(records), experimental_records=n_exp,
            theoretical_records=n_theory, unknown_records=n_unknown,
            material_ids=join((r.material_id for r in records), ';'),
            source_ids=join(sort!(unique([r.source_ids for r in records if r.source_ids != "."])), ';')))
    end
    valid_count = sum((c.record_count for c in compositions); init=0)
    summary = Dict{String,Any}(
        "schema_version" => 1, "database_version" => metadata["database_version"],
        "is_synthetic" => metadata["is_synthetic"],
        "scope" => "oxygen-containing ternaries; not oxidation-state-validated oxides",
        "redistribution_status" => metadata["redistribution_status"],
        "records_sha256" => metadata["records_sha256"],
        "snapshot_metadata_sha256" => bytes2hex(sha256(metadata_bytes)),
        "audit_code_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "composition_code_sha256" => bytes2hex(sha256(read(joinpath(@__DIR__, "compositions.jl")))),
        "julia_version" => string(VERSION), "package_version" => string(Base.pkgversion(@__MODULE__)),
        "total_records" => length(rows), "included_records" => valid_count,
        "excluded_records" => length(excluded), "exclusion_reasons" => reason_counts,
        "unique_compositions" => length(compositions),
        "collapsed_extra_records" => valid_count - length(compositions),
        "positive_compositions" => count(c -> c.label == "positive", compositions),
        "unlabelled_compositions" => count(c -> c.label == "unlabelled", compositions),
        "unresolved_compositions" => count(c -> c.label == "unresolved", compositions),
        "mixed_flag_compositions" => count(c -> c.experimental_records > 0 && c.theoretical_records > 0, compositions),
        "records_missing_flag" => count(r -> r[3] == "unknown", rows),
        "records_missing_source_ids" => count(r -> r[4] == ".", rows),
    )
    summary["positive_holdout_20_percent_floor"] = fld(summary["positive_compositions"], 5)
    summary["eligible_pu_compositions"] = summary["positive_compositions"] + summary["unlabelled_compositions"]
    summary["has_minimum_pilot_data"] = summary["positive_holdout_20_percent_floor"] >= 1 && summary["unlabelled_compositions"] >= 1
    # Existence of data is only a feasibility signal, never a power calculation.
    mkdir(target)
    try
        write(joinpath(target, "snapshot.toml"), metadata_bytes)
        open(joinpath(target, "audit.toml"), "w") do io
            TOML.print(io, summary; sorted=true)
        end
        open(joinpath(target, "compositions.tsv"), "w") do io
            println(io, "composition\tchemical_system\tlabel\trecord_count\texperimental_records\ttheoretical_records\tunknown_records\tmaterial_ids\tsource_ids")
            for c in compositions
                println(io, join(values(c), '\t'))
            end
        end
        open(joinpath(target, "excluded.tsv"), "w") do io
            println(io, "material_id\tcomposition\treason\tnormalization_issue")
            for row in sort!(excluded; by=r -> r.material_id)
                println(io, join(values(row), '\t'))
            end
        end
        open(joinpath(target, "audit.md"), "w") do io
            println(io, "# MP pilot data audit\n")
            println(io, metadata["is_synthetic"] ? "**Synthetic software fixture. Not an MP measurement.**\n" :
                "MP snapshot feasibility audit. No ranking experiment has been performed.\n")
            println(io, "Scope: oxygen plus exactly two other elements. Oxide chemistry/charge neutrality is not verified.\n")
            println(io, "| Quantity | Count |\n| --- | --- |")
            for key in ("total_records", "included_records", "excluded_records", "unique_compositions",
                    "collapsed_extra_records", "positive_compositions", "unlabelled_compositions",
                    "unresolved_compositions", "mixed_flag_compositions", "records_missing_flag",
                    "records_missing_source_ids", "positive_holdout_20_percent_floor")
                println(io, "| ", replace(key, '_' => ' '), " | ", summary[key], " |")
            end
            println(io, "\nPositive means at least one record explicitly has theoretical=false. It is an experimental-provenance proxy.")
            println(io, "All-true compositions are unlabelled, never confirmed failures. Missing flags without a positive produce unresolved compositions.")
            println(io, "Different structures can legitimately have different flags; a positive record takes precedence within a composition.")
            println(io, "Unsupported formulas and rows outside scope are itemized in excluded.tsv. No occupancy rounding is performed.\n")
            println(io, "The 20% holdout count is floor(positive compositions / 5), not a power calculation or an actual split.")
            println(io, "No discovery years are inferred. Source IDs and theoretical flags do not establish score-training independence.")
            println(io, "GNoME exclusion is recorded as an API query condition, not a licence certification. Review source terms before redistributing.\n")
            println(io, "Next: freeze the chemistry definition and snapshot; review exclusions and source terms; implement explicit PU recovery splits/metrics.")
            println(io, "Keep this audit with its original snapshot. The hashes establish file integrity, not upstream authenticity.")
        end
    catch
        rm(target; recursive=true)
        rethrow()
    end
    return (path=target, summary=summary, compositions=compositions, excluded=excluded)
end

function mp_audit_main(args; out::IO)
    settings = ArgParseSettings(prog="eka audit-mp", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Audit an MP pilot snapshot without interpreting unlabelled compounds as failures.")
    @add_arg_table! settings begin
        "--help", "-h"
            action = :store_true
            help = "Show MP audit help"
        "--snapshot"
            arg_type = String
            required = true
            help = "Directory containing records.tsv, records.jsonl, and snapshot.toml"
        "--output"
            arg_type = String
            required = true
            help = "New audit directory; parent must exist"
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    parsed = parse_args(args, settings)
    report = audit_mp_snapshot(parsed["snapshot"], parsed["output"])
    println(out, "Audited ", report.summary["total_records"], " records: ",
        report.summary["positive_compositions"], " positive, ", report.summary["unlabelled_compositions"],
        " unlabelled, ", report.summary["unresolved_compositions"], " unresolved compositions; report: ", report.path)
    return 0
end
