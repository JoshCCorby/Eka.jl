include(joinpath(@__DIR__, "..", "src", "mp_label_sensitivity.jl"))
using .MPLabelSensitivity
const LS = MPLabelSensitivity

@testset "Versioned recovery protocol pins" begin
    @test Eka.recovery_protocol("eka-mp-recovery-v1").sha256 == "f64c1fb803da3cc57aff658341b299824e3d662cc48039586a8bc10410bab21f"
    @test Eka.recovery_protocol(LS.PROTOCOL).sha256 == bytes2hex(sha256(read(joinpath(@__DIR__, "..", "docs", "mp-label-sensitivity-protocol.md"))))
    @test_throws ArgumentError Eka.recovery_protocol("eka-mp-recovery-v999")
    @test_throws ArgumentError Eka.recovery_protocol("../mp-recovery-protocol.md")
end

@testset "Policy membership and fixed-ranking evaluation semantics" begin
    groups = [(composition=f,label=l,mixed=f=="Li1Na1O1") for (f,l) in recovery_test_groups()]
    original = mp_recovery_splits(LS.policy_groups(groups,"original");budgets=[1,2])
    excluded = mp_recovery_splits(LS.policy_groups(groups,"exclude_mixed");budgets=[1,2])
    unlabelled = mp_recovery_splits(LS.policy_groups(groups,"unlabel_mixed");budgets=[1,2])
    mixed = Set([Composition("LiNaO")])
    @test original.positive_count == 10 && excluded.positive_count == unlabelled.positive_count == 9
    @test excluded.unlabelled_count == 2 && unlabelled.unlabelled_count == 3
    @test LS.policy_groups(reverse(groups),"exclude_mixed") == LS.policy_groups(groups,"exclude_mixed")
    for (a,b) in zip(excluded.splits,unlabelled.splits)
        @test a.inputs.training == b.inputs.training
        @test a.evaluation.heldout == b.evaluation.heldout
        @test isempty(intersect(mixed,a.inputs.training))
        @test isempty(intersect(mixed,b.inputs.training))
        @test isempty(intersect(mixed,a.inputs.candidates))
        @test issubset(mixed,Set(b.inputs.candidates))
        for method in LS.METHODS
            x=pu_rank(a.inputs.training,a.inputs.candidates;method,ranking_seed=a.seed+10000)
            y=pu_rank(b.inputs.training,b.inputs.candidates;method,ranking_seed=b.seed+10000)
            @test x == [r for r in y if !(r.composition in mixed)]
        end
    end
    @test_throws ArgumentError LS.policy_groups(groups,"unknown")
    @test_throws ArgumentError LS.policy_groups(vcat(groups,groups[1:1]),"original")
    @test_throws ArgumentError LS.policy_groups([(composition="LiNaO",label="unlabelled",mixed=true)],"original")

    # Deliberately put a mixed positive first, then an unlabelled and a pure
    # positive. Exclusion spends two eligible positions but reaches depth three.
    training=Composition.(["CaTiO3","BaTiO3"])
    candidates=Composition.(["LiNaO","MgAl2O4","SrTiO3"])
    heldout=candidates[[1,3]]
    split=(seed=0,inputs=(training=training,candidates=candidates),evaluation=(heldout=heldout,labels=["positive","unlabelled","positive"]))
    ranked=[(composition=c,score=1.0,random_key="",tie_key="") for c in candidates]
    ex=LS.evaluation_membership(split,mixed,"exclude_mixed")
    un=LS.evaluation_membership(split,mixed,"unlabel_mixed")
    @test ex.inputs.training == un.inputs.training == training
    @test ex.evaluation.heldout == un.evaluation.heldout == candidates[3:3]
    selected=LS.filter_ranking(ranked,ex.inputs.candidates)
    @test getproperty.(selected,:original_rank)==[2,3]
    @test [r.row for r in selected]==ranked[2:3]
    exm=only(pu_metrics([r.row.composition for r in selected],ex.evaluation.heldout;budgets=[2]))
    unm=only(pu_metrics(candidates,un.evaluation.heldout;budgets=[2]))
    @test exm.hits==1 && exm.candidate_count==2 && exm.heldout_count==1 && exm.random_expected_hits==1
    @test unm.hits==0 && unm.candidate_count==3 && unm.heldout_count==1 && unm.random_expected_hits==2/3
    relabelled=merge(ex,(evaluation=(heldout=ex.inputs.candidates[1:1],labels=["positive","unlabelled"]),))
    @test LS.filter_ranking(ranked,relabelled.inputs.candidates)==selected
    @test_throws ArgumentError LS.validate_membership(ex,[3])
    @test_throws ArgumentError LS.validate_membership(merge(ex,(evaluation=(heldout=Composition[],labels=["unlabelled","unlabelled"]),)),[1])
    @test_throws ArgumentError LS.filter_ranking(ranked[1:1],candidates)
end

@testset "Sensitivity complete synthetic workflow and tampered baselines" begin
    mktempdir() do dir
        snapshot,audit=recovery_test_inputs(dir)
        bundle=joinpath(dir,"splits")
        split_mp_recovery(snapshot,audit,bundle;synthetic=true,budgets=[1,2])
        baseline=benchmark_pu(bundle,snapshot,audit,joinpath(dir,"pilot");synthetic=true)
        saved=recovery_tree(baseline.path)
        a=LS.run_sensitivity(snapshot,audit,baseline.path,joinpath(dir,"sensitivity");synthetic=true)
        @test length(a.metrics)==720 # All six branches, 20 seeds, three methods, two budgets.
        @test Set((m.mode,m.policy,m.split_seed,m.method,m.budget) for m in a.metrics)==
            Set((mode,p,s,m,k) for mode in LS.MODES for p in LS.POLICIES for s in 0:19 for m in LS.METHODS for k in [1,2])
        for m in a.metrics
            @test m.heldout_count>=1 && m.candidate_count>=m.budget
            if m.mode=="full_pipeline" && m.policy!="original"
                @test m.mixed_training_count==0 && m.training_count==8 && m.heldout_count==1
                @test m.candidate_count==(m.policy=="exclude_mixed" ? 3 : 4)
            end
        end
        b=LS.run_sensitivity(snapshot,audit,baseline.path,joinpath(dir,"rerun");synthetic=true)
        deterministic(tree)=Dict(k=>v for (k,v) in tree if k!="runtime.tsv")
        @test deterministic(recovery_tree(a.path))==deterministic(recovery_tree(b.path))
        @test recovery_tree(baseline.path)==saved
        @test_throws ArgumentError LS.run_sensitivity(snapshot,audit,baseline.path,a.path;synthetic=true)
        for (name,hash) in a.config["deterministic_file_hashes"]
            @test bytes2hex(sha256(read(joinpath(a.path,name))))==hash
        end
        # An attacker rewriting both ranking bytes and their checksum must not
        # turn a corrupted frozen baseline into a valid sensitivity input.
        ranking=joinpath(baseline.path,"split-00/popularity.tsv")
        old=bytes2hex(sha256(read(ranking)))
        write(ranking,replace(read(ranking,String),"positive"=>"unlabelled";count=1))
        configpath=joinpath(baseline.path,"config.toml")
        config=TOML.parsefile(configpath)
        config["deterministic_file_hashes"]["split-00/popularity.tsv"]=bytes2hex(sha256(read(ranking)))
        Eka.recovery_write_toml(configpath,config)
        @test_throws ArgumentError LS.run_sensitivity(snapshot,audit,baseline.path,joinpath(dir,"bad");synthetic=true)
        @test !ispath(joinpath(dir,"bad"))
    end
end
