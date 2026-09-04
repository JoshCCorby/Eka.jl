"""Frozen learned-comparator evaluation using previously verified v2 populations."""
module MPElementPair
using ...EkaCompositions
using ..MPSystemHoldout
using ..ElementPairModel
using SHA, TOML
const SH=MPSystemHoldout
const EP=ElementPairModel
const PROTOCOL="eka-mp-element-pair-v1"
const BASELINE_SHA="c55cc2cf29f75b74abda3dc66194043339b564cf1614d925434adcb581932565"
check(ok,msg)=ok || throw(ArgumentError(msg))
digest(bytes)=bytes2hex(sha256(bytes))

function baseline_inputs(path,source;synthetic)
    raw=read(joinpath(path,"config.toml"));cfg=EkaCompositions.recovery_toml(raw,"v2 config")
    check(synthetic || digest(raw)==BASELINE_SHA,"real v2 baseline config differs from pre-evaluation pin")
    check(cfg["is_synthetic"]===synthetic,"baseline mode mismatch")
    check(cfg["protocol_id"]==SH.PROTOCOL && cfg["protocol_sha256"]==EkaCompositions.recovery_protocol(SH.PROTOCOL).sha256,"baseline protocol mismatch")
    check(cfg["input_hashes"]==Dict(n=>digest(b) for (n,b) in source.files),"baseline source mismatch")
    captured=Dict("config.toml"=>raw)
    for (name,hash) in cfg["deterministic_file_hashes"]
        check(!isabspath(name) && !occursin('\\',name) && !(".." in split(name,'/')),"unsafe baseline path")
        bytes=read(joinpath(path,name));check(digest(bytes)==hash,"baseline hash mismatch: $name")
        if name in ("metrics.tsv","populations.tsv","protocol.md") ||
            (any(d->startswith(name,"$d/"),SH.DESIGNS) && (occursin("/inputs/",name)||occursin("/evaluation/",name)))
            captured[name]=bytes
        end
    end
    return (;cfg,captured)
end

function run_evaluation(snapshot,audit,baseline,output;synthetic=false)
    target=abspath(output);check(!ispath(target)&&!islink(target),"refusing to overwrite model output")
    check(isdir(dirname(target)),"output parent must exist")
    protocol=EkaCompositions.recovery_protocol(PROTOCOL)
    source=EkaCompositions.recovery_verified_inputs(snapshot,audit;synthetic)
    base=baseline_inputs(baseline,source;synthetic)
    seeds,budgets=base.cfg["split_seeds"],base.cfg["budgets"]
    check(synthetic || (seeds==collect(0:19)&&budgets==[20,50,100,200]),"wrong real evaluation grid")
    branches=SH.preflight(SH.source_groups(source);seeds,budgets)
    # Reconstruct and compare every membership before any learned fitting.
    for b in branches
        s=b.split;folder="$(b.design)/$(b.policy)/split-$(lpad(s.seed,2,'0'))"
        expected=(EkaCompositions.recovery_formulas(s.inputs.training),EkaCompositions.recovery_formulas(s.inputs.candidates),
            EkaCompositions.recovery_formulas(s.evaluation.heldout),"composition\tlabel\n"*join("$(formula(c))\t$l\n" for (c,l) in zip(s.inputs.candidates,s.evaluation.labels)))
        for (name,text) in zip(EkaCompositions.PU_MEMBER_FILES,expected)
            check(base.captured["$folder/$name"]==codeunits(text),"baseline membership differs from reconstructed source")
        end
    end
    settings=EP.Settings();root=normpath(joinpath(@__DIR__,".."))
    codefiles=["src/element_pair_model.jl","src/mp_element_pair.jl","src/mp_system_holdout.jl","src/mp_label_sensitivity.jl",
        "src/mp_recovery.jl","src/mp_pu.jl","src/compositions.jl","src/mp_audit.jl","src/benchmark.jl","src/EkaCompositions.jl",
        "scripts/run_element_pair.jl","scripts/analyze_element_pair.py","scripts/analyze_system_holdout.py","scripts/analyze_pu_pilot.py",
        "docs/mp-element-pair-protocol.md","docs/mp-learned-feasibility.md","Project.toml"]
    isfile(joinpath(root,"Manifest.toml"))&&push!(codefiles,"Manifest.toml")
    code=Dict(n=>read(joinpath(root,n)) for n in codefiles)
    cfg=Dict{String,Any}("schema_version"=>1,"protocol_id"=>PROTOCOL,"protocol_sha256"=>protocol.sha256,"is_synthetic"=>synthetic,
        "model_id"=>EP.MODEL_ID,"designs"=>collect(SH.DESIGNS),"policies"=>collect(SH.POLICIES),"split_seeds"=>seeds,"budgets"=>budgets,
        "settings"=>Dict(string(k)=>getproperty(settings,k) for k in fieldnames(EP.Settings)),"tie_seed"=>20260901,
        "baseline_config_sha256"=>digest(base.captured["config.toml"]),"input_hashes"=>Dict(n=>digest(b) for (n,b) in source.files),
        "implementation_hashes"=>Dict(n=>digest(b) for (n,b) in code),"julia_version"=>string(VERSION))
    metrics,diagnostics,times=NamedTuple[],NamedTuple[],NamedTuple[]
    shared=Dict{Tuple{String,Int},Any}()
    mkdir(target)
    try
        write(joinpath(target,"protocol.md"),protocol.bytes)
        for (prefix,files) in (("source",source.files),("baseline",base.captured),("implementation",code)),(name,bytes) in files
            p=joinpath(target,prefix,name);mkpath(dirname(p));write(p,bytes)
        end
        for b in branches
            design,policy,s=b.design,b.policy,b.split
            folder=joinpath(target,design,policy,"split-$(lpad(s.seed,2,'0'))");mkpath(folder)
            fitted=@timed EP.fit(s.inputs.training;settings);model=fitted.value
            scored=@timed EP.rank_candidates(model,s.inputs.candidates);ranked=scored.value
            h=Set(s.evaluation.heldout)
            records=[(rank=i,composition=formula(r.composition),score=r.score,coverage=r.coverage,
                observed_training_pair=r.observed_training_pair,tie_key=r.tie_key,observed_label=r.composition in h ? "positive" : "unlabelled") for (i,r) in enumerate(ranked)]
            EkaCompositions.pu_write_rows(joinpath(folder,"ranking.tsv"),keys(first(records)),records)
            factors=[(element=EP.ELEMENTS[i],factor=k,value=model.factors[i,k],seen_in_training=model.active[i]) for i in 1:117 for k in 1:settings.rank]
            EkaCompositions.pu_write_rows(joinpath(folder,"factors.tsv"),keys(first(factors)),factors)
            counts=[(element_a=EP.ELEMENTS[a],element_b=EP.ELEMENTS[c],count=model.counts[a,c]) for a in 1:116 for c in a+1:117 if model.counts[a,c]>0]
            EkaCompositions.pu_write_rows(joinpath(folder,"pair-counts.tsv"),keys(first(counts)),counts)
            EkaCompositions.pu_write_rows(joinpath(folder,"objective.tsv"),keys(first(model.trace)),model.trace)
            key=(design,s.seed)
            if policy=="exclude_mixed";shared[key]=(factors=model.factors,trace=model.trace,ranked=ranked);end
            if policy=="unlabel_mixed"
                old=shared[key];eligible=Set(r.composition for r in old.ranked)
                check(old.factors==model.factors && old.trace==model.trace && old.ranked==filter(r->r.composition in eligible,ranked),"alternative-policy fitted state or shared scores differ")
            end
            frequencies=Dict{Float64,Int}()
            for r in ranked;frequencies[r.score]=get(frequencies,r.score,0)+1;end
            traininghash=digest(codeunits(EkaCompositions.recovery_formulas(s.inputs.training)))
            push!(diagnostics,(design=design,policy=policy,split_seed=s.seed,training_sha256=traininghash,training_count=length(model.training),
                candidate_count=length(ranked),heldout_count=length(h),prevalence=length(h)/length(ranked),active_elements=count(model.active),
                cold_candidates=count(r->r.coverage=="unseen_element_zero",ranked),distinct_scores=length(frequencies),
                tied_candidates=sum(v for v in values(frequencies) if v>1;init=0),iterations=last(model.trace).iteration,
                termination=model.termination,initial_objective=first(model.trace).objective,final_objective=last(model.trace).objective,
                final_projected_gradient=last(model.trace).projected_gradient))
            push!(times,(design=design,policy=policy,split_seed=s.seed,fit_seconds=fitted.time,ranking_seconds=scored.time,fit_allocated_bytes=fitted.bytes))
            for m in pu_metrics([r.composition for r in ranked],s.evaluation.heldout;budgets)
                push!(metrics,(design=design,policy=policy,split_seed=s.seed,method="element_pair",m...))
            end
        end
        check(length(metrics)==6*length(seeds)*length(budgets),"incomplete learned metric grid")
        for (name,rows) in (("metrics.tsv",metrics),("fit-diagnostics.tsv",diagnostics),("runtime.tsv",times))
            EkaCompositions.pu_write_rows(joinpath(target,name),keys(first(rows)),rows)
        end
        cfg["deterministic_file_hashes"]=Dict(replace(relpath(joinpath(d,n),target),'\\'=>'/')=>digest(read(joinpath(d,n))) for (d,_,ns) in walkdir(target) for n in ns if n!="runtime.tsv")
        EkaCompositions.recovery_write_toml(joinpath(target,"config.toml"),cfg)
    catch
        rm(target;recursive=true);rethrow()
    end
    return (;path=target,metrics,config=cfg)
end
end
