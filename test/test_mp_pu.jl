@testset "PU metrics: hand-calculated observed-label recovery" begin
    ranking = ["LiNaO", "CaTiO3", "MgAl2O4", "BaTiO3"]
    heldout = ["CaTiO3", "MgAl2O4"]
    rows = pu_metrics(ranking, heldout; budgets=[1, 2, 3, 4])
    @test getproperty.(rows, :hits) == [0, 1, 2, 2]
    @test getproperty.(rows, :observed_label_fraction) == [0.0, 0.5, 2/3, 0.5]
    @test getproperty.(rows, :heldout_recall) == [0.0, 0.5, 1.0, 1.0]
    @test getproperty.(rows, :observed_label_enrichment) == [0.0, 1.0, 4/3, 1.0]
    @test getproperty.(rows, :random_expected_hits) == [0.5, 1.0, 1.5, 2.0]
    @test [(r.random_expected_hits_numerator, r.random_expected_hits_denominator) for r in rows] == [(1,2), (1,1), (3,2), (2,1)]
    thirds = only(pu_metrics(ranking[1:3], [ranking[1]]; budgets=[2]))
    @test thirds.random_expected_hits_numerator == 2 && thirds.random_expected_hits_denominator == 3
    @test thirds.random_expected_hits == 2/3
    all_positive = pu_metrics(ranking, ranking; budgets=[1,4])
    @test getproperty.(all_positive, :observed_label_fraction) == [1.0,1.0]
    @test getproperty.(all_positive, :observed_label_enrichment) == [1.0,1.0]
    @test only(pu_metrics(["LiNaO"], ["O2Li2Na2"]; budgets=[1])).hits == 1
    for bad_ranking in ([], ["LiNaO", "Li2Na2O2"])
        @test_throws ArgumentError pu_metrics(bad_ranking, heldout; budgets=[1])
    end
    for bad_heldout in ([], ["LiNaO", "Li2Na2O2"], ["SrTiO3"])
        @test_throws ArgumentError pu_metrics(ranking, bad_heldout; budgets=[1])
    end
    for bad_budgets in ([], [0], [5], [1,1], [true], [1.5], "1")
        @test_throws ArgumentError pu_metrics(ranking, heldout; budgets=bad_budgets)
    end
    # Exhaustive two-position subsets of a four-candidate pool (two positives):
    # exact uniform mean = one hit. No stochastic pass/fail tolerance.
    subset_hits = [(i in (2,3)) + (j in (2,3)) for i in 1:4 for j in i+1:4]
    @test sum(subset_hits)//length(subset_hits) == rows[2].random_expected_hits_numerator//rows[2].random_expected_hits_denominator
end

@testset "PU rankers: training-only features and frozen ties" begin
    training = ["CaTiO3", "BaTiO3"]
    candidates = ["MgTiO3", "SrTiO3", "CaZrO3", "MgAl2O4"]
    popularity = pu_rank(training, candidates; method="popularity")
    @test formula.([r.composition for r in popularity]) == ["O3Sr1Ti1", "Mg1O3Ti1", "Ca1O3Zr1", "Al2Mg1O4"]
    @test getproperty.(popularity, :score) == [2/3, 2/3, 0.5, 1/3]
    # Golden keys independently ordered with Python hashlib.
    random = pu_rank(training, candidates; method="random")
    @test formula.([r.composition for r in random]) == ["O3Sr1Ti1", "Al2Mg1O4", "Mg1O3Ti1", "Ca1O3Zr1"]
    @test first(random).random_key == "0258222e9f909963d1fd1d5e893bfed04a646c4e31010741ed2f9af166e63d6a"
    @test first(random).tie_key == "0a39da58b15a2942e1a9c07eed488f6c18fb9d46abdde88e5e080795b8574b6d"
    @test all(r -> r.score === nothing, random)
    @test all(r -> isempty(r.random_key), popularity)
    for method in ("random", "popularity")
        first_run = pu_rank(training, candidates; method)
        @test pu_rank(reverse(training), reverse(candidates); method) == first_run
        @test pu_rank(["O6Ti2Ca2", "BaTiO3"], candidates; method) == first_run
        @test all(r -> propertynames(r) == (:composition, :score, :random_key, :tie_key), first_run)
        # Changing evaluator labels changes metrics, never scores/order for fixed inputs.
        order = [r.composition for r in first_run]
        original = deepcopy(first_run)
        a = only(pu_metrics(order, [first(order)]; budgets=[1]))
        b = only(pu_metrics(order, [last(order)]; budgets=[1]))
        @test a.hits == 1 && b.hits == 0
        @test first_run == original == pu_rank(training, candidates; method)
    end
    refit = pu_rank(["Mg2TiO4", "Mg3TiO5"], candidates; method="popularity")
    @test only(r.score for r in refit if r.composition == Composition("MgTiO3")) == 1.0
    @test pu_rank(training, candidates; method="popularity") == popularity # No cross-split cache.
    @test pu_rank(["Mg2TiO4"], candidates; method="random") == random # Training doesn't affect random keys.
    Random.seed!(855); expected = rand(UInt64, 2); Random.seed!(855)
    pu_rank(training, candidates; method="random")
    @test rand(UInt64, 2) == expected
    @test_throws ArgumentError pu_rank(training, candidates; method="score")
    @test_throws ArgumentError pu_rank([], candidates; method="random")
    @test_throws ArgumentError pu_rank(training, []; method="popularity")
    @test_throws ArgumentError pu_rank(vcat(training, ["Ca2Ti2O6"]), candidates; method="popularity")
    @test_throws ArgumentError pu_rank(training, vcat(candidates, ["Mg2Ti2O6"]); method="random")
    @test_throws ArgumentError pu_rank(training, ["Ba2Ti2O6"]; method="random")
    @test_throws ArgumentError pu_rank(training, ["MgO"]; method="random")
    @test_throws ArgumentError pu_rank(training, [("MgTiO3", "positive")]; method="random")
    @test_throws ArgumentError pu_rank(training, candidates; method="random", ranking_seed=-1)
    @test_throws ArgumentError pu_rank(training, candidates; method="popularity", tie_seed=true)
end

function pu_test_bundle(dir)
    snapshot, audit = recovery_test_inputs(dir)
    bundle = joinpath(dir, "splits")
    split_mp_recovery(snapshot, audit, bundle; synthetic=true, seeds=[0,1], budgets=[1,4])
    return snapshot, audit, bundle
end

function pu_rehash_test_bundle(bundle, member=nothing)
    rootpath = joinpath(bundle, "manifest.toml")
    root = TOML.parsefile(rootpath)
    for name in keys(root["split_manifest_hashes"])
        path = joinpath(bundle, split(name, '/')...)
        m = TOML.parsefile(path)
        if member !== nothing
            m["membership_hashes"][member] = bytes2hex(sha256(read(joinpath(dirname(path), split(member, '/')...))))
            Eka.recovery_write_toml(path, m)
        end
        root["split_manifest_hashes"][name] = bytes2hex(sha256(read(path)))
    end
    Eka.recovery_write_toml(rootpath, root)
end

@testset "PU verified bundle loader and evaluator" begin
    mktempdir() do dir
        snapshot, audit, bundle = pu_test_bundle(dir)
        before = recovery_tree(bundle)
        loaded = load_mp_recovery(bundle, snapshot, audit; synthetic=true)
        @test loaded.result == mp_recovery_splits(recovery_test_groups(); seeds=[0,1], budgets=[1,4])
        @test length(loaded.files) > 8
        first_run = benchmark_pu(bundle, snapshot, audit, joinpath(dir, "first"); synthetic=true)
        second = benchmark_pu(bundle, snapshot, audit, joinpath(dir, "second"); synthetic=true)
        @test length(first_run.metrics) == 8
        @test Set(m.method for m in first_run.metrics) == Set(["random", "popularity"])
        @test Set((m.split_seed,m.method,m.budget) for m in first_run.metrics) ==
            Set((s,m,k) for s in 0:1 for m in ("random","popularity") for k in (1,4))
        deterministic(tree) = Dict(k=>v for (k,v) in tree if k != "runtime.tsv")
        @test deterministic(recovery_tree(first_run.path)) == deterministic(recovery_tree(second.path))
        @test first_run.metrics == second.metrics
        @test recovery_tree(bundle) == before
        @test first_run.config["split_bundle_manifest_sha256"] == bytes2hex(sha256(read(joinpath(bundle,"manifest.toml"))))
        @test first_run.config["is_synthetic"] === true
        for (name, hash) in first_run.config["deterministic_file_hashes"]
            @test bytes2hex(sha256(read(joinpath(first_run.path, split(name,'/')...)))) == hash
        end
        @test length(first_run.config["deterministic_file_hashes"]) == 6
        @test !haskey(first_run.config["deterministic_file_hashes"], "runtime.tsv")
        @test occursin("not scientific evidence", read(joinpath(first_run.path,"report.md"),String))
        for split in loaded.result.splits, method in ("random","popularity")
            path=joinpath(first_run.path,"split-$(lpad(split.seed,2,'0'))","$method.tsv")
            lines = Base.split(chomp(read(path,String)), '\n')
            @test length(lines)==5 # Complete pool, not just requested top k.
            rows=[Base.split(line,'\t';keepempty=true) for line in lines[2:end]]
            @test Set(r[2] for r in rows)==Set(formula.(split.inputs.candidates))
            @test count(r->r[6]=="positive",rows)==2
            @test all(r->r[6] in ("positive","unlabelled"),rows)
        end
        @test_throws ArgumentError benchmark_pu(bundle,snapshot,audit,first_run.path;synthetic=true)
        @test deterministic(recovery_tree(first_run.path)) == deterministic(recovery_tree(second.path))
        args=["benchmark-pu","--splits",bundle,"--snapshot",snapshot,"--audit",audit,"--output",joinpath(dir,"cli"),"--synthetic"]
        code, stdout, _ = run_cli(args)
        @test code==0 && occursin("8 metric rows",stdout)
        @test deterministic(recovery_tree(joinpath(dir,"cli")))==deterministic(recovery_tree(first_run.path))
        @test run_cli(args)[1]==2
        @test run_cli(["benchmark-pu","--help"])[1]==0
        @test run_cli(["benchmark-pu"])[1]==2
        @test_throws ArgumentError load_mp_recovery(bundle,snapshot,audit) # No implicit synthetic mode.
    end
end

@testset "PU loader rejects tampering even with rewritten checksums" begin
    mktempdir() do dir
        snapshot,audit,bundle=pu_test_bundle(dir)
        saved=recovery_tree(bundle)
        function reject(mutate)
            try
                mutate()
                @test_throws ArgumentError benchmark_pu(bundle,snapshot,audit,joinpath(dir,"rejected");synthetic=true)
                @test !ispath(joinpath(dir,"rejected"))
            finally
                for (name, bytes) in saved
                    write(joinpath(bundle,name),bytes)
                end
            end
        end
        for name in ("manifest.toml","split-00/manifest.toml","provenance/protocol.md",
                     "provenance/implementation/src/mp_recovery.jl","provenance/audit/compositions.tsv",
                     "provenance/unresolved.tsv","split-00/inputs/candidates.tsv")
            reject() do
                p=joinpath(bundle,split(name,'/')...);write(p,read(p,String)*"tamper\n")
            end
        end
        for member in ("evaluation/labels.tsv","evaluation/heldout.tsv","inputs/training.tsv","inputs/candidates.tsv")
            reject() do
                p=joinpath(bundle,"split-00",split(member,'/')...)
                text=read(p,String)
                if member=="evaluation/labels.tsv"
                    text=replace(text,"positive"=>"unlabelled";count=1)
                else
                    lines=split(chomp(text),'\n');reverse!(view(lines,2:length(lines)));text=join(lines,'\n')*"\n"
                end
                write(p,text);pu_rehash_test_bundle(bundle,member)
            end
        end
        # An invalid second split must prevent any evaluation, not leave a partial run.
        reject() do
            p=joinpath(bundle,"split-01/evaluation/labels.tsv")
            write(p,replace(read(p,String),"positive"=>"negative";count=1))
            pu_rehash_test_bundle(bundle,"evaluation/labels.tsv")
        end
        for (key,value) in (("tie_seed",7),("ranking_seeds",[7,8]),("split_seeds",[0,0]),
                          ("split_count",1),("positive_count",11),("scope","other"),("is_synthetic",false))
            reject() do
                p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p);m[key]=value;Eka.recovery_write_toml(p,m)
            end
        end
        reject() do
            p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p)
            delete!(m["split_manifest_hashes"],"split-01/manifest.toml");Eka.recovery_write_toml(p,m)
        end
        reject() do
            p=joinpath(bundle,"split-00/manifest.toml");m=TOML.parsefile(p)
            m["membership_hashes"]["../../outside"]="bad";Eka.recovery_write_toml(p,m)
            pu_rehash_test_bundle(bundle)
        end
        reject() do
            p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p)
            m["implementation_hashes"]["../../outside"]="bad";Eka.recovery_write_toml(p,m)
        end
    end
end
