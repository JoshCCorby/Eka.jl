# Separate PU evaluation. The binary benchmark contract is unchanged.
const PU_METHODS = ("random", "popularity", "similarity")
const PU_MEMBER_FILES = ("inputs/training.tsv", "inputs/candidates.tsv",
    "evaluation/heldout.tsv", "evaluation/labels.tsv")
const PU_PRODUCER_FILES = ("src/mp_recovery.jl", "src/mp_audit.jl", "src/compositions.jl",
    "src/benchmark.jl", "src/Eka.jl", "src/cli.jl", "scripts/export_mp_pilot.py", "Project.toml")

pu_check(condition, message) = condition || throw(ArgumentError(message))
function pu_match(actual, expected, label)
    actual isa AbstractDict || throw(ArgumentError("$label must be a table"))
    for (key, value) in expected
        isequal(get(actual, key, nothing), value) || throw(ArgumentError("$label mismatch: $key"))
    end
end
function pu_hashes(actual, expected, label)
    pu_match(actual, expected, label)
    pu_check(Set(keys(actual)) == Set(keys(expected)), "$label has unexpected keys")
end

"""
    load_mp_recovery(bundle, snapshot, audit; synthetic=false)

Load a schema-v1 split bundle only after checking its manifests, captured file
hashes and exact expected memberships reconstructed from the verified original
snapshot/audit. The same checks apply to every split before any ranking begins.
No manifest-supplied path is executed or used outside fixed allowlisted filenames.
Returns separate composition-only inputs and evaluator-owned labels plus captured
provenance bytes. Preserved producer code is verified, never executed.
"""
function load_mp_recovery(bundle::AbstractString, snapshot::AbstractString, audit::AbstractString;
        synthetic::Bool=false)
    files = Dict{String,Vector{UInt8}}()
    capture(name) = get!(files, name) do
        read(joinpath(bundle, split(name, '/')...))
    end
    root = recovery_toml(capture("manifest.toml"), "split bundle")
    pu_check(get(root, "is_synthetic", nothing) === synthetic, "bundle synthetic mode mismatch")
    seeds = recovery_integers(get(root, "split_seeds", []), "bundle seeds"; maximum=typemax(Int)-10000)
    budgets = recovery_integers(get(root, "budgets", []), "bundle budgets"; minimum=1)
    if !synthetic
        pu_check(seeds == collect(0:19) && budgets == [20, 50, 100, 200], "real bundle differs from frozen seeds/budgets")
    end
    protocol = capture("provenance/protocol.md")
    pu_check(bytes2hex(sha256(protocol)) == MP_RECOVERY_PROTOCOL_SHA256, "bundle protocol hash mismatch")
    recovery_protocol(MP_RECOVERY_PROTOCOL)
    source = recovery_verified_inputs(snapshot, audit; synthetic)
    expected = mp_recovery_splits(source.groups; seeds, budgets)
    inputs = Dict(name => bytes2hex(sha256(bytes)) for (name, bytes) in source.files)
    pu_hashes(get(root, "input_hashes", nothing), inputs, "bundle original input hashes")
    for (name, bytes) in source.files
        name in ("snapshot/records.tsv", "snapshot/records.jsonl") && continue
        pu_check(capture("provenance/$name") == bytes, "bundle provenance differs from original $name")
    end
    pu_check(capture("provenance/unresolved.tsv") == codeunits(recovery_formulas(expected.unresolved)),
        "bundle unresolved membership mismatch")
    producer = get(root, "implementation_hashes", nothing)
    pu_check(producer isa AbstractDict && Set(keys(producer)) == Set(PU_PRODUCER_FILES), "invalid producer file list")
    for name in PU_PRODUCER_FILES
        pu_check(bytes2hex(sha256(capture("provenance/implementation/$name"))) == producer[name],
            "preserved producer hash mismatch: $name")
    end
    # Wrapper/CLI source may evolve after split generation. Compatibility is
    # established by schema, algorithm and complete membership reconstruction,
    # rather than requiring all historical source files to equal today's files.
    pu_match(root, Dict(
        "schema_version" => 1, "protocol_id" => synthetic ? "eka-mp-recovery-synthetic-v1" : MP_RECOVERY_PROTOCOL,
        "protocol_sha256" => MP_RECOVERY_PROTOCOL_SHA256, "scope" => MP_RECOVERY_SCOPE,
        "split_algorithm" => MP_RECOVERY_ALGORITHM, "split_seeds" => seeds,
        "ranking_seeds" => seeds .+ 10000, "tie_seed" => 20260901, "budgets" => budgets,
        "holdout_divisor" => 5, "split_count" => length(seeds),
        "positive_count" => expected.positive_count, "unlabelled_count" => expected.unlabelled_count,
        "unresolved_count" => length(expected.unresolved), "excluded_record_count" => source.summary["excluded_records"],
        "database_version" => source.metadata["database_version"],
        "redistribution_status" => source.metadata["redistribution_status"],
        "membership_format" => "UTF-8; LF; header and trailing LF; canonical formula order"), "split bundle")
    for key in ("julia_version", "package_version")
        pu_check(get(root, key, nothing) isa String && !isempty(root[key]), "bundle must record $key")
    end
    split_hashes = get(root, "split_manifest_hashes", nothing)
    names = ["split-$(lpad(seed, 2, '0'))/manifest.toml" for seed in seeds]
    pu_check(split_hashes isa AbstractDict && Set(keys(split_hashes)) == Set(names), "incomplete or unexpected split manifest list")
    for (split, name) in zip(expected.splits, names)
        bytes = capture(name)
        pu_check(bytes2hex(sha256(bytes)) == split_hashes[name], "split manifest hash mismatch: $name")
        config = recovery_toml(bytes, "split manifest")
        pu_match(config, Dict(
            "schema_version" => 1, "protocol_id" => root["protocol_id"],
            "protocol_sha256" => MP_RECOVERY_PROTOCOL_SHA256, "scope" => MP_RECOVERY_SCOPE,
            "is_synthetic" => synthetic, "split_algorithm" => MP_RECOVERY_ALGORITHM,
            "split_seed" => split.seed, "ranking_seed" => split.seed + 10000, "tie_seed" => 20260901,
            "budgets" => budgets, "training_count" => length(split.inputs.training),
            "heldout_count" => length(split.evaluation.heldout), "candidate_count" => length(split.inputs.candidates),
            "unlabelled_count" => expected.unlabelled_count, "unresolved_count" => length(expected.unresolved)), name)
        pu_hashes(get(config, "input_hashes", nothing), inputs, "$name input hashes")
        pu_hashes(get(config, "implementation_hashes", nothing), producer, "$name producer hashes")
        membership = get(config, "membership_hashes", nothing)
        pu_check(membership isa AbstractDict && Set(keys(membership)) == Set(PU_MEMBER_FILES), "invalid membership file list")
        payloads = (recovery_formulas(split.inputs.training), recovery_formulas(split.inputs.candidates),
            recovery_formulas(split.evaluation.heldout), "composition\tlabel\n" * join(
                "$(formula(c))\t$label\n" for (c, label) in zip(split.inputs.candidates, split.evaluation.labels)))
        folder = first(splitpath(name))
        for (member, expected_text) in zip(PU_MEMBER_FILES, payloads)
            data = capture("$folder/$member")
            pu_check(bytes2hex(sha256(data)) == membership[member], "membership hash mismatch: $folder/$member")
            pu_check(data == codeunits(expected_text), "membership differs from verified source/split: $folder/$member")
        end
    end
    return (result=expected, manifest=root, files=files)
end

function pu_compositions(rows, label)
    rows isa AbstractString && throw(ArgumentError("$label must be a collection"))
    result = Composition[]
    seen = Set{Composition}()
    for row in rows
        row isa Union{Composition,AbstractString} || throw(ArgumentError("$label must contain formulas only"))
        c = row isa Composition ? row : Composition(row)
        c in seen && throw(ArgumentError("duplicate canonical $label composition: $(formula(c))"))
        push!(seen, c); push!(result, c)
    end
    isempty(result) && throw(ArgumentError("$label must not be empty"))
    return result
end

# Integer-coded element counts in the composition's own canonical term order.
# The cosine arithmetic below is written to match `similarity`/`ranking_value`
# term for term, so the streaming maximum is exactly the pairwise value Eka
# already computes; only repeated symbol comparison and norm work is hoisted.
struct PUVector
    terms::Vector{Tuple{Int,Float64}}
    norm::Float64
end

function pu_vector(c::Composition)
    terms = [(findfirst(==(symbol), ELEMENT_SYMBOLS)::Int, Float64(count)) for (symbol, count) in c.terms]
    return PUVector(terms, composition_norm(c))
end

function pu_cosine(candidate::PUVector, reference::PUVector)
    product = 0.0
    for (code, count) in candidate.terms, (other, amount) in reference.terms
        code == other && (product += count * amount)
    end
    return clamp(product / (candidate.norm * reference.norm), 0.0, 1.0)
end

"""
    pu_max_similarity(candidates, training)

Maximum composition-vector cosine similarity between each candidate and any
training composition, streamed one candidate at a time. Peak working memory is
proportional to the number of compositions, never to the candidate-by-training
product; no pairwise matrix is materialised. Held-out labels play no part: only
the training vectors are consulted, and each call refits them from its argument.
"""
function pu_max_similarity(candidates, training)
    references = map(pu_vector, training)
    scores = Vector{Float64}(undef, length(candidates))
    for (i, c) in enumerate(candidates)
        candidate = pu_vector(c)
        best = 0.0
        for reference in references
            value = pu_cosine(candidate, reference)
            value > best && (best = value)
        end
        scores[i] = best
    end
    return scores
end

"""
    pu_rank(training, candidates; method, ranking_seed=10000, tie_seed=20260901)

Composition-only random, training-element-popularity, or maximum-training-
similarity ranking. There is no argument for labels, source IDs, stored scores,
or bundle paths. All counts and similarity references are refitted per call from
unique training compositions. Returned scores are Float64 for popularity and
similarity; random uses its exact SHA-256 key and has no numeric score.
"""
function pu_rank(training, candidates; method::AbstractString, ranking_seed=10000, tie_seed=20260901)
    method in PU_METHODS || throw(ArgumentError("PU methods are random, popularity and similarity"))
    ranking_seed = only(recovery_integers([ranking_seed], "ranking seed"))
    tie_seed = only(recovery_integers([tie_seed], "tie seed"))
    training = pu_compositions(training, "training")
    candidates = sort!(pu_compositions(candidates, "candidate"); by=formula)
    pu_check(isempty(intersect(Set(training), Set(candidates))), "PU training/candidate overlap")
    pu_check(all(c -> length(c) == 3 && "O" in species(c), vcat(training, candidates)), "PU ranker requires oxygen-containing ternaries")
    frequency = Dict{String,Int}()
    if method == "popularity"
        for c in training, e in species(c)
            frequency[e] = get(frequency, e, 0) + 1
        end
    end
    # Fitted anew here from this call's training compositions alone; no cache
    # from an earlier split or from the complete positive set is consulted.
    similarities = method == "similarity" ? pu_max_similarity(candidates, training) : Float64[]
    rows = map(eachindex(candidates)) do i
        c = candidates[i]
        tie = bytes2hex(sha256("eka-pu-tie-v1\n$tie_seed\n$(formula(c))"))
        if method == "random"
            return (composition=c, score=nothing,
                random_key=bytes2hex(sha256("eka-pu-random-v1\n$ranking_seed\n$(formula(c))")), tie_key=tie)
        end
        score = method == "similarity" ? similarities[i] :
            sum(get(frequency, e, 0) for e in species(c)) / (length(c) * length(training))
        pu_check(isfinite(score), "non-finite PU $method score")
        return (composition=c, score=score, random_key="", tie_key=tie)
    end
    sort!(rows; by=r -> method == "random" ? (r.random_key, r.tie_key, formula(r.composition)) :
        (-r.score, r.tie_key, formula(r.composition)))
    return rows
end

"""
    pu_metrics(ranking, heldout; budgets)

Metrics for a complete ordering of unique composition formulas and its observed
held-out positive subset. Unlabelled entries are not confirmed failures. Returns
hits, observed-label fraction, held-out recall, enrichment, and uniform-random
expected hits as both Float64 and an exact numerator/denominator pair.
"""
function pu_metrics(ranking, heldout; budgets)
    ranking = pu_compositions(ranking, "ranking")
    heldout = pu_compositions(heldout, "heldout")
    pu_check(issubset(Set(heldout), Set(ranking)), "heldout composition absent from ranking")
    budgets = recovery_integers(budgets, "budgets"; minimum=1)
    n, h = length(ranking), length(heldout)
    pu_check(maximum(budgets) <= n, "PU budget exceeds candidate pool")
    observed = Set(heldout)
    cumulative = cumsum([c in observed for c in ranking])
    return map(budgets) do k
        hits = cumulative[k]
        expected = (big(k) * h) // n
        return (budget=k, hits=hits, candidate_count=n, heldout_count=h,
            observed_label_fraction=hits/k, heldout_recall=hits/h,
            observed_label_enrichment=(hits/k)/(h/n), random_expected_hits=Float64(expected),
            random_expected_hits_numerator=numerator(expected), random_expected_hits_denominator=denominator(expected))
    end
end

function pu_write_rows(path, header, rows)
    open(path, "w") do io
        println(io, join(header, '\t'))
        for row in rows
            println(io, join(values(row), '\t'))
        end
    end
end

"""
    benchmark_pu(bundle, snapshot, audit, output; synthetic=false)

Verify all saved splits before running the random, popularity and maximum
training-similarity methods on each split and every declared budget. Rankers
receive only formula vectors and declared seeds. Evaluator-owned holdouts are
consulted only after ranking. Save complete rankings, raw metrics,
input/implementation provenance and runtime in a NEW output directory. External
scores are not a method here; see docs/mp-external-score-provenance.md.
"""
function benchmark_pu(bundle::AbstractString, snapshot::AbstractString, audit::AbstractString,
        output::AbstractString; synthetic::Bool=false)
    target = abspath(output)
    pu_check(!(ispath(target) || islink(target)), "refusing to overwrite PU report: $target")
    pu_check(isdir(dirname(target)), "PU output parent must exist")
    loaded = load_mp_recovery(bundle, snapshot, audit; synthetic)
    # File/provenance validation completes for ALL splits before any method runs.
    code_names = (PU_PRODUCER_FILES..., "src/mp_pu.jl")
    code = Dict(name => read(joinpath(@__DIR__, "..", name)) for name in code_names)
    dependency_file = joinpath(@__DIR__, "..", "Manifest.toml")
    isfile(dependency_file) && (code["Manifest.toml"] = read(dependency_file))
    config = Dict{String,Any}(
        "schema_version" => 1, "evaluation_algorithm" => "eka-pu-evaluation-v1",
        "stage" => "all declared primary methods implemented; paired analysis is a separate step",
        "is_synthetic" => synthetic, "protocol_id" => loaded.manifest["protocol_id"],
        "protocol_sha256" => MP_RECOVERY_PROTOCOL_SHA256, "methods" => collect(PU_METHODS),
        "budgets" => loaded.result.budgets, "split_seeds" => loaded.result.seeds,
        "ranking_seeds" => loaded.manifest["ranking_seeds"], "tie_seed" => loaded.manifest["tie_seed"],
        "split_bundle_manifest_sha256" => bytes2hex(sha256(loaded.files["manifest.toml"])),
        "input_hashes" => loaded.manifest["input_hashes"],
        "implementation_hashes" => Dict(name => bytes2hex(sha256(bytes)) for (name, bytes) in code),
        "julia_version" => string(VERSION), "package_version" => string(Base.pkgversion(@__MODULE__)),
        "producer_compatibility" => "schema-v1 plus complete reconstruction from verified originals; preserved code never executed",
        "deterministic_file_hashes" => Dict{String,String}())
    metrics, runtimes = NamedTuple[], NamedTuple[]
    mkdir(target)
    try
        for (name, bytes) in loaded.files
            path = joinpath(target, "inputs", split(name, '/')...)
            mkpath(dirname(path)); write(path, bytes)
        end
        for (name, bytes) in code
            path = joinpath(target, "implementation", name)
            mkpath(dirname(path)); write(path, bytes)
        end
        for split in loaded.result.splits
            folder = "split-$(lpad(split.seed, 2, '0'))"
            mkdir(joinpath(target, folder))
            for method in PU_METHODS
                start = time_ns()
                ranked = pu_rank(split.inputs.training, split.inputs.candidates; method,
                    ranking_seed=split.seed+10000, tie_seed=loaded.manifest["tie_seed"])
                seconds = (time_ns() - start) / 1.0e9
                push!(runtimes, (split_seed=split.seed, method=method, ranking_seconds=seconds))
                # Evaluation data first enters here, after score/order computation.
                heldout = Set(split.evaluation.heldout)
                rows = [(rank=i, composition=formula(r.composition),
                    score=r.score === nothing ? "" : string(r.score), random_key=r.random_key,
                    tie_key=r.tie_key, observed_label=r.composition in heldout ? "positive" : "unlabelled")
                    for (i, r) in enumerate(ranked)]
                file = "$folder/$method.tsv"
                pu_write_rows(joinpath(target, file), keys(first(rows)), rows)
                config["deterministic_file_hashes"][file] = bytes2hex(sha256(read(joinpath(target, file))))
                for m in pu_metrics([r.composition for r in ranked], split.evaluation.heldout; budgets=loaded.result.budgets)
                    push!(metrics, (;method, split_seed=split.seed, ranking_seed=split.seed+10000,
                        tie_seed=loaded.manifest["tie_seed"], m...))
                end
            end
        end
        pu_write_rows(joinpath(target, "metrics.tsv"), keys(first(metrics)), metrics)
        pu_write_rows(joinpath(target, "runtime.tsv"), keys(first(runtimes)), runtimes)
        open(joinpath(target, "report.md"), "w") do io
            println(io, "# PU recovery evaluation\n")
            println(io, synthetic ? "**Synthetic software fixture; not scientific evidence.**\n" :
                "**Local MP recovery run; data redistribution not cleared.**\n")
            println(io, "Methods: random reference, training-element popularity, and maximum training-composition similarity.")
            println(io, "The predefined primary comparison pairs similarity against popularity on identical splits; this file reports the raw per-split rows for it.\n")
            println(io, "Rankers received only training/candidate compositions and declared seeds; labels were attached after ranking.")
            println(io, "Observed-label fraction is not synthesis success rate. Unlabelled candidates are not confirmed failures.")
            println(io, "Repeated overlapping holdouts describe split sensitivity, not independent experiments or confidence intervals.")
            println(io, "Random expected hits assume uniform sampling without replacement; realized hash rankings need not equal that expectation.\n")
            println(io, "| Split | Method | k | Candidates | Holdouts | Hits | Observed-label fraction | Recall | Enrichment | Random expected hits |")
            println(io, "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
            for m in metrics
                println(io, "| $(m.split_seed) | $(m.method) | $(m.budget) | $(m.candidate_count) | $(m.heldout_count) | $(m.hits) | $(m.observed_label_fraction) | $(m.heldout_recall) | $(m.observed_label_enrichment) | $(m.random_expected_hits_numerator)/$(m.random_expected_hits_denominator) |")
            end
            println(io, "\nFull rankings, raw metrics, captured inputs and implementation bytes are preserved here.")
            println(io, "Config hashes deterministic outputs; runtime.tsv contains per-method ranking time (including first-call compilation) and is excluded from exact rerun comparisons.")
        end
        for name in ("metrics.tsv", "report.md")
            config["deterministic_file_hashes"][name] = bytes2hex(sha256(read(joinpath(target, name))))
        end
        recovery_write_toml(joinpath(target, "config.toml"), config)
    catch
        rm(target; recursive=true)
        rethrow()
    end
    return (path=target, metrics=metrics, config=config)
end

function benchmark_pu_main(args; out::IO)
    settings = ArgParseSettings(prog="eka benchmark-pu", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Verify split bundles and evaluate the declared PU random, popularity and similarity methods.")
    @add_arg_table! settings begin
        "--help", "-h"
            action = :store_true
        "--splits"
            arg_type = String
            required = true
            help = "Verified Day 2 split bundle"
        "--snapshot"
            arg_type = String
            required = true
        "--audit"
            arg_type = String
            required = true
        "--output"
            arg_type = String
            required = true
            help = "New local output directory"
        "--synthetic"
            action = :store_true
            help = "Require synthetic snapshot and split bundle"
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    args = parse_args(args, settings)
    report = benchmark_pu(args["splits"], args["snapshot"], args["audit"], args["output"]; synthetic=args["synthetic"])
    println(out, "PU recovery evaluation: ", length(report.metrics), " metric rows; report: ", report.path)
    return 0
end
