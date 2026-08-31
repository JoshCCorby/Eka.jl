using TOML, SHA

@testset "Fixed-budget benchmark" begin
    records = [("MgO", 0.9, 1), ("NaCl", 0.8, 0), ("Mg2O", 0.7, 1), ("LiF", 0.6, 0)]
    training = ["MgO2", "SiO2"]
    result = benchmark_rankings(records, training; budgets=[1, 2, 4], seeds=[8, 3])
    score = filter(m -> m.method == "score" && m.budget == 2, result.metrics) |> only
    @test score.hits == 1
    @test score.precision == 0.5
    @test score.recall == 0.5
    @test score.enrichment == 1.0
    @test score.novel_system_fraction == 0.5
    @test score.unique_system_fraction == 1.0
    @test score.element_coverage ≈ 4 / 6
    full = only(filter(m -> m.method == "score" && m.budget == 4, result.metrics))
    @test full.hits == 2 && full.recall == 1.0 && full.enrichment == 1.0
    @test full.unique_system_fraction == 3 / 4
    @test full.element_coverage == 1.0
    popularity = filter(r -> r.method == "popularity", result.rankings)
    @test popularity[1].composition == "Mg1O1"
    @test popularity[1].ranking_value == 0.75
    @test popularity[2].composition == "Mg2O1"
    @test length(result.metrics) == 12 # 2 deterministic + 2 random runs, 3 budgets

    reordered = benchmark_rankings(reverse(records), reverse(training); budgets=[4, 2, 1], seeds=[3, 8])
    @test result.rankings == reordered.rankings
    @test result.metrics == reordered.metrics
    @test records[1] == ("MgO", 0.9, 1) && training == ["MgO2", "SiO2"]

    # Permuting labels or scores cannot change baseline order or ranking values.
    changed = [(r[1], -r[2], 1 - r[3]) for r in records]
    other = benchmark_rankings(changed, training; budgets=[1], seeds=[3, 8])
    baseline(r) = [(x.method, x.seed, x.composition, x.ranking_value) for x in r.rankings if x.method != "score"]
    @test baseline(result) == baseline(other)
    ties = benchmark_rankings([("NaCl", -2.0, 1), ("LiF", 9.0, 0)], training;
        budgets=[1], methods=["popularity"])
    @test first(ties.rankings).composition == "Cl1Na1" # no stored-score tie break
    nulls = benchmark_rankings([("NaCl", 1.0, 0)], training; budgets=[1], methods=["score"])
    @test only(nulls.metrics).recall === nothing
    @test only(nulls.metrics).enrichment === nothing
    singleton = benchmark_rankings([("NaCl", -3.0, 1)], training; budgets=[1])
    @test all(m -> m.hits == 1 && m.precision == 1.0, singleton.metrics)

    for bad in ([records; [("O2Mg2", 0.1, 0)]], [("MgO2", 1.0, 1)],
            [("MgO", NaN, 1)], [("MgO", Inf, 1)], [("MgO", 1.0, -1)],
            [("MgO", 1.0, missing)], [("MgO", 1.0, true)], [], [("MgO", 1.0)])
        @test_throws ArgumentError benchmark_rankings(bad, training; budgets=[1])
    end
    @test_throws ArgumentError benchmark_rankings(records, ["MgO2", "Mg2O4"]; budgets=[1])
    @test_throws ArgumentError benchmark_rankings(records, []; budgets=[1])
    for options in ((budgets=[0],), (budgets=[5],), (budgets=Int[],), (budgets=[true],),
            (seeds=[-1], budgets=[1]), (seeds=Int[], budgets=[1]),
            (methods=["seko"], budgets=[1]), (methods=String[], budgets=[1]),
            (methods=["score", "score"], budgets=[1]))
        @test_throws ArgumentError benchmark_rankings(records, training; options...)
    end
    # Distinct seeds produce distinct random permutations on a nontrivial pool.
    large = [(string(e, "O"), 0.0, 0) for e in ["Li", "Na", "K", "Rb", "Cs", "Mg", "Ca", "Sr", "Ba", "Zn"]]
    random = benchmark_rankings(large, ["SiO2"]; budgets=[1], seeds=[0, 1], methods=["random"])
    @test [r.composition for r in random.rankings if r.seed == 0] !=
        [r.composition for r in random.rankings if r.seed == 1]
end

@testset "Benchmark reports and CLI" begin
    root = dirname(@__DIR__)
    input = joinpath(root, "examples", "benchmark", "candidates.tsv")
    training = joinpath(root, "examples", "benchmark", "training.tsv")
    @test run_cli(["benchmark", "--help"])[1] == 0
    @test occursin("--training", run_cli(["benchmark", "--help"])[2])
    @test run_cli(["benchmark"])[1] == 2
    mktempdir() do dir
        output = joinpath(dir, "report")
        args = ["benchmark", "--input", input, "--training", training, "--output", output,
            "--source", "Synthetic \"test\"\nfixture", "--budget", "2", "5", "10", "--seeds", "0", "1"]
        status, message, errors = run_cli(args)
        @test status == 0 && isempty(errors)
        @test occursin("Benchmarked 10 candidates", message)
        @test Set(readdir(output)) == Set(["config.toml", "input.tsv", "training.tsv", "candidates.csv", "metrics.json", "benchmark.md"])
        config = TOML.parsefile(joinpath(output, "config.toml"))
        @test config["source"] == "Synthetic \"test\"\nfixture"
        @test config["input_sha256"] == bytes2hex(sha256(read(input)))
        @test config["training_sha256"] == bytes2hex(sha256(read(training)))
        @test read(joinpath(output, "input.tsv")) == read(input)
        @test config["candidate_count"] == 10 && config["positive_count"] == 5
        @test length(readlines(joinpath(output, "candidates.csv"))) == 41
        original = Dict(f => read(joinpath(output, f)) for f in readdir(output))
        @test run_cli(args)[1] == 2
        @test all(read(joinpath(output, f)) == bytes for (f, bytes) in original)
        rerun = joinpath(dir, "rerun")
        benchmark_tsv(joinpath(output, config["input"]), joinpath(output, config["training"]), rerun;
            source=config["source"], budgets=config["budgets"], seeds=config["seeds"], methods=config["methods"])
        @test all(read(joinpath(rerun, f)) == bytes for (f, bytes) in original)

        bad = joinpath(dir, "bad.tsv")
        failed = joinpath(dir, "failed")
        for content in ("composition\tscore\toutcome\nMgO\t1\tunknown\n",
                "composition\tscore\toutcome\nMgO\tNaN\t1\n",
                "composition\tscore\toutcome\nMgO\t1\t1\textra\n",
                "composition\tscore\noutcome\n", "composition\tscore\toutcome\n\n")
            write(bad, content)
            @test_throws ArgumentError benchmark_tsv(bad, training, failed; source="test", budgets=[1])
            @test !ispath(failed)
        end
        write(bad, "composition\tscore\toutcome\r\nNaCl\t-1.0\t0\r\n")
        benchmark_tsv(bad, training, failed; source="test", budgets=[1])
        @test occursin("\"recall\":null", read(joinpath(failed, "metrics.json"), String))
        @test occursin("\"enrichment\":null", read(joinpath(failed, "metrics.json"), String))
        @test_throws ArgumentError benchmark_tsv(input, training, joinpath(dir, "blank"); source=" ", budgets=[1])
        @test_throws ArgumentError benchmark_tsv(input, training, joinpath(dir, "missing", "report"); source="test", budgets=[1])
        if !Sys.iswindows() # Creating symlinks can require elevated Windows privileges.
            symlink(joinpath(dir, "nonexistent"), joinpath(dir, "link"))
            @test_throws ArgumentError benchmark_tsv(input, training, joinpath(dir, "link"); source="test", budgets=[1])
        end
    end
end
