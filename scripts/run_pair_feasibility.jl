# Synthetic development only: accepts no real-data, membership or label paths.
using EkaCompositions, SHA, TOML
const EP=EkaCompositions.Research.ElementPairModel
const ElementPairModel=EP

function small_case()
    communities=(("Li","Na","K","Rb"),("Mg","Ca","Sr","Ba"))
    hidden=Set([Set(["Li","Na"]),Set(["Mg","Ca"])])
    training=String[]
    for cluster in communities, i in 1:3, j in i+1:4
        Set([cluster[i],cluster[j]]) in hidden && continue
        for amount in 1:3;push!(training,"$(cluster[i])$(amount)$(cluster[j])1O1");end
    end
    elements=vcat(collect.(communities)...)
    candidates=["$(elements[i])1$(elements[j])1O2" for i in 1:7 for j in i+1:8]
    append!(candidates,["ZnFeO2","CsRbO2"])
    return training,candidates,["LiNaO2","MgCaO2"]
end

function size_case()
    elements=EP.ELEMENTS[1:80]
    pairs=[(elements[i],elements[j]) for i in 1:79 for j in i+1:80]
    # Leave some known-element pairs unobserved, independent of any labels.
    pairs=[p for (i,p) in enumerate(pairs) if i%7!=0]
    training=[begin a,b=pairs[mod1(i,length(pairs))];"$(a)$(1+div(i-1,length(pairs)))$(b)1O1" end for i in 1:4288]
    allpairs=[(EP.ELEMENTS[i],EP.ELEMENTS[j]) for i in 1:116 for j in i+1:117]
    candidates=[begin a,b=allpairs[mod1(i,length(allpairs))];"$(a)1$(b)1O$(2+div(i-1,length(allpairs)))" end for i in 1:9293]
    return training,candidates
end

function main(args)
    length(args)==1 || error("usage: run_pair_feasibility.jl NEW_OUTPUT (synthetic only)")
    target=abspath(only(args));EP.check(!ispath(target)&&!islink(target),"refusing to overwrite feasibility output")
    EP.check(isdir(dirname(target)),"output parent must exist")
    settings=EP.Settings();settingsdict=Dict(string(k)=>getproperty(settings,k) for k in fieldnames(EP.Settings))
    times=NamedTuple[];summaries=NamedTuple[];mkdir(target)
    try
        for name in ("small","size_check")
            training,candidates=name=="small" ? small_case()[1:2] : size_case()
            cold=@timed EP.fit(training;settings)
            warm=@timed EP.fit(training;settings)
            model=warm.value
            EP.check(cold.value.factors==model.factors && cold.value.trace==model.trace,"fit not reproducible")
            ranking=@timed EP.rank_candidates(model,candidates)
            ranked=ranking.value
            EP.check(length(ranked)==length(candidates),"incomplete coverage")
            p=joinpath(target,name);mkdir(p)
            write(joinpath(p,"training.tsv"),EkaCompositions.recovery_formulas(Composition.(model.training)))
            write(joinpath(p,"candidates.tsv"),EkaCompositions.recovery_formulas(sort!(Composition.(candidates);by=formula)))
            EkaCompositions.pu_write_rows(joinpath(p,"objective.tsv"),keys(first(model.trace)),model.trace)
            factorrows=[(element=EP.ELEMENTS[i],factor=k,value=model.factors[i,k],seen_in_training=model.active[i]) for i in 1:117 for k in 1:settings.rank]
            EkaCompositions.pu_write_rows(joinpath(p,"factors.tsv"),keys(first(factorrows)),factorrows)
            rows=[(rank=i,composition=formula(r.composition),score=r.score,coverage=r.coverage,observed_training_pair=r.observed_training_pair,tie_key=r.tie_key) for (i,r) in enumerate(ranked)]
            EkaCompositions.pu_write_rows(joinpath(p,"ranking.tsv"),keys(first(rows)),rows)
            if name=="small"
                heldout=Composition.(small_case()[3]);m=pu_metrics([r.composition for r in ranked],heldout;budgets=[1,4,10])
                EkaCompositions.pu_write_rows(joinpath(p,"synthetic-metrics.tsv"),keys(first(m)),m)
                write(joinpath(p,"synthetic-heldout.tsv"),EkaCompositions.recovery_formulas(sort!(heldout;by=formula)))
            end
            push!(summaries,(case=name,training_count=length(training),candidate_count=length(candidates),active_elements=count(model.active),
                cold_candidates=count(r->r.coverage=="unseen_element_zero",ranked),unobserved_known_pairs=count(r->r.coverage=="known_elements"&&!r.observed_training_pair,ranked),
                iterations=last(model.trace).iteration,termination=model.termination,initial_objective=first(model.trace).objective,
                final_objective=last(model.trace).objective,final_projected_gradient=last(model.trace).projected_gradient,
                distinct_scores=length(unique(r.score for r in ranked))))
            push!(times,(case=name,cold_fit_seconds=cold.time,warm_fit_seconds=warm.time,ranking_seconds=ranking.time,warm_fit_allocated_bytes=warm.bytes))
        end
        EkaCompositions.pu_write_rows(joinpath(target,"summary.tsv"),keys(first(summaries)),summaries)
        EkaCompositions.pu_write_rows(joinpath(target,"runtime.tsv"),keys(first(times)),times)
        root=normpath(joinpath(@__DIR__,".."))
        files=["src/element_pair_model.jl","scripts/run_pair_feasibility.jl","docs/mp-learned-feasibility.md","Project.toml"]
        isfile(joinpath(root,"Manifest.toml"))&&push!(files,"Manifest.toml")
        for name in files;p=joinpath(target,"implementation",name);mkpath(dirname(p));write(p,read(joinpath(root,name)));end
        hashes=Dict(replace(relpath(joinpath(d,n),target),'\\'=>'/')=>bytes2hex(sha256(read(joinpath(d,n)))) for (d,_,ns) in walkdir(target) for n in ns if n!="runtime.tsv")
        config=Dict("model_id"=>EP.MODEL_ID,"is_synthetic"=>true,"settings"=>settingsdict,"julia_version"=>string(VERSION),"deterministic_file_hashes"=>hashes)
        EkaCompositions.recovery_write_toml(joinpath(target,"config.toml"),config)
        println("Synthetic pair-model feasibility complete: ",target)
    catch
        rm(target;recursive=true);rethrow()
    end
end
main(ARGS)
