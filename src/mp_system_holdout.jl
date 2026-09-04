"""Versioned research runner; does not change the v1 CLI or ranking algorithms."""
module MPSystemHoldout

using ...EkaCompositions
using ..MPLabelSensitivity
using SHA, TOML
const LS = MPLabelSensitivity
const PROTOCOL = "eka-mp-system-holdout-v2"
const ALGORITHM = "eka-pu-system-split-v2"
const DESIGNS = ("composition", "system")
const POLICIES = LS.POLICIES
const METHODS = LS.METHODS
check(ok, message) = ok || throw(ArgumentError(message))
digest(bytes) = bytes2hex(sha256(bytes))
system(c::Composition) = join(sort!(collect(species(c))), "-")
system(f::AbstractString) = system(Composition(f))

function universe(groups)
    # Reuse full input validation (scope, duplicate canonical keys and labels).
    pairs = LS.policy_groups(groups, "original")
    EkaCompositions.mp_recovery_splits(pairs; seeds=[0], budgets=[1])
    return sort!(unique(system(f) for (f,l) in pairs if l != "unresolved"))
end

function selections(systems, seed)
    n = fld(length(systems), 5)
    check(n >= 1 && n < length(systems), "need at least five eligible systems")
    return sort!(sort(systems; by=s -> (digest("$ALGORITHM\n$seed\n$s"),s))[1:n])
end

function system_splits(groups, policy; seeds=0:19, budgets=[20,50,100,200])
    seeds = EkaCompositions.recovery_integers(seeds,"seeds";maximum=typemax(Int)-10000)
    budgets = EkaCompositions.recovery_integers(budgets,"budgets";minimum=1)
    systems = universe(groups)
    pairs = LS.policy_groups(groups,policy)
    positives = sort!([Composition(f) for (f,l) in pairs if l=="positive"];by=formula)
    unlabelled = sort!([Composition(f) for (f,l) in pairs if l=="unlabelled"];by=formula)
    splits = map(seeds) do seed
        chosen = Set(selections(systems,seed))
        training = filter(c -> !(system(c) in chosen),positives)
        heldout = filter(c -> system(c) in chosen,positives)
        candidates = sort!(vcat(heldout,filter(c->system(c) in chosen,unlabelled));by=formula)
        h = Set(heldout)
        split = (; seed,inputs=(;training,candidates),evaluation=(;heldout,labels=[c in h ? "positive" : "unlabelled" for c in candidates]))
        LS.validate_membership(split,budgets)
        check(isempty(intersect(Set(system.(training)),Set(system.(candidates)))),"training/candidate system overlap")
        split
    end
    return (;splits,seeds,budgets,systems)
end

function concentration(compositions)
    counts = Dict{String,Int}()
    for c in compositions
        s=system(c); counts[s]=get(counts,s,0)+1
    end
    ordered=sort!(collect(values(counts));rev=true)
    check(!isempty(ordered),"empty positive concentration population")
    return (largest=first(ordered)/length(compositions),top5=sum(ordered[1:min(5,length(ordered))])/length(compositions))
end

function population(groups,design,policy,split,systems)
    t,c,h=split.inputs.training,split.inputs.candidates,split.evaluation.heldout
    st,sc,sh=Set(system.(t)),Set(system.(c)),Set(system.(h))
    mixed=Set(Composition(r.composition) for r in groups if r.mixed)
    chosen=design=="system" ? Set(selections(systems,split.seed)) : Set{String}()
    pairs=LS.policy_groups(groups,policy)
    u=count(r->last(r)=="unlabelled",pairs)
    ct,ch=concentration(t),concentration(h)
    return (design=design,policy=policy,split_seed=split.seed,
        training_count=length(t),candidate_count=length(c),heldout_count=length(h),
        unlabelled_count=length(c)-length(h),prevalence=length(h)/length(c),
        excluded_group_count=length(groups)-count(r->last(r)!="unresolved",pairs),
        unused_unlabelled_count=u-(length(c)-length(h)),universe_system_count=length(systems),
        selected_system_count=length(chosen),selected_empty_system_count=length(setdiff(chosen,sc)),
        training_system_count=length(st),candidate_system_count=length(sc),heldout_system_count=length(sh),
        system_overlap_count=length(intersect(st,sc)),
        mixed_training_count=length(intersect(Set(t),mixed)),mixed_candidate_count=length(intersect(Set(c),mixed)),
        training_largest_system_fraction=ct.largest,training_top5_system_fraction=ct.top5,
        heldout_largest_system_fraction=ch.largest,heldout_top5_system_fraction=ch.top5)
end

function preflight(groups;seeds=0:19,budgets=[20,50,100,200])
    systems=universe(groups)
    branches=NamedTuple[]
    for design in DESIGNS, policy in POLICIES
        result=design=="system" ? system_splits(groups,policy;seeds,budgets) :
            mp_recovery_splits(LS.policy_groups(groups,policy);seeds,budgets)
        for split in result.splits
            LS.validate_membership(split,budgets)
            push!(branches,(;design,policy,split,population=population(groups,design,policy,split,systems)))
        end
    end
    return branches
end

function source_groups(source)
    rows=EkaCompositions.recovery_group_rows(source.files["audit/compositions.tsv"])
    return [(composition=r[1],label=r[3],mixed=parse(Int,r[5])>0 && parse(Int,r[6])>0) for r in values(rows)]
end

function table(bytes)
    lines=split(chomp(String(copy(bytes))),'\n');header=split(first(lines),'\t')
    return [Dict(zip(header,split(line,'\t';keepempty=true))) for line in lines[2:end]]
end

function capture_baseline(path,source;synthetic)
    bytes=read(joinpath(path,"config.toml")); config=EkaCompositions.recovery_toml(bytes,"sensitivity config")
    pin=EkaCompositions.recovery_protocol(LS.PROTOCOL)
    check(config["protocol_id"]==LS.PROTOCOL && config["protocol_sha256"]==pin.sha256,"wrong baseline protocol")
    check(config["is_synthetic"]===synthetic,"baseline synthetic mode mismatch")
    check(config["methods"]==collect(METHODS) && config["policies"]==collect(POLICIES),"wrong baseline branches")
    check(config["input_hashes"]==Dict(n=>digest(b) for (n,b) in source.files),"baseline source mismatch")
    seeds=EkaCompositions.recovery_integers(config["split_seeds"],"baseline seeds")
    budgets=EkaCompositions.recovery_integers(config["budgets"],"baseline budgets";minimum=1)
    check(config["ranking_seeds"]==seeds .+ 10000 && config["tie_seed"]==20260901,"baseline ranking seeds differ")
    check(synthetic || (seeds==collect(0:19) && budgets==[20,50,100,200]),"wrong real design")
    files=Dict("config.toml"=>bytes)
    for (name,hash) in config["deterministic_file_hashes"]
        check(!isabspath(name) && !occursin('\\',name) && !(".." in split(name,'/')),"unsafe baseline path")
        content=read(joinpath(path,name));check(digest(content)==hash,"baseline hash mismatch: $name")
        if startswith(name,"full_pipeline/") || name in ("metrics.tsv","protocol.md")
            files[name]=content
        end
    end
    check(files["protocol.md"]==pin.bytes,"altered baseline protocol")
    return (;files,seeds,budgets)
end

function write_rank(path,ranked,heldout)
    h=Set(heldout)
    rows=[(rank=i,composition=formula(r.composition),score=r.score===nothing ? "" : string(r.score),
        random_key=r.random_key,tie_key=r.tie_key,observed_label=r.composition in h ? "positive" : "unlabelled") for (i,r) in enumerate(ranked)]
    EkaCompositions.pu_write_rows(path,keys(first(rows)),rows)
    return rows
end

function diagnostic(values)
    check(!isempty(values),"empty diagnostic subset")
    n=length(values);ordered=sort(values);q(p)=ordered[max(1,ceil(Int,p*n))]
    total=0.0
    for v in values;total+=v;end
    return (n=n,mean=total/n,min=first(ordered),p10=q(0.1),median=q(0.5),p90=q(0.9),max=last(ordered),
        fraction_ge_09=count(>=(0.9),values)/n,fraction_ge_099=count(>=(0.99),values)/n)
end

function run_system_holdout(snapshot,audit,baseline_path,output;synthetic=false,preflight_only=false)
    target=abspath(output)
    check(!(ispath(target)||islink(target)),"refusing to overwrite system holdout output")
    check(isdir(dirname(target)),"output parent must exist")
    protocol=EkaCompositions.recovery_protocol(PROTOCOL)
    source=EkaCompositions.recovery_verified_inputs(snapshot,audit;synthetic)
    baseline=capture_baseline(baseline_path,source;synthetic)
    groups=source_groups(source)
    branches=preflight(groups;seeds=baseline.seeds,budgets=baseline.budgets)
    if preflight_only
        mkdir(target)
        EkaCompositions.pu_write_rows(joinpath(target,"populations.tsv"),keys(first(branches).population),[b.population for b in branches])
        write(joinpath(target,"protocol.md"),protocol.bytes)
        return (;path=target,metrics=NamedTuple[])
    end
    # All original controls will be reconstructed and matched, not trusted from hashes alone.
    base_metrics=table(baseline.files["metrics.tsv"])
    root=normpath(joinpath(@__DIR__,".."))
    names=sort!(unique([collect(EkaCompositions.PU_PRODUCER_FILES);"src/mp_pu.jl";"src/mp_label_sensitivity.jl";
        "src/mp_system_holdout.jl";"scripts/run_system_holdout.jl";"scripts/analyze_system_holdout.py";"scripts/analyze_pu_pilot.py";
        "docs/mp-recovery-protocol.md";"docs/mp-label-sensitivity-protocol.md";"docs/mp-system-holdout-protocol.md"]))
    isfile(joinpath(root,"Manifest.toml")) && push!(names,"Manifest.toml")
    code=Dict(n=>read(joinpath(root,n)) for n in names)
    config=Dict{String,Any}("schema_version"=>1,"protocol_id"=>PROTOCOL,"protocol_sha256"=>protocol.sha256,
        "is_synthetic"=>synthetic,"designs"=>collect(DESIGNS),"policies"=>collect(POLICIES),"methods"=>collect(METHODS),
        "split_seeds"=>baseline.seeds,"ranking_seeds"=>baseline.seeds .+ 10000,"tie_seed"=>20260901,"budgets"=>baseline.budgets,
        "input_hashes"=>Dict(n=>digest(b) for (n,b) in source.files),"implementation_hashes"=>Dict(n=>digest(b) for (n,b) in code),
        "baseline_config_sha256"=>digest(baseline.files["config.toml"]),"julia_version"=>string(VERSION),
        "redistribution_status"=>"local experiment; separate attributed data-release review")
    metrics,runtimes,diagnostics=NamedTuple[],NamedTuple[],NamedTuple[]
    shared=Dict{Tuple{String,Int,String},Any}()
    mkdir(target)
    try
        write(joinpath(target,"protocol.md"),protocol.bytes)
        for (prefix,files) in (("source",source.files),("baseline",baseline.files),("implementation",code))
            for (n,bytes) in files
                p=joinpath(target,prefix,n);mkpath(dirname(p));write(p,bytes)
            end
        end
        for branch in branches
            design,policy,split=branch.design,branch.policy,branch.split
            sub="$policy/split-$(lpad(split.seed,2,'0'))";folder=joinpath(target,design,sub)
            LS.write_membership(folder,split)
            if design=="system"
                EkaCompositions.pu_write_rows(joinpath(folder,"selected-systems.tsv"),(:chemical_system,),
                    [(chemical_system=s,) for s in selections(universe(groups),split.seed)])
            else
                for n in EkaCompositions.PU_MEMBER_FILES
                    check(read(joinpath(folder,n))==baseline.files["full_pipeline/$sub/$n"],"control membership mismatch")
                end
            end
            for method in METHODS
                started=time_ns()
                ranked=pu_rank(split.inputs.training,split.inputs.candidates;method,ranking_seed=split.seed+10000,tie_seed=20260901)
                push!(runtimes,(design=design,policy=policy,split_seed=split.seed,method=method,seconds=(time_ns()-started)/1e9))
                rows=write_rank(joinpath(folder,"$method.tsv"),ranked,split.evaluation.heldout)
                if design=="composition"
                    old=table(baseline.files["full_pipeline/$sub/$method.tsv"])
                    check(length(old)==length(rows) && all(all(string(getproperty(row,k))==prior[string(k)] for k in keys(row)) for (row,prior) in zip(rows,old)),"control ranking mismatch")
                end
                key=(design,split.seed,method)
                if policy=="exclude_mixed";shared[key]=ranked;end
                if policy=="unlabel_mixed"
                    common=Set(r.composition for r in shared[key])
                    check([r for r in ranked if r.composition in common]==shared[key],"common-candidate scores/order differ")
                end
                for m in pu_metrics([r.composition for r in ranked],split.evaluation.heldout;budgets=baseline.budgets)
                    push!(metrics,(design=design,policy=policy,split_seed=split.seed,method=method,training_count=length(split.inputs.training),m...))
                    if design=="composition"
                        old=only(r for r in base_metrics if r["mode"]=="full_pipeline" && r["policy"]==policy && parse(Int,r["split_seed"])==split.seed && r["method"]==method && parse(Int,r["budget"])==m.budget)
                        check(all(parse(Float64,old[string(k)])==Float64(getproperty(m,k)) for k in keys(m)),"control metric mismatch")
                    end
                end
                if method=="similarity"
                    scores=Dict(r.composition=>r.score for r in ranked);h=Set(split.evaluation.heldout)
                    detail=[(composition=formula(c),maximum_similarity=scores[c],observed_label=c in h ? "positive" : "unlabelled") for c in split.inputs.candidates]
                    EkaCompositions.pu_write_rows(joinpath(folder,"candidate-similarity.tsv"),keys(first(detail)),detail)
                    for subset in ("all","positive","unlabelled")
                        vals=[scores[c] for c in split.inputs.candidates if subset=="all" || (c in h ? "positive" : "unlabelled")==subset]
                        push!(diagnostics,(design=design,policy=policy,split_seed=split.seed,subset=subset,diagnostic(vals)...))
                    end
                end
            end
        end
        check(length(metrics)==length(DESIGNS)*length(POLICIES)*length(baseline.seeds)*length(METHODS)*length(baseline.budgets),"incomplete metric grid")
        for (name,rows) in (("metrics.tsv",metrics),("runtime.tsv",runtimes),("populations.tsv",[b.population for b in branches]),("similarity-diagnostics.tsv",diagnostics))
            EkaCompositions.pu_write_rows(joinpath(target,name),keys(first(rows)),rows)
        end
        config["deterministic_file_hashes"]=Dict(replace(relpath(joinpath(d,n),target),'\\'=>'/')=>digest(read(joinpath(d,n))) for (d,_,ns) in walkdir(target) for n in ns if n!="runtime.tsv")
        EkaCompositions.recovery_write_toml(joinpath(target,"config.toml"),config)
    catch
        rm(target;recursive=true);rethrow()
    end
    return (;path=target,metrics,config)
end
end
