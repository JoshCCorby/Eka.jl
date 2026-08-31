# Day 2: composition-safe membership only. No ranking or PU metric evaluation.
const MP_RECOVERY_PROTOCOL = "eka-mp-recovery-v1"
const MP_RECOVERY_ALGORITHM = "eka-pu-split-v1"
const MP_RECOVERY_SCOPE = "oxygen-containing ternaries; not oxidation-state-validated oxides"
const MP_RECOVERY_GROUP_HEADER = "composition\tchemical_system\tlabel\trecord_count\texperimental_records\ttheoretical_records\tunknown_records\tmaterial_ids\tsource_ids"
const MP_RECOVERY_PROTOCOL_SHA256 = "f64c1fb803da3cc57aff658341b299824e3d662cc48039586a8bc10410bab21f"
# Explicit versioned pins; retaining the v1 alias preserves its public identity.
const MP_RECOVERY_PROTOCOLS = (
    "eka-mp-recovery-v1" => (file="mp-recovery-protocol.md", sha256=MP_RECOVERY_PROTOCOL_SHA256),
    "eka-mp-label-sensitivity-v1" => (file="mp-label-sensitivity-protocol.md",
        sha256="f577444465292b6f1099e2650eec22106aebfb2ce3b970b86a5a037bc578a09f"),
)

function recovery_protocol(id::AbstractString)
    index = findfirst(pair -> first(pair) == id, MP_RECOVERY_PROTOCOLS)
    index === nothing && throw(ArgumentError("unknown recovery protocol: $id"))
    pin = last(MP_RECOVERY_PROTOCOLS[index])
    bytes = read(joinpath(@__DIR__, "..", "docs", pin.file))
    bytes2hex(sha256(bytes)) == pin.sha256 || throw(ArgumentError("protocol document differs from frozen $id contract"))
    return (; id, pin.file, pin.sha256, bytes)
end
# These identities are frozen in docs/mp-recovery-protocol.md, not inferred from
# whichever metadata the caller supplies. New real data requires a new protocol.
const MP_RECOVERY_INPUT_HASHES = (
    "snapshot/snapshot.toml" => "5c82fb38f90105a03779daab0cb32f2ba134cb1ce50cf94e845b38e92719ad58",
    "snapshot/records.tsv" => "98a6ce78d592e5e7e4cef98d675badcf991cc2caecef9a6b0ec10c1e08731a08",
    "snapshot/records.jsonl" => "5ba17f307d61c9635a93f75fe86afc9e81af430036f3ef1fc0fe199a75f3829b",
    "audit/audit.toml" => "c63f465ab9104508b5a08f4a3263d267842b06d94954d0479e3662da7268eefa",
    "audit/compositions.tsv" => "722ecf2e40a99c59b0f024219782a1fe8791f000353cd5e6cf7faa1ef6e5213d",
)

function recovery_integers(values, name; minimum=0, maximum=typemax(Int))
    values isa Union{Number,AbstractString} && throw(ArgumentError("$name must be a collection"))
    result = Int[]
    for value in values
        value isa Integer && !(value isa Bool) && minimum <= value <= maximum ||
            throw(ArgumentError("$name must contain integers in $minimum:$maximum"))
        push!(result, Int(value))
    end
    isempty(result) && throw(ArgumentError("$name must not be empty"))
    length(unique(result)) == length(result) || throw(ArgumentError("duplicate $name"))
    return sort!(result)
end

"""
    mp_recovery_splits(groups; seeds=0:19, budgets=[20, 50, 100, 200])

Pure membership calculation for `(composition, label)` rows, with labels
`positive`, `unlabelled`, or `unresolved`. Canonical duplicates are errors, even
across labels. Hold out floor(P/5) positive compositions using the frozen v1
SHA-256 ordering; exclude training positives and unresolved groups from the pool.

Returns splits with `inputs=(training, candidates)` containing compositions only,
and a separate `evaluation=(heldout, labels)` whose labels align with candidates.
This helper cannot establish source provenance. Use `split_mp_recovery` for saved
snapshot/audit inputs. Non-default seeds/budgets support synthetic fixtures only
in the file-based API. No RNG, ranking, evaluation, or filesystem access occurs.
"""
function mp_recovery_splits(groups; seeds=0:19, budgets=[20, 50, 100, 200])
    seeds = recovery_integers(seeds, "seeds"; maximum=typemax(Int) - 10000)
    budgets = recovery_integers(budgets, "budgets"; minimum=1)
    positives, unlabelled, unresolved = Composition[], Composition[], Composition[]
    seen = Set{Composition}()
    for row in groups
        row isa Union{Tuple,NamedTuple} && length(row) == 2 ||
            throw(ArgumentError("groups must contain (composition, label) pairs"))
        c = row[1] isa Composition ? row[1] : Composition(row[1])
        length(c) == 3 && "O" in species(c) || throw(ArgumentError("group outside oxygen-containing ternary scope"))
        c in seen && throw(ArgumentError("duplicate canonical composition: $(formula(c))"))
        push!(seen, c)
        label = row[2]
        label in ("positive", "unlabelled", "unresolved") || throw(ArgumentError("invalid PU label: $label"))
        push!(label == "positive" ? positives : label == "unlabelled" ? unlabelled : unresolved, c)
    end
    for rows in (positives, unlabelled, unresolved)
        sort!(rows; by=formula)
    end
    h = fld(length(positives), 5)
    h >= 1 && length(positives) - h >= 1 && !isempty(unlabelled) ||
        throw(ArgumentError("recovery requires >= 5 positives and >= 1 unlabelled composition"))
    maximum(budgets) <= h + length(unlabelled) || throw(ArgumentError("budget exceeds recovery candidate pool"))
    splits = map(seeds) do seed
        order = sortperm(positives; by=c ->
            (bytes2hex(sha256("$MP_RECOVERY_ALGORITHM\n$seed\n$(formula(c))")), formula(c)))
        heldout = sort!(positives[order[1:h]]; by=formula)
        training = sort!(positives[order[h+1:end]]; by=formula)
        candidates = sort!(vcat(heldout, unlabelled); by=formula)
        heldout_set = Set(heldout)
        labels = [c in heldout_set ? "positive" : "unlabelled" for c in candidates]
        return (seed=seed, inputs=(training=training, candidates=candidates),
            evaluation=(heldout=heldout, labels=labels))
    end
    return (splits=splits, seeds=seeds, budgets=budgets,
        positive_count=length(positives), unlabelled_count=length(unlabelled),
        unresolved=unresolved)
end

function recovery_toml(bytes, label)
    try
        return TOML.parse(String(copy(bytes)))
    catch error
        error isa TOML.ParserError || rethrow()
        throw(ArgumentError("invalid $label TOML"))
    end
end

# Audit source_ids can be empty. Do not use the binary benchmark's stricter TSV
# parser, which disallows every empty cell. Canonical keys reject equivalent rows.
function recovery_group_rows(bytes)
    lines = split(String(copy(bytes)), '\n'; keepempty=true)
    !isempty(lines) && isempty(last(lines)) && pop!(lines)
    lines = [endswith(line, "\r") ? chop(line; tail=1) : String(line) for line in lines]
    !isempty(lines) && first(lines) == MP_RECOVERY_GROUP_HEADER ||
        throw(ArgumentError("invalid audited composition header"))
    rows = Dict{String,Vector{String}}()
    for line in lines[2:end]
        row = String.(split(line, '\t'; keepempty=true))
        length(row) == 9 && all(!isempty, row[1:8]) || throw(ArgumentError("malformed audited composition row"))
        f = formula(Composition(row[1]))
        haskey(rows, f) && throw(ArgumentError("duplicate canonical audited composition: $f"))
        row[1] = f
        rows[f] = row
    end
    return rows
end

function recovery_verified_inputs(snapshot, audit; synthetic)
    files = Dict{String,Vector{UInt8}}()
    for (prefix, directory, names) in (
        ("snapshot", snapshot, ("snapshot.toml", "records.tsv", "records.jsonl")),
        ("audit", audit, ("snapshot.toml", "audit.toml", "compositions.tsv", "excluded.tsv")))
        for name in names
            files["$prefix/$name"] = read(joinpath(directory, name))
        end
    end
    metadata = recovery_toml(files["snapshot/snapshot.toml"], "snapshot")
    get(metadata, "is_synthetic", nothing) === synthetic ||
        throw(ArgumentError("synthetic mode must exactly match snapshot is_synthetic"))
    files["snapshot/snapshot.toml"] == files["audit/snapshot.toml"] ||
        throw(ArgumentError("audit snapshot metadata differs from original snapshot"))
    if !synthetic
        for (name, expected) in MP_RECOVERY_INPUT_HASHES
            bytes2hex(sha256(files[name])) == expected ||
                throw(ArgumentError("$name does not match the frozen recovery protocol"))
        end
    end
    # Require the exporting implementation too; a digest written by unknown code
    # is not silently treated as sufficient provenance.
    exporter = read(joinpath(@__DIR__, "..", "scripts", "export_mp_pilot.py"))
    get(metadata, "exporter_sha256", nothing) == bytes2hex(sha256(exporter)) ||
        throw(ArgumentError("snapshot exporter hash differs from the current exporter"))
    supplied = recovery_toml(files["audit/audit.toml"], "audit")
    groups = recovery_group_rows(files["audit/compositions.tsv"])
    # Reaudit captured bytes, not mutable input paths. Existing audit code verifies
    # snapshot schema, record/jsonl hashes, query filters and record normalization.
    # It is left unchanged to preserve the Day 1 implementation hashes.
    mktempdir() do temporary
        copied = joinpath(temporary, "snapshot")
        mkdir(copied)
        for name in ("snapshot.toml", "records.tsv", "records.jsonl")
            write(joinpath(copied, name), files["snapshot/$name"])
        end
        rebuilt = audit_mp_snapshot(copied, joinpath(temporary, "audit"))
        # Runtime version strings may differ on another supported Julia version;
        # every scientific/schema/provenance field must match exactly.
        for key in ("julia_version", "package_version")
            get(supplied, key, nothing) isa String && !isempty(supplied[key]) ||
                throw(ArgumentError("audit must record $key"))
        end
        stable(d) = Dict(k => v for (k, v) in d if !(k in ("julia_version", "package_version")))
        stable(supplied) == stable(rebuilt.summary) || throw(ArgumentError("audit metadata/counts/code hashes differ from rebuilt audit"))
        groups == recovery_group_rows(read(joinpath(rebuilt.path, "compositions.tsv"))) ||
            throw(ArgumentError("audited groups differ from snapshot records"))
        files["audit/excluded.tsv"] == read(joinpath(rebuilt.path, "excluded.tsv")) ||
            throw(ArgumentError("audit exclusions differ from snapshot records"))
    end
    return (files=files, metadata=metadata, summary=supplied,
        groups=[(row[1], row[3]) for row in values(groups)])
end

recovery_formulas(rows) = "composition\n" * join((formula(c) * "\n" for c in rows))
function recovery_write_toml(path, content)
    open(path, "w") do io
        TOML.print(io, content; sorted=true)
    end
end

"""
    split_mp_recovery(snapshot, audit, output; synthetic=false,
                      seeds=0:19, budgets=[20, 50, 100, 200])

Verify snapshot and audit provenance, then save all deterministic membership
splits in a NEW directory. Real mode is pinned to the Day 1 input hashes, protocol,
20 seeds and four budgets. Explicit synthetic mode requires a synthetic snapshot
and keeps its identity distinct; it does not certify real data provenance.

Saved ranker inputs contain formulas only. Evaluation labels, holdouts, input and
implementation hashes, counts, and manifest hashes are recorded separately. No
existing directory (including a dangling symlink) is overwritten. On failure,
remove only the new output directory reserved by this invocation.
"""
function split_mp_recovery(snapshot::AbstractString, audit::AbstractString, output::AbstractString;
        synthetic::Bool=false, seeds=0:19, budgets=[20, 50, 100, 200])
    target = abspath(output)
    (ispath(target) || islink(target)) && throw(ArgumentError("refusing to overwrite recovery output: $target"))
    isdir(dirname(target)) || throw(ArgumentError("recovery output parent must exist"))
    seeds = recovery_integers(seeds, "seeds"; maximum=typemax(Int) - 10000)
    budgets = recovery_integers(budgets, "budgets"; minimum=1)
    if !synthetic && (seeds != collect(0:19) || budgets != [20, 50, 100, 200])
        throw(ArgumentError("real recovery must use frozen seeds 0:19 and budgets 20,50,100,200"))
    end
    protocol_bytes = recovery_protocol(MP_RECOVERY_PROTOCOL).bytes
    source = recovery_verified_inputs(snapshot, audit; synthetic)
    result = mp_recovery_splits(source.groups; seeds, budgets)
    # Preserve the exact relevant source bytes, including a dirty implementation,
    # without requiring a git executable or writing a user's repository metadata.
    code = Dict(name => read(joinpath(@__DIR__, "..", name)) for name in (
        "src/mp_recovery.jl", "src/mp_audit.jl", "src/compositions.jl", "src/benchmark.jl",
        "src/Eka.jl", "src/cli.jl", "scripts/export_mp_pilot.py", "Project.toml"))
    manifest = Dict{String,Any}(
        "schema_version" => 1, "protocol_id" => synthetic ? "eka-mp-recovery-synthetic-v1" : MP_RECOVERY_PROTOCOL,
        "protocol_sha256" => bytes2hex(sha256(protocol_bytes)), "scope" => MP_RECOVERY_SCOPE,
        "split_algorithm" => MP_RECOVERY_ALGORITHM, "is_synthetic" => synthetic,
        "split_seeds" => seeds, "ranking_seeds" => seeds .+ 10000, "tie_seed" => 20260901,
        "budgets" => budgets, "holdout_divisor" => 5, "split_count" => length(seeds),
        "positive_count" => result.positive_count, "unlabelled_count" => result.unlabelled_count,
        "unresolved_count" => length(result.unresolved), "excluded_record_count" => source.summary["excluded_records"],
        "database_version" => source.metadata["database_version"],
        "redistribution_status" => source.metadata["redistribution_status"],
        "julia_version" => string(VERSION), "package_version" => string(Base.pkgversion(@__MODULE__)),
        "input_hashes" => Dict(name => bytes2hex(sha256(bytes)) for (name, bytes) in source.files),
        "implementation_hashes" => Dict(name => bytes2hex(sha256(bytes)) for (name, bytes) in code),
        "membership_format" => "UTF-8; LF; header and trailing LF; canonical formula order",
        "split_manifest_hashes" => Dict{String,String}())
    # mkdir is the exclusive reservation. Do not put it inside the cleanup block:
    # if another writer wins the race, its directory must never be removed.
    mkdir(target)
    try
        mkdir(joinpath(target, "provenance"))
        write(joinpath(target, "provenance", "protocol.md"), protocol_bytes)
        for (name, bytes) in source.files
            # Original raw snapshot remains alongside its audit; do not duplicate
            # the JSONL/TSV export for every split bundle.
            name in ("snapshot/records.tsv", "snapshot/records.jsonl") && continue
            path = joinpath(target, "provenance", name)
            mkpath(dirname(path))
            write(path, bytes)
        end
        for (name, bytes) in code
            path = joinpath(target, "provenance", "implementation", name)
            mkpath(dirname(path))
            write(path, bytes)
        end
        write(joinpath(target, "provenance", "unresolved.tsv"), recovery_formulas(result.unresolved))
        for split in result.splits
            name = "split-$(lpad(split.seed, 2, '0'))"
            directory = joinpath(target, name)
            mkpath(joinpath(directory, "inputs"))
            mkdir(joinpath(directory, "evaluation"))
            payloads = Dict(
                "inputs/training.tsv" => recovery_formulas(split.inputs.training),
                "inputs/candidates.tsv" => recovery_formulas(split.inputs.candidates),
                "evaluation/heldout.tsv" => recovery_formulas(split.evaluation.heldout),
                "evaluation/labels.tsv" => "composition\tlabel\n" * join(
                    "$(formula(c))\t$label\n" for (c, label) in zip(split.inputs.candidates, split.evaluation.labels)))
            for (file, bytes) in payloads
                write(joinpath(directory, file), bytes)
            end
            config = Dict{String,Any}(
                "schema_version" => 1, "protocol_id" => manifest["protocol_id"],
                "protocol_sha256" => manifest["protocol_sha256"], "scope" => MP_RECOVERY_SCOPE,
                "is_synthetic" => synthetic, "split_algorithm" => MP_RECOVERY_ALGORITHM,
                "split_seed" => split.seed, "ranking_seed" => split.seed + 10000, "tie_seed" => 20260901,
                "budgets" => budgets, "training_count" => length(split.inputs.training),
                "heldout_count" => length(split.evaluation.heldout), "candidate_count" => length(split.inputs.candidates),
                "unlabelled_count" => result.unlabelled_count, "unresolved_count" => length(result.unresolved),
                "input_hashes" => manifest["input_hashes"], "implementation_hashes" => manifest["implementation_hashes"],
                "membership_hashes" => Dict(file => bytes2hex(sha256(bytes)) for (file, bytes) in payloads))
            path = joinpath(directory, "manifest.toml")
            recovery_write_toml(path, config)
            manifest["split_manifest_hashes"]["$name/manifest.toml"] = bytes2hex(sha256(read(path)))
        end
        recovery_write_toml(joinpath(target, "manifest.toml"), manifest)
        write(joinpath(target, "README.md"), """
        # MP recovery splits

        $(synthetic ? "Synthetic software fixture; not MP evidence." : "Frozen MP composition holdouts; local data, redistribution not cleared.")
        $(length(seeds)) splits; protocol $(manifest["protocol_id"]); algorithm $MP_RECOVERY_ALGORITHM.
        Each split has $(length(first(result.splits).inputs.training)) training positives,
        $(length(first(result.splits).evaluation.heldout)) held-out positives and
        $(length(first(result.splits).inputs.candidates)) candidates.

        Rankers may read only split-*/inputs/training.tsv and inputs/candidates.tsv.
        Evaluation labels and heldouts are separate. Unlabelled is not negative.
        Composition holdout does not guarantee unseen chemical systems.
        No rankings, evaluation metrics or discovery claims have been produced.

        Manifests hash the original inputs, implementation files, and saved membership.
        Preserve the original snapshot records.tsv and records.jsonl alongside this
        bundle. Provenance copies contain labels and must not be scoring features.
        Files are reproducible for the same inputs, source bytes and Julia/package
        versions; paths and wall-clock timestamps are not embedded in manifests.
        Regenerate into a new directory; existing outputs are never overwritten.
        """)
    catch
        rm(target; recursive=true)
        rethrow()
    end
    return (path=target, result=result, manifest=manifest)
end

function mp_recovery_main(args; out::IO)
    settings = ArgParseSettings(prog="eka split-mp", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Generate composition-safe MP recovery splits; no ranking.")
    @add_arg_table! settings begin
        "--help", "-h"
            action = :store_true
        "--snapshot"
            arg_type = String
            required = true
            help = "Preserved original snapshot directory"
        "--audit"
            arg_type = String
            required = true
            help = "Audit generated from this snapshot"
        "--output"
            arg_type = String
            required = true
            help = "New local output directory; parent must exist"
        "--synthetic"
            action = :store_true
            help = "Require synthetic inputs; never bypass checks for real inputs"
        "--seeds"
            arg_type = Int
            nargs = '+'
            default = collect(0:19)
            help = "Split seeds; overrides permitted only for synthetic inputs"
        "--budget"
            arg_type = Int
            nargs = '+'
            default = [20, 50, 100, 200]
            help = "Planned budgets; overrides permitted only for synthetic inputs"
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    parsed = parse_args(args, settings)
    report = split_mp_recovery(parsed["snapshot"], parsed["audit"], parsed["output"];
        synthetic=parsed["synthetic"], seeds=parsed["seeds"], budgets=parsed["budget"])
    println(out, "Generated ", length(report.result.splits), " composition-safe splits; no rankings; output: ", report.path)
    return 0
end
