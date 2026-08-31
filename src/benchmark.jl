const BENCHMARK_METHODS = ("score", "random", "popularity")

chemical_system(c::Composition) = join(species(c), "-")

function benchmark_integers(values, name; minimum=0)
    values isa Union{Integer,AbstractString} && throw(ArgumentError("$name must be a collection"))
    result = Int[]
    for value in values
        value isa Integer && !(value isa Bool) && minimum <= value <= typemax(Int) ||
            throw(ArgumentError("$name must contain integers >= $minimum within the Int range"))
        push!(result, Int(value))
    end
    isempty(result) && throw(ArgumentError("$name must not be empty"))
    return sort!(unique!(result))
end

"""
    benchmark_rankings(records, training; budgets=[25, 50, 100], seeds=[0, 1, 2],
                       methods=["score", "random", "popularity"])

Evaluate explicit `(composition, stored_score, outcome)` records at fixed budgets.
Outcomes must be integer 0 or 1: absent/unlabelled compounds are NOT negatives.
Training is a separate collection of known-positive compositions. Both collections
must be unique after canonicalization and disjoint. All methods share one pool.
No model is trained; supplied scores must be generated without evaluation leakage.
"""
function benchmark_rankings(records, training; budgets=[25, 50, 100], seeds=[0, 1, 2],
        methods=collect(BENCHMARK_METHODS))
    budgets = benchmark_integers(budgets, "budgets"; minimum=1)
    seeds = benchmark_integers(seeds, "seeds")
    methods isa AbstractString && throw(ArgumentError("methods must be a collection"))
    methods = collect(methods)
    !isempty(methods) && all(m -> m in BENCHMARK_METHODS, methods) ||
        throw(ArgumentError("methods must contain score, random, or popularity"))
    length(unique(methods)) == length(methods) || throw(ArgumentError("duplicate methods"))
    training_rows = Composition[]
    seen = Set{Composition}()
    for raw in training
        c = raw isa Composition ? raw : Composition(raw)
        c in seen && throw(ArgumentError("duplicate training composition: $(formula(c))"))
        push!(seen, c)
        push!(training_rows, c)
    end
    isempty(training_rows) && throw(ArgumentError("training must not be empty"))
    sort!(training_rows; by=formula)
    candidates = NamedTuple{(:composition, :score, :outcome),Tuple{Composition,Float64,Int}}[]
    candidate_seen = Set{Composition}()
    for (index, record) in enumerate(records)
        record isa Union{Tuple,NamedTuple} && length(record) == 3 ||
            throw(ArgumentError("candidate row $index must contain (composition, score, outcome)"))
        c, score, _ = checked_import_record((record[1], record[2]), index)
        outcome = record[3]
        outcome isa Integer && !(outcome isa Bool) && outcome in (0, 1) ||
            throw(ArgumentError("candidate row $index: outcome must be integer 0 or 1; unknown is not negative"))
        c in seen && throw(ArgumentError("training/candidate overlap: $(formula(c))"))
        c in candidate_seen && throw(ArgumentError("duplicate candidate composition: $(formula(c))"))
        push!(candidate_seen, c)
        push!(candidates, (composition=c, score=score, outcome=Int(outcome)))
    end
    isempty(candidates) && throw(ArgumentError("candidate pool must not be empty"))
    maximum(budgets) <= length(candidates) || throw(ArgumentError("budget exceeds candidate pool size"))
    sort!(candidates; by=r -> formula(r.composition))

    frequency = Dict{String,Int}()
    for c in training_rows, element in species(c)
        frequency[element] = get(frequency, element, 0) + 1
    end
    training_systems = Set(chemical_system(c) for c in training_rows)
    pool_elements = Set(e for r in candidates for e in species(r.composition))
    positives = sum(r.outcome for r in candidates)
    prevalence = positives / length(candidates)
    rankings, metrics = NamedTuple[], NamedTuple[]
    for method in methods
        # Replicating deterministic methods across seeds would imply false replication.
        for seed in (method == "random" ? seeds : [nothing])
            values = if method == "score"
                [r.score for r in candidates]
            elseif method == "popularity"
                [sum(get(frequency, e, 0) for e in species(r.composition)) /
                    (length(r.composition) * length(training_rows)) for r in candidates]
            else
                # Versioned hash ordering avoids global RNG state and input-order dependence.
                [bytes2hex(sha256("eka-random-v1\n$seed\n$(formula(r.composition))")) for r in candidates]
            end
            order = method == "random" ?
                sortperm(eachindex(candidates); by=i -> (values[i], formula(candidates[i].composition))) :
                sortperm(eachindex(candidates); by=i -> (-values[i], formula(candidates[i].composition)))
            # Baseline ties intentionally do not use the supplied model score.
            for (rank, i) in enumerate(order)
                r = candidates[i]
                push!(rankings, (method=method, seed=seed, rank=rank,
                    composition=formula(r.composition), stored_score=r.score,
                    ranking_value=values[i], outcome=r.outcome))
            end
            for budget in budgets
                top = candidates[order[1:budget]]
                hits = sum(r.outcome for r in top)
                systems = [chemical_system(r.composition) for r in top]
                elements = Set(e for r in top for e in species(r.composition))
                push!(metrics, (method=method, seed=seed, budget=budget, hits=hits,
                    precision=hits / budget,
                    recall=positives == 0 ? nothing : hits / positives,
                    enrichment=positives == 0 ? nothing : (hits / budget) / prevalence,
                    novel_system_fraction=count(s -> !(s in training_systems), systems) / budget,
                    unique_system_fraction=length(Set(systems)) / budget,
                    element_coverage=length(elements) / length(pool_elements)))
            end
        end
    end
    return (candidates=candidates, training=training_rows, rankings=rankings, metrics=metrics,
        budgets=budgets, seeds=seeds, methods=methods, positives=positives)
end

function benchmark_table(bytes, header, label)
    lines = split(String(copy(bytes)), '\n'; keepempty=true)
    !isempty(lines) && isempty(last(lines)) && pop!(lines)
    lines = [endswith(line, "\r") ? chop(line; tail=1) : String(line) for line in lines]
    !isempty(lines) && first(lines) == header || throw(ArgumentError("$label requires header $header"))
    width = length(split(header, '\t'))
    rows = [split(line, '\t'; keepempty=true) for line in lines[2:end]]
    for (i, row) in enumerate(rows)
        length(row) == width && all(!isempty, row) || throw(ArgumentError("$label line $(i + 1): malformed TSV row"))
    end
    return rows
end

# The report schema uses only fixed ASCII keys/methods, numbers, and null.
# User-supplied provenance strings are serialized by TOML, never this JSON writer.
benchmark_json(x::Nothing) = "null"
benchmark_json(x::Real) = string(x)
benchmark_json(x::AbstractString) = "\"" * x * "\""
benchmark_json(x::NamedTuple) = "{" * join(("\"$k\":" * benchmark_json(v) for (k, v) in pairs(x)), ",") * "}"

"""
    benchmark_tsv(input, training, output; source, kwargs...)

Read strict labelled-candidate and training TSV files and create a new report
directory. Preserve exact input snapshots and SHA-256 checksums. Existing output
paths are never overwritten. `source` describes the data, labels, split, and scores.
"""
function benchmark_tsv(input::AbstractString, training::AbstractString, output::AbstractString;
        source::AbstractString, kwargs...)
    isempty(strip(source)) && throw(ArgumentError("source description must not be empty"))
    target = abspath(output)
    (ispath(target) || islink(target)) && throw(ArgumentError("refusing to overwrite existing report: $target"))
    isdir(dirname(target)) || throw(ArgumentError("report parent directory does not exist"))
    input_bytes, training_bytes = read(input), read(training)
    rows = benchmark_table(input_bytes, "composition\tscore\toutcome", "candidates")
    training_rows = benchmark_table(training_bytes, "composition", "training")
    records = map(enumerate(rows)) do (i, row)
        score = tryparse(Float64, row[2])
        score === nothing && throw(ArgumentError("candidates line $(i + 1): invalid score"))
        row[3] in ("0", "1") || throw(ArgumentError("candidates line $(i + 1): outcome must be 0 or 1"))
        return (row[1], score, parse(Int, row[3]))
    end
    result = benchmark_rankings(records, [only(row) for row in training_rows]; kwargs...)
    # Reserve exclusively after validation; cleanup only the directory created here.
    mkdir(target)
    try
        write(joinpath(target, "input.tsv"), input_bytes)
        write(joinpath(target, "training.tsv"), training_bytes)
        config = Dict("schema_version" => 1, "source" => String(source),
            "input" => "input.tsv", "training" => "training.tsv",
            "input_sha256" => bytes2hex(sha256(input_bytes)),
            "training_sha256" => bytes2hex(sha256(training_bytes)),
            "budgets" => result.budgets, "seeds" => result.seeds, "methods" => result.methods,
            "random_algorithm" => "sha256-order-v1", "package_version" => string(Base.pkgversion(@__MODULE__)),
            "benchmark_code_sha256" => bytes2hex(sha256(read(@__FILE__))),
            "julia_version" => string(VERSION), "candidate_count" => length(result.candidates),
            "training_count" => length(result.training), "positive_count" => result.positives)
        open(joinpath(target, "config.toml"), "w") do io
            TOML.print(io, config; sorted=true)
        end
        open(joinpath(target, "candidates.csv"), "w") do io
            println(io, "method,seed,rank,composition,stored_score,ranking_value,outcome")
            for r in result.rankings
                println(io, join((r.method, something(r.seed, ""), r.rank, r.composition,
                    r.stored_score, r.ranking_value, r.outcome), ','))
            end
        end
        write(joinpath(target, "metrics.json"), "{\"schema_version\":1,\"metrics\":[\n" *
            join(benchmark_json.(result.metrics), ",\n") * "\n]}\n")
        open(joinpath(target, "benchmark.md"), "w") do io
            println(io, "# Fixed-budget ranking benchmark\n")
            println(io, "Retrospective evaluation of supplied labels; not evidence of stability or synthesizability.\n")
            println(io, "Pool: $(length(result.candidates)) candidates, $(result.positives) positives. Training: $(length(result.training)) compositions.\n")
            println(io, "| Method | Seed | Budget | Hits | Precision | Novel systems | Unique systems | Element coverage |")
            println(io, "| --- | --- | --- | --- | --- | --- | --- | --- |")
            for m in result.metrics
                @printf(io, "| %s | %s | %d | %d | %.4f | %.4f | %.4f | %.4f |\n", m.method,
                    string(something(m.seed, "—")), m.budget, m.hits, m.precision,
                    m.novel_system_fraction, m.unique_system_fraction, m.element_coverage)
            end
            println(io, "\nHits count outcome=1; precision divides by budget. Recall divides by all pool positives;")
            println(io, "enrichment divides precision by pool prevalence. Both are null when no positives exist.")
            println(io, "Novel systems are element sets absent from training; unique systems divide distinct selected element sets by budget.")
            println(io, "Element coverage divides selected distinct elements by pool distinct elements. These are proxies, not chemical distances.\n")
            println(io, "Score ranks supplied scores; popularity averages training element occurrence fractions.")
            println(io, "Random uses seeded SHA-256 ordering. Ties use canonical formulas, never model scores for baselines.")
            println(io, "Random seeds are separate runs, not independent datasets or confidence intervals.\n")
            println(io, "Input snapshots, provenance, and hashes are in this directory. See config.toml for budgets and seeds.")
            println(io, "Scores must have been produced without evaluation data. The software detects composition overlap,")
            println(io, "but cannot audit upstream model training. Unknown/unobserved compounds must not be labelled negative.")
        end
    catch
        rm(target; recursive=true)
        rethrow()
    end
    return (path=target, result=result)
end

function benchmark_main(args; out::IO)
    settings = ArgParseSettings(prog="eka benchmark", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Compare rankings on explicit labelled candidates at fixed budgets.")
    @add_arg_table! settings begin
        "--help", "-h"
            action = :store_true
            help = "Show benchmark help"
        "--input"
            arg_type = String
            required = true
            help = "Candidate TSV: composition, score, outcome (0 or 1)"
        "--training"
            arg_type = String
            required = true
            help = "Known-positive training TSV: composition"
        "--output"
            arg_type = String
            required = true
            help = "New report directory; parent must exist"
        "--source"
            arg_type = String
            required = true
            help = "Describe dataset/version, outcome meaning, split, and score provenance"
        "--methods"
            arg_type = String
            default = "score,random,popularity"
            help = "Comma-separated methods: score,random,popularity"
        "--budget"
            arg_type = Int
            nargs = '+'
            default = [25, 50, 100]
            help = "Positive candidate budgets, each <= pool size"
        "--seeds"
            arg_type = Int
            nargs = '+'
            default = [0, 1, 2]
            help = "Nonnegative random baseline seeds"
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    parsed = parse_args(args, settings)
    report = benchmark_tsv(parsed["input"], parsed["training"], parsed["output"];
        source=parsed["source"], methods=String.(split(parsed["methods"], ',')),
        budgets=parsed["budget"], seeds=parsed["seeds"])
    println(out, "Benchmarked ", length(report.result.candidates), " candidates; report: ", report.path)
    return 0
end
