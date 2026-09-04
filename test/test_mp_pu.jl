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
    for method in ("random", "popularity", "similarity")
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

# Deterministic distinct oxygen-containing ternaries for size/streaming checks.
function pu_similarity_pool(count; offset=0)
    others = [e for e in EkaCompositions.ELEMENT_SYMBOLS if e != "O"]
    pairs = [(a, b) for a in others for b in others if a < b]
    return [Composition("$(pairs[i+1][1])1$(pairs[i+1][2])2O3") for i in offset:(offset+count-1)]
end

@testset "PU maximum training similarity: hand-calculated scores and ties" begin
    training = ["CaTiO3", "BaTiO3"]
    candidates = ["MgTiO3", "SrTiO3", "CaZrO3", "MgAl2O4"]
    ranked = pu_rank(training, candidates; method="similarity")
    # Ti+O overlap: (1*1 + 3*3) / (sqrt(11) * sqrt(11)); MgAl2O4 shares only O:
    # (4*3) / (sqrt(21) * sqrt(11)). Both training references give equal values here.
    @test getproperty.(ranked, :score) == [10/11, 10/11, 10/11, 12/(sqrt(21)*sqrt(11))]
    # Three exactly equal scores: order is the frozen score-independent tie policy,
    # never the input order, the stored-score fallback, or a rounding tolerance.
    @test formula.([r.composition for r in ranked]) == ["O3Sr1Ti1", "Mg1O3Ti1", "Ca1O3Zr1", "Al2Mg1O4"]
    @test issorted(getproperty.(ranked[1:3], :tie_key))
    @test allunique(getproperty.(ranked, :tie_key))
    @test all(r -> isempty(r.random_key), ranked)
    # The tie key is shared with popularity: one score-independent policy, not a
    # per-method ordering, and it never depends on any stored model score.
    @test Dict(r.composition => r.tie_key for r in ranked) ==
        Dict(r.composition => r.tie_key for r in pu_rank(training, candidates; method="popularity"))

    # The maximum over training, not the first, the last, or a mean.
    mixed = pu_rank(["CaTiO3", "MgAl2O4"], ["Al2Zn1O4", "Ca1O3Zr1"]; method="similarity")
    scores = Dict(formula(r.composition) => r.score for r in mixed)
    @test scores["Al2O4Zn1"] == 20/21           # Al+O overlap with MgAl2O4.
    @test scores["Ca1O3Zr1"] == 10/11           # Ca+O overlap with CaTiO3.
    @test scores["Al2O4Zn1"] > similarity(Composition("Al2Zn1O4"), Composition("CaTiO3"))
    @test scores["Ca1O3Zr1"] > similarity(Composition("Ca1O3Zr1"), Composition("MgAl2O4"))

    # Exactly the pairwise cosine Eka already computes, maximised over training.
    pool = pu_similarity_pool(60)
    reference_training, reference_candidates = pool[1:25], pool[26:60]
    reference = [maximum(similarity(c, t) for t in reference_training) for c in reference_candidates]
    @test EkaCompositions.pu_max_similarity(reference_candidates, reference_training) == reference
    @test getproperty.(pu_rank(reference_training, reference_candidates; method="similarity"), :score) ==
        sort(reference; rev=true) # Descending score sequence; equal scores allowed.
    @test all(0.0 .<= reference .<= 1.0) && all(isfinite, reference)
    # Every candidate contains oxygen, so no in-scope pair can be fully disjoint.
    @test minimum(reference) > 0.0
    @test EkaCompositions.pu_cosine(EkaCompositions.pu_vector(Composition("CaTiO3")), EkaCompositions.pu_vector(Composition("CaTiO3"))) == 1.0
end

@testset "PU similarity: training isolation, label independence and streaming cost" begin
    training = ["CaTiO3", "BaTiO3"]
    candidates = ["MgTiO3", "SrTiO3", "CaZrO3", "MgAl2O4"]
    baseline = pu_rank(training, candidates; method="similarity")
    score_of(rows, f) = only(r.score for r in rows if r.composition == Composition(f))

    # Adding a training composition may only raise a maximum, and removing it must
    # restore the earlier value: references are refitted per call, never cached.
    widened = pu_rank(vcat(training, ["Al2Mg1O3"]), candidates; method="similarity")
    @test score_of(widened, "MgAl2O4") > score_of(baseline, "MgAl2O4")
    @test all(score_of(widened, f) >= score_of(baseline, f) for f in candidates)
    @test pu_rank(training, candidates; method="similarity") == baseline
    narrowed = pu_rank(["BaTiO3"], candidates; method="similarity")
    @test score_of(narrowed, "MgAl2O4") <= score_of(baseline, "MgAl2O4")
    @test pu_rank(training, candidates; method="similarity") == baseline

    # A candidate's score depends on the training set alone, not on the rest of
    # the pool, so per-split pools cannot leak into one another.
    for f in candidates
        @test only(pu_rank(training, [f]; method="similarity")).score == score_of(baseline, f)
    end

    # Fixed training and candidates: evaluation labels cannot reach the scores.
    order = [r.composition for r in baseline]
    for heldout in ([first(order)], [last(order)], order[2:3])
        @test only(pu_metrics(order, heldout; budgets=[4])).hits == length(heldout)
        @test pu_rank(training, candidates; method="similarity") == baseline
    end
    @test only(pu_metrics(order, [first(order)]; budgets=[1])).hits == 1
    @test only(pu_metrics(order, [last(order)]; budgets=[1])).hits == 0

    # Global RNG state is untouched, and repeated calls are byte-identical.
    Random.seed!(913); expected = rand(UInt64, 2); Random.seed!(913)
    pu_rank(training, candidates; method="similarity")
    @test rand(UInt64, 2) == expected
    @test all(pu_rank(training, candidates; method="similarity") == baseline for _ in 1:3)
    @test_throws ArgumentError pu_rank(training, ["MgO"]; method="similarity")
    @test_throws ArgumentError pu_rank(training, vcat(candidates, ["Ba2Ti2O6"]); method="similarity")
    @test_throws ArgumentError pu_rank(training, [("MgTiO3", "positive")]; method="similarity")

    # Streaming, not a stored pairwise matrix: 300 x 600 pairs would need 1.4 MB
    # of Float64 scores alone. The bound is deliberately loose but far below that.
    stream_training, stream_candidates = pu_similarity_pool(300), pu_similarity_pool(600; offset=300)
    @test isempty(intersect(Set(stream_training), Set(stream_candidates)))
    EkaCompositions.pu_max_similarity(stream_candidates[1:2], stream_training[1:2])
    used = @allocated EkaCompositions.pu_max_similarity(stream_candidates, stream_training)
    @test used < 300_000
    @test used < length(stream_training) * length(stream_candidates) * sizeof(Float64)
    @test length(EkaCompositions.pu_max_similarity(stream_candidates, stream_training)) == length(stream_candidates)
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
            EkaCompositions.recovery_write_toml(path, m)
        end
        root["split_manifest_hashes"][name] = bytes2hex(sha256(read(path)))
    end
    EkaCompositions.recovery_write_toml(rootpath, root)
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
        @test length(first_run.metrics) == 12
        @test Set(m.method for m in first_run.metrics) == Set(["random", "popularity", "similarity"])
        @test Set((m.split_seed,m.method,m.budget) for m in first_run.metrics) ==
            Set((s,m,k) for s in 0:1 for m in ("random","popularity","similarity") for k in (1,4))
        deterministic(tree) = Dict(k=>v for (k,v) in tree if k != "runtime.tsv")
        @test deterministic(recovery_tree(first_run.path)) == deterministic(recovery_tree(second.path))
        @test first_run.metrics == second.metrics
        @test recovery_tree(bundle) == before
        @test first_run.config["split_bundle_manifest_sha256"] == bytes2hex(sha256(read(joinpath(bundle,"manifest.toml"))))
        @test first_run.config["is_synthetic"] === true
        for (name, hash) in first_run.config["deterministic_file_hashes"]
            @test bytes2hex(sha256(read(joinpath(first_run.path, split(name,'/')...)))) == hash
        end
        @test length(first_run.config["deterministic_file_hashes"]) == 8
        @test !haskey(first_run.config["deterministic_file_hashes"], "runtime.tsv")
        @test occursin("not scientific evidence", read(joinpath(first_run.path,"report.md"),String))
        for split in loaded.result.splits, method in ("random","popularity","similarity")
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
        @test code==0 && occursin("12 metric rows",stdout)
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
                p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p);m[key]=value;EkaCompositions.recovery_write_toml(p,m)
            end
        end
        reject() do
            p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p)
            delete!(m["split_manifest_hashes"],"split-01/manifest.toml");EkaCompositions.recovery_write_toml(p,m)
        end
        reject() do
            p=joinpath(bundle,"split-00/manifest.toml");m=TOML.parsefile(p)
            m["membership_hashes"]["../../outside"]="bad";EkaCompositions.recovery_write_toml(p,m)
            pu_rehash_test_bundle(bundle)
        end
        reject() do
            p=joinpath(bundle,"manifest.toml");m=TOML.parsefile(p)
            m["implementation_hashes"]["../../outside"]="bad";EkaCompositions.recovery_write_toml(p,m)
        end
    end
end
