"""Follow-on label sensitivity; loaded explicitly by the research script, not v1's CLI."""
module MPLabelSensitivity

using EkaCompositions, SHA, TOML

const PROTOCOL = "eka-mp-label-sensitivity-v1"
const POLICIES = ("original", "exclude_mixed", "unlabel_mixed")
const MODES = ("evaluation_only", "full_pipeline")
const METHODS = ("random", "popularity", "similarity")
check(ok, message) = ok || throw(ArgumentError(message))
digest(bytes) = bytes2hex(sha256(bytes))

function policy_groups(groups, policy)
    check(policy in POLICIES, "unknown label policy")
    output = Tuple{String,String}[]
    seen = Set{String}()
    for row in groups
        f = formula(Composition(row.composition))
        check(!(f in seen), "duplicate composition group")
        push!(seen, f)
        check(row.label in ("positive", "unlabelled", "unresolved"), "invalid source label")
        check(row.mixed isa Bool && (!row.mixed || row.label == "positive"), "mixed group must be an original positive")
        row.mixed && policy == "exclude_mixed" && continue
        push!(output, (f, row.mixed && policy == "unlabel_mixed" ? "unlabelled" : row.label))
    end
    return sort!(output; by=first)
end

function evaluation_membership(original, mixed, policy)
    check(policy in POLICIES, "unknown label policy")
    candidates = policy == "exclude_mixed" ? filter(c -> !(c in mixed), original.inputs.candidates) : copy(original.inputs.candidates)
    heldout = policy == "original" ? copy(original.evaluation.heldout) : filter(c -> !(c in mixed), original.evaluation.heldout)
    positives = Set(heldout)
    return (seed=original.seed, inputs=(training=copy(original.inputs.training), candidates=candidates),
        evaluation=(heldout=heldout, labels=[c in positives ? "positive" : "unlabelled" for c in candidates]))
end

# This helper receives permitted candidate membership, never evaluation labels.
function filter_ranking(ranked, candidates)
    eligible = Set(candidates)
    selected = [(row=row, original_rank=i) for (i, row) in enumerate(ranked) if row.composition in eligible]
    check(length(selected) == length(eligible) && Set(x.row.composition for x in selected) == eligible,
        "fixed ranking does not cover eligible candidates")
    return selected
end

function validate_membership(split, budgets)
    t, c, h = split.inputs.training, split.inputs.candidates, split.evaluation.heldout
    check(allunique(t) && allunique(c) && allunique(h), "duplicate membership")
    check(!isempty(t) && !isempty(h) && length(c) > length(h), "infeasible training/positive/unlabelled population")
    check(isempty(intersect(t, c)) && issubset(Set(h), Set(c)), "invalid membership overlap")
    check(maximum(budgets) <= length(c), "budget exceeds eligible candidate pool")
end

function read_ranking(bytes)
    lines = split(chomp(String(copy(bytes))), '\n')
    check(first(lines) == "rank\tcomposition\tscore\trandom_key\ttie_key\tobserved_label", "invalid baseline ranking header")
    return map(lines[2:end]) do line
        r = split(line, '\t'; keepempty=true)
        check(length(r) == 6, "invalid baseline ranking row")
        (composition=Composition(r[2]), score=isempty(r[3]) ? nothing : parse(Float64, r[3]), random_key=String(r[4]), tie_key=String(r[5]))
    end
end

function verified_baseline(pilot, snapshot, audit; synthetic)
    loaded = load_mp_recovery(joinpath(pilot, "inputs"), snapshot, audit; synthetic)
    config_bytes = read(joinpath(pilot, "config.toml"))
    config = EkaCompositions.recovery_toml(config_bytes, "original pilot config")
    captures = Dict("config.toml" => config_bytes)
    # Recompute v1 only as a compatibility/integrity check. Evaluation-only
    # subsequently consumes the original captured rankings, not refitted scores.
    mktempdir() do tmp
        rebuilt = benchmark_pu(joinpath(pilot, "inputs"), snapshot, audit, joinpath(tmp, "baseline"); synthetic)
        for field in ("schema_version", "evaluation_algorithm", "protocol_id", "protocol_sha256", "is_synthetic",
                "methods", "budgets", "split_seeds", "ranking_seeds", "tie_seed", "input_hashes",
                "split_bundle_manifest_sha256", "deterministic_file_hashes")
            check(get(config, field, nothing) == rebuilt.config[field], "original pilot mismatch: $field")
        end
        for name in keys(rebuilt.config["deterministic_file_hashes"])
            bytes = read(joinpath(pilot, name))
            check(bytes == read(joinpath(rebuilt.path, name)), "original pilot output differs from recomputation: $name")
            captures[name] = bytes
        end
    end
    rankings = Dict((s, m) => read_ranking(captures["split-$(lpad(s, 2, '0'))/$m.tsv"])
        for s in loaded.result.seeds for m in METHODS)
    return (; loaded, config, captures, rankings)
end

function write_membership(folder, split)
    mkpath(joinpath(folder, "inputs")); mkpath(joinpath(folder, "evaluation"))
    write(joinpath(folder, "inputs/training.tsv"), EkaCompositions.recovery_formulas(split.inputs.training))
    write(joinpath(folder, "inputs/candidates.tsv"), EkaCompositions.recovery_formulas(split.inputs.candidates))
    write(joinpath(folder, "evaluation/heldout.tsv"), EkaCompositions.recovery_formulas(split.evaluation.heldout))
    EkaCompositions.pu_write_rows(joinpath(folder, "evaluation/labels.tsv"), (:composition, :label),
        [(composition=formula(c), label=l) for (c,l) in zip(split.inputs.candidates, split.evaluation.labels)])
end

"""Run all six frozen branches into a new directory; never modify pilot inputs."""
function run_sensitivity(snapshot, audit, pilot, output; synthetic=false)
    target = abspath(output)
    check(!(ispath(target) || islink(target)), "refusing to overwrite sensitivity output")
    check(isdir(dirname(target)), "output parent must exist")
    protocol = EkaCompositions.recovery_protocol(PROTOCOL)
    source = EkaCompositions.recovery_verified_inputs(snapshot, audit; synthetic)
    raw_groups = EkaCompositions.recovery_group_rows(source.files["audit/compositions.tsv"])
    groups = [(composition=r[1], label=r[3], mixed=parse(Int,r[5]) > 0 && parse(Int,r[6]) > 0) for r in values(raw_groups)]
    mixed = Set(Composition(r.composition) for r in groups if r.mixed)
    # Validate every branch before any alternative ranking is computed.
    loaded = load_mp_recovery(joinpath(pilot, "inputs"), snapshot, audit; synthetic)
    seeds, budgets = loaded.result.seeds, loaded.result.budgets
    full = Dict(policy => mp_recovery_splits(policy_groups(groups, policy); seeds, budgets) for policy in POLICIES)
    check(full["original"] == loaded.result, "original control membership mismatch")
    branches = [(; mode, policy, split) for mode in MODES for policy in POLICIES
        for split in (mode == "full_pipeline" ? full[policy].splits :
            [evaluation_membership(s, mixed, policy) for s in loaded.result.splits])]
    foreach(branch -> validate_membership(branch.split, budgets), branches)
    baseline = verified_baseline(pilot, snapshot, audit; synthetic)
    check(baseline.loaded.files == loaded.files, "baseline membership changed during verification")
    metrics, runtimes = NamedTuple[], NamedTuple[]
    code_names = [collect(EkaCompositions.PU_PRODUCER_FILES); "src/mp_pu.jl"; "src/mp_label_sensitivity.jl"; "scripts/run_label_sensitivity.jl"]
    root = normpath(joinpath(@__DIR__, ".."))
    isfile(joinpath(root, "Manifest.toml")) && push!(code_names, "Manifest.toml")
    code = Dict(name => read(joinpath(root, name)) for name in code_names)
    config = Dict{String,Any}("schema_version"=>1, "evaluation_algorithm"=>"eka-mp-label-sensitivity-evaluation-v1",
        "protocol_id"=>PROTOCOL, "protocol_sha256"=>protocol.sha256,
        "is_synthetic"=>synthetic, "modes"=>collect(MODES), "policies"=>collect(POLICIES), "methods"=>collect(METHODS),
        "split_seeds"=>seeds, "ranking_seeds"=>seeds .+ 10000, "tie_seed"=>20260901, "budgets"=>budgets,
        "julia_version"=>string(VERSION), "package_version"=>string(Base.pkgversion(EkaCompositions)),
        "mixed_group_count"=>length(mixed), "original_pilot_config_sha256"=>digest(baseline.captures["config.toml"]),
        "input_hashes"=>Dict(name=>digest(bytes) for (name,bytes) in source.files),
        "implementation_hashes"=>Dict(name=>digest(bytes) for (name,bytes) in code),
        "original_validation"=>"all memberships reconstructed; all v1 rankings, metrics and raw report recomputed byte-identically",
        "redistribution_status"=>"local only; sharing not cleared")
    mkdir(target)
    try
        write(joinpath(target, "protocol.md"), protocol.bytes)
        for (prefix, files) in (("source", source.files), ("baseline", baseline.captures), ("implementation", code))
            for (name,bytes) in files
                path=joinpath(target,prefix,name); mkpath(dirname(path)); write(path,bytes)
            end
        end
        for branch in branches
            mode, policy, split = branch.mode, branch.policy, branch.split
            folder=joinpath(target,mode,policy,"split-$(lpad(split.seed,2,'0'))")
            write_membership(folder,split)
            heldout = Set(split.evaluation.heldout)
            for method in METHODS
                start=time_ns()
                fixed = mode == "evaluation_only"
                original = baseline.rankings[split.seed,method]
                selected = fixed ? filter_ranking(original,split.inputs.candidates) :
                    [(row=r,original_rank=0) for r in pu_rank(split.inputs.training,split.inputs.candidates;
                        method,ranking_seed=split.seed+10000,tie_seed=20260901)]
                ranked = [x.row for x in selected]
                policy == "original" && check(ranked == original, "original control ranking mismatch")
                push!(runtimes,(mode=mode,policy=policy,split_seed=split.seed,method=method,ranking_seconds=(time_ns()-start)/1e9))
                ranking_rows=[(rank=i,composition=formula(x.row.composition),score=x.row.score === nothing ? "" : string(x.row.score),
                    random_key=x.row.random_key,tie_key=x.row.tie_key,observed_label=x.row.composition in heldout ? "positive" : "unlabelled",
                    original_rank=fixed ? string(x.original_rank) : "") for (i,x) in enumerate(selected)]
                EkaCompositions.pu_write_rows(joinpath(folder,"$method.tsv"),keys(first(ranking_rows)),ranking_rows)
                values=pu_metrics([r.composition for r in ranked],split.evaluation.heldout;budgets)
                if policy == "original"
                    original_split=only(s for s in loaded.result.splits if s.seed==split.seed)
                    check(values==pu_metrics([r.composition for r in original],original_split.evaluation.heldout;budgets),"original control metric mismatch")
                end
                for m in values
                    push!(metrics,(mode=mode,policy=policy,split_seed=split.seed,method=method,
                        training_count=length(split.inputs.training),mixed_training_count=count(c->c in mixed,split.inputs.training),
                        mixed_candidate_count=count(c->c in mixed,split.inputs.candidates),
                        policy_positive_count=full[policy].positive_count,policy_unlabelled_count=full[policy].unlabelled_count,
                        excluded_group_count=length(full[policy].unresolved)+(policy=="exclude_mixed" ? length(mixed) : 0),
                        original_rank_depth=fixed ? string(selected[m.budget].original_rank) : "",
                        ranking_seed=split.seed+10000,tie_seed=20260901,m...))
                end
            end
        end
        check(length(metrics)==length(MODES)*length(POLICIES)*length(seeds)*length(METHODS)*length(budgets),"incomplete metric grid")
        EkaCompositions.pu_write_rows(joinpath(target,"metrics.tsv"),keys(first(metrics)),metrics)
        EkaCompositions.pu_write_rows(joinpath(target,"runtime.tsv"),keys(first(runtimes)),runtimes)
        write(joinpath(target,"README.md"),"# Label sensitivity outputs\n\nLocal unreviewed derivatives. Six branches retain every declared method, seed and budget.\nEvaluation-only keeps original training and scores; exclusion compacts eligible ranks and records original depth.\nFull-pipeline rebuilds labels, membership and training-derived scores.\nOriginal controls match v1 exactly. See protocol.md and metrics.tsv; runtime.tsv is nondeterministic.\n")
        hashes=Dict{String,String}()
        for (dir,_,names) in walkdir(target), name in names
            path=joinpath(dir,name); relative=replace(relpath(path,target),'\\'=>'/')
            relative=="runtime.tsv" && continue
            hashes[relative]=digest(read(path))
        end
        config["deterministic_file_hashes"]=hashes
        EkaCompositions.recovery_write_toml(joinpath(target,"config.toml"),config)
    catch
        rm(target;recursive=true)
        rethrow()
    end
    return (;path=target,metrics,config)
end

end
