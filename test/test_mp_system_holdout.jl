include(joinpath(@__DIR__,"..","src","mp_system_holdout.jl"))
const SH=MPSystemHoldout

function system_test_inputs(dir)
    body=IOBuffer();id=0
    for (j,e) in enumerate(["Li","K","Rb","Cs","Be","Mg","Ca","Sr","Ba","Al"])
        last=j==1 ? 10 : 5
        for i in 1:last
            id+=1;println(body,"mp-$id\t$(e)$(i)Na1O1\tfalse\ticsd:synthetic-$id\t.")
        end
        id+=1;println(body,"mp-$id\t$(e)1Na1O1\ttrue\t.\t.")
        for i in last+1:last+2
            id+=1;println(body,"mp-$id\t$(e)$(i)Na1O1\ttrue\t.\t.")
        end
    end
    id+=1;println(body,"mp-$id\tMgAlO\ttrue\t.\t.") # unlabelled-only system
    id+=1;println(body,"mp-$id\tFeCoO\tunknown\t.\t.")
    hash=bytes2hex(sha256(read(joinpath(@__DIR__,"..","scripts","export_mp_pilot.py"))))
    snapshot=mp_test_snapshot(dir,String(take!(body));overrides=Dict("exporter_sha256"=>hash))
    audit=joinpath(dir,"audit");audit_mp_snapshot(snapshot,audit)
    return snapshot,audit
end

@testset "System grouping, policy alignment and diagnostics" begin
    @test SH.system("O6Ti2Ba2")==SH.system("BaTiO3")=="Ba-O-Ti"
    @test SH.system("SrTiO3")!="Ba-O-Ti"
    @test EkaCompositions.recovery_protocol(SH.PROTOCOL).sha256==bytes2hex(sha256(read(joinpath(@__DIR__,"..","docs","mp-system-holdout-protocol.md"))))
    @test SH.diagnostic([0.0,0.5,0.9,1.0])==(n=4,mean=0.6,min=0.0,p10=0.0,median=0.5,p90=1.0,max=1.0,fraction_ge_09=0.5,fraction_ge_099=0.25)
    @test SH.concentration(Composition.(["LiNaO","Li2NaO","MgNaO"]))==(largest=2/3,top5=1.0)
    mktempdir() do dir
        snapshot,audit=system_test_inputs(dir)
        source=EkaCompositions.recovery_verified_inputs(snapshot,audit;synthetic=true)
        groups=SH.source_groups(source)
        branches=SH.preflight(groups;seeds=0:19,budgets=[1,4])
        @test length(branches)==120
        @test SH.preflight(reverse(groups);seeds=19:-1:0,budgets=[4,1])==branches
        mixed=Set(Composition(g.composition) for g in groups if g.mixed)
        @test length(mixed)==10
        for seed in 0:19
            ex=only(b for b in branches if b.design=="system" && b.policy=="exclude_mixed" && b.split.seed==seed)
            un=only(b for b in branches if b.design=="system" && b.policy=="unlabel_mixed" && b.split.seed==seed)
            @test ex.split.inputs.training==un.split.inputs.training
            @test ex.split.evaluation.heldout==un.split.evaluation.heldout
            @test ex.population.system_overlap_count==un.population.system_overlap_count==0
            @test ex.population.unused_unlabelled_count>0
            @test isempty(intersect(mixed,Set(ex.split.inputs.training)))
            @test isempty(intersect(mixed,Set(un.split.inputs.training)))
            @test Set(un.split.inputs.candidates)==union(Set(ex.split.inputs.candidates),Set(c for c in mixed if SH.system(c) in SH.selections(SH.universe(groups),seed)))
            for method in SH.METHODS
                a=pu_rank(ex.split.inputs.training,ex.split.inputs.candidates;method,ranking_seed=seed+10000)
                b=pu_rank(un.split.inputs.training,un.split.inputs.candidates;method,ranking_seed=seed+10000)
                @test a==filter(r->!(r.composition in mixed),b)
            end
        end
        # Whole-system selection is independent of label changes within originally
        # eligible systems; the ranker has no evaluation-label argument.
        a=first(filter(b->b.design=="system",branches)).split
        relabelled=merge(a,(evaluation=(heldout=a.inputs.candidates[1:1],labels=fill("unlabelled",length(a.inputs.candidates))),))
        @test pu_rank(a.inputs.training,a.inputs.candidates;method="similarity")==pu_rank(relabelled.inputs.training,relabelled.inputs.candidates;method="similarity")
        @test_throws ArgumentError SH.preflight(groups;budgets=[10000])
        @test_throws ArgumentError SH.system_splits(groups,"bogus";budgets=[1])
        @test_throws ArgumentError SH.preflight(vcat(groups,groups[1:1]);budgets=[1])
        @test_throws ArgumentError SH.selections(["Li-Na-O"],0)
        @test_throws ArgumentError SH.preflight([(composition="Li$(i)NaO",label=i<6 ? "positive" : "unlabelled",mixed=false) for i in 1:6];budgets=[1])
        @test any(b.population.candidate_system_count>b.population.heldout_system_count for b in branches if b.design=="system")
    end
end

@testset "System holdout full workflow and corrupt controls" begin
    mktempdir() do dir
        snapshot,audit=system_test_inputs(dir)
        splitdir=joinpath(dir,"splits")
        split_mp_recovery(snapshot,audit,splitdir;synthetic=true,seeds=0:2,budgets=[1,4])
        pilot=benchmark_pu(splitdir,snapshot,audit,joinpath(dir,"pilot");synthetic=true)
        baseline=SH.LS.run_sensitivity(snapshot,audit,pilot.path,joinpath(dir,"sensitivity");synthetic=true)
        before=recovery_tree(baseline.path)
        a=SH.run_system_holdout(snapshot,audit,baseline.path,joinpath(dir,"system");synthetic=true)
        b=SH.run_system_holdout(snapshot,audit,baseline.path,joinpath(dir,"rerun");synthetic=true)
        @test length(a.metrics)==108
        deterministic(tree)=Dict(k=>v for (k,v) in tree if k!="runtime.tsv")
        @test deterministic(recovery_tree(a.path))==deterministic(recovery_tree(b.path))
        @test recovery_tree(baseline.path)==before
        @test_throws ArgumentError SH.run_system_holdout(snapshot,audit,baseline.path,a.path;synthetic=true)
        for (name,hash) in a.config["deterministic_file_hashes"]
            @test bytes2hex(sha256(read(joinpath(a.path,name))))==hash
        end
        ranking="full_pipeline/original/split-00/popularity.tsv"
        p=joinpath(baseline.path,ranking)
        write(p,replace(read(p,String),"positive"=>"unlabelled";count=1))
        confpath=joinpath(baseline.path,"config.toml");cfg=TOML.parsefile(confpath)
        cfg["deterministic_file_hashes"][ranking]=bytes2hex(sha256(read(p)))
        EkaCompositions.recovery_write_toml(confpath,cfg)
        @test_throws ArgumentError SH.run_system_holdout(snapshot,audit,baseline.path,joinpath(dir,"corrupt");synthetic=true)
        @test !ispath(joinpath(dir,"corrupt"))
    end
end
