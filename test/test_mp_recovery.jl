# Synthetic fixtures only. No API key, network, or private MP snapshot required.
function recovery_test_groups()
    return vcat([("Li$(i)Na1O1", "positive") for i in 1:10],
        [("MgAl2O4", "unlabelled"), ("CaTiO3", "unlabelled"), ("BaTiO3", "unresolved")])
end

function recovery_test_inputs(dir)
    body = join("mp-$i\tLi$(i)Na1O1\tfalse\ticsd:synthetic-$i\t.\n" for i in 1:10)
    # Equivalent polymorph and mixed flags must not turn one composition into two units.
    body *= "mp-11\tLi2Na2O2\ttrue\t.\t.\n"
    body *= "mp-12\tMgAl2O4\ttrue\t.\t.\nmp-13\tCaTiO3\ttrue\t.\t.\n"
    body *= "mp-14\tBaTiO3\tunknown\t.\t.\nmp-15\tBa2Ti2O6\ttrue\t.\t.\n"
    body *= "mp-16\tMgO\tfalse\ticsd:synthetic-16\t.\n"
    body *= "mp-17\t.\tfalse\t.\tfractional_counts\n"
    source_hash = bytes2hex(sha256(read(joinpath(@__DIR__, "..", "scripts", "export_mp_pilot.py"))))
    snapshot = mp_test_snapshot(dir, body; overrides=Dict("exporter_sha256" => source_hash))
    audit = joinpath(dir, "audit")
    audit_mp_snapshot(snapshot, audit)
    return snapshot, audit
end

function recovery_tree(path)
    return Dict(relpath(joinpath(dir, file), path) => read(joinpath(dir, file))
        for (dir, _, files) in walkdir(path) for file in files)
end

@testset "PU composition membership invariants" begin
    groups = recovery_test_groups()
    result = mp_recovery_splits(groups; budgets=[1, 4])
    @test result.seeds == collect(0:19)
    @test result.positive_count == 10 && result.unlabelled_count == 2
    @test formula.(result.unresolved) == ["Ba1O3Ti1"]
    @test length(result.splits) == 20
    # Independently computed with Python hashlib; lock domain, delimiters and seed encoding.
    @test formula.(result.splits[1].evaluation.heldout) == ["Li10Na1O1", "Li4Na1O1"]
    @test formula.(result.splits[2].evaluation.heldout) == ["Li6Na1O1", "Li9Na1O1"]
    @test formula.(result.splits[20].evaluation.heldout) == ["Li3Na1O1", "Li7Na1O1"]
    positive_set = Set(Composition(g[1]) for g in groups if g[2] == "positive")
    unlabelled_set = Set(Composition(g[1]) for g in groups if g[2] == "unlabelled")
    for split in result.splits
        training, candidates = split.inputs.training, split.inputs.candidates
        heldout = split.evaluation.heldout
        @test length(training) == 8 && length(heldout) == 2 && length(candidates) == 4
        @test isempty(intersect(Set(training), Set(candidates)))
        @test union(Set(training), Set(heldout)) == positive_set
        @test Set(candidates) == union(Set(heldout), unlabelled_set)
        @test isempty(intersect(Set(result.unresolved), union(Set(training), Set(candidates))))
        @test all(issorted(formula.(rows)) for rows in (training, candidates, heldout))
        @test split.evaluation.labels == [c in Set(heldout) ? "positive" : "unlabelled" for c in candidates]
        @test propertynames(split.inputs) == (:training, :candidates)
        @test all(c -> c isa Composition, vcat(training, candidates))
        # Equivalent stoichiometries are not independent candidates/polymorphs.
        @test (Composition("Li2Na2O2") in training) != (Composition("Li1Na1O1") in candidates)
    end
    @test mp_recovery_splits(reverse(groups); budgets=[4, 1], seeds=19:-1:0) == result
    # Scale and element order may change, but canonical membership must not.
    equivalent = [(replace(g[1], "Li1Na1O1" => "O2Na2Li2"), g[2]) for g in groups]
    @test mp_recovery_splits(equivalent; budgets=[1, 4]) == result
    @test mp_recovery_splits([(Composition(g[1]), g[2]) for g in groups]; budgets=[1, 4]) == result
    rng = MersenneTwister(871)
    @test mp_recovery_splits(shuffle(rng, groups); budgets=[1, 4]) == result
    # The helper must neither consume nor depend on the global RNG.
    Random.seed!(591)
    expected = rand(UInt64, 4)
    Random.seed!(591)
    @test mp_recovery_splits(groups; budgets=[1, 4]) == result
    @test rand(UInt64, 4) == expected
    @test mp_recovery_splits(groups; seeds=[19], budgets=[1]).splits[1] == result.splits[20]
end

@testset "PU invalid memberships and configuration" begin
    groups = recovery_test_groups()
    for extra in (("Li2Na2O2", "positive"), ("O1Na1Li1", "unlabelled"), ("LiNaO", "unresolved"))
        @test_throws ArgumentError mp_recovery_splits(vcat(groups, [extra]); budgets=[1])
    end
    for rows in ([], groups[1:4], groups[1:10], [groups[end]],
            [("MgO", "positive")], [("Xx2NaO", "unlabelled")],
            [("LiNaO", "negative")], [("LiNaO", 0)], [("LiNaO", "positive", 5)])
        @test_throws ArgumentError mp_recovery_splits(rows; budgets=[1])
    end
    for seeds in ([], [0, 0], [-1], [true], [0.5], [typemax(Int)], "0", 0)
        @test_throws ArgumentError mp_recovery_splits(groups; seeds, budgets=[1])
    end
    for budgets in ([], [1, 1], [0], [-1], [true], [1.5], [5], "1", 1)
        @test_throws ArgumentError mp_recovery_splits(groups; budgets)
    end
    @test_throws ArgumentError mp_recovery_splits(groups) # Frozen real budgets exceed this tiny synthetic pool.
    minimum_groups = vcat(groups[1:5], [groups[11]])
    minimum_split = only(mp_recovery_splits(minimum_groups; seeds=[0], budgets=[2]).splits)
    @test length(minimum_split.inputs.training) == 4
    @test length(minimum_split.inputs.candidates) == 2
end

@testset "Snapshot-bound PU split artifacts and CLI" begin
    mktempdir() do dir
        snapshot, audit = recovery_test_inputs(dir)
        original_inputs = (recovery_tree(snapshot), recovery_tree(audit))
        output = joinpath(dir, "splits")
        report = split_mp_recovery(snapshot, audit, output; synthetic=true, budgets=[1, 4])
        @test report.result == mp_recovery_splits(recovery_test_groups(); budgets=[1, 4])
        @test report.manifest["protocol_id"] == "eka-mp-recovery-synthetic-v1"
        @test report.manifest["is_synthetic"] === true
        @test report.manifest["unresolved_count"] == 1
        @test report.manifest["excluded_record_count"] == 2
        @test report.manifest["ranking_seeds"] == collect(10000:10019)
        @test report.manifest["split_count"] == 20
        @test TOML.parsefile(joinpath(output, "manifest.toml")) == report.manifest
        for (name, hash) in report.manifest["split_manifest_hashes"]
            path = joinpath(output, name)
            @test bytes2hex(sha256(read(path))) == hash
            manifest = TOML.parsefile(path)
            @test manifest["training_count"] == 8 && manifest["candidate_count"] == 4 && manifest["heldout_count"] == 2
            @test manifest["ranking_seed"] == manifest["split_seed"] + 10000
            @test manifest["tie_seed"] == 20260901
            for (member, expected) in manifest["membership_hashes"]
                @test bytes2hex(sha256(read(joinpath(dirname(path), member)))) == expected
            end
            for input in ("training.tsv", "candidates.tsv")
                text = read(joinpath(dirname(path), "inputs", input), String)
                @test startswith(text, "composition\n") && endswith(text, '\n')
                @test !occursin(r"label|positive|unlabelled|source|material|score|\t", text)
            end
        end
        # Both structures of a mixed group land in one membership; unresolved
        # polymorphs and out-of-scope records never appear in either partition.
        for split in report.result.splits
            @test count(==(Composition("Li2Na2O2")), vcat(split.inputs.training, split.inputs.candidates)) == 1
            @test all(c -> c != Composition("Ba2Ti2O6") && c != Composition("MgO"), vcat(split.inputs.training, split.inputs.candidates))
        end
        rerun = split_mp_recovery(snapshot, audit, joinpath(dir, "rerun"); synthetic=true, budgets=[1, 4])
        @test recovery_tree(output) == recovery_tree(rerun.path)
        @test (recovery_tree(snapshot), recovery_tree(audit)) == original_inputs
        original_output = recovery_tree(output)
        @test_throws ArgumentError split_mp_recovery(snapshot, audit, output; synthetic=true, budgets=[1])
        @test recovery_tree(output) == original_output
        @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "missing", "child"); synthetic=true, budgets=[1])
        # Synthetic mode must be explicit, and cannot be supplied for a real marker.
        @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "real"))
        @test !ispath(joinpath(dir, "real"))
        cli_output = joinpath(dir, "cli")
        args = ["split-mp", "--snapshot", snapshot, "--audit", audit, "--output", cli_output,
            "--synthetic", "--budget", "1", "4"]
        code, stdout, _ = run_cli(args)
        @test code == 0 && occursin("20 composition-safe splits; no rankings", stdout)
        @test recovery_tree(cli_output) == recovery_tree(output)
        @test run_cli(args)[1] == 2
        @test run_cli(["split-mp"])[1] == 2
        @test run_cli(["split-mp", "--help"])[1] == 0
        @test run_cli(["--help"])[1] == 0
        # Symlinks require privileges on some Windows CI hosts.
        if !Sys.iswindows()
            symlink(joinpath(dir, "absent"), joinpath(dir, "link"))
            @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "link"); synthetic=true, budgets=[1])
            @test islink(joinpath(dir, "link"))
            @test !ispath(joinpath(dir, "absent"))
        end
    end
end

@testset "PU provenance rejects corrupted or stale inputs" begin
    mktempdir() do dir
        snapshot, audit = recovery_test_inputs(dir)
        function rejected(file, mutate; synthetic=true, budgets=[1])
            path = joinpath(dir, file)
            original = read(path)
            target = joinpath(dir, "rejected")
            try
                write(path, mutate(String(copy(original))))
                @test_throws ArgumentError split_mp_recovery(snapshot, audit, target; synthetic, budgets)
                @test !ispath(target)
            finally
                write(path, original)
            end
        end
        rejected("snapshot/records.tsv", s -> replace(s, "false" => "true"; count=1))
        rejected("snapshot/records.jsonl", s -> s * " ")
        rejected("audit/snapshot.toml", s -> s * "# edited\n")
        rejected("snapshot/snapshot.toml", s -> "invalid [ TOML")
        rejected("audit/audit.toml", s -> replace(s, "positive_compositions = 10" => "positive_compositions = 9"))
        rejected("audit/audit.toml", s -> replace(s, r"audit_code_sha256 = .*" => "audit_code_sha256 = \"stale\""))
        rejected("audit/audit.toml", s -> replace(s, r"composition_code_sha256 = .*" => "composition_code_sha256 = \"stale\""))
        rejected("audit/compositions.tsv", s -> replace(s, "positive" => "unlabelled"; count=1))
        rejected("audit/compositions.tsv", s -> s * split(s, '\n')[2] * "\n")
        rejected("audit/compositions.tsv", s -> s * replace(split(s, '\n')[2], "Al2Mg1O4" => "Mg2Al4O8") * "\n")
        rejected("audit/compositions.tsv", s -> replace(s, "mp-1;mp-11" => "mp-1"))
        rejected("audit/excluded.tsv", s -> first(split(s, '\n')) * "\n")
        # Change both metadata copies, so failure must come from provenance/schema,
        # not merely mismatched copies. Real mode must still require frozen hashes.
        original = read(joinpath(snapshot, "snapshot.toml"))
        for (key, value, synthetic) in (("exporter_sha256", "unknown", true),
                ("query_include_gnome", true, true), ("is_synthetic", false, true),
                ("is_synthetic", false, false))
            try
                meta = TOML.parse(String(copy(original))); meta[key] = value
                for folder in (snapshot, audit)
                    open(joinpath(folder, "snapshot.toml"), "w") do io
                        TOML.print(io, meta; sorted=true)
                    end
                end
                @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "bad"); synthetic,
                    budgets=synthetic ? [1] : [20, 50, 100, 200])
                @test !ispath(joinpath(dir, "bad"))
            finally
                write(joinpath(snapshot, "snapshot.toml"), original)
                write(joinpath(audit, "snapshot.toml"), original)
            end
        end
        # Equivalent formula spelling and row order do not change synthetic
        # membership; exact input byte hashes in the manifest correctly change.
        original_groups = read(joinpath(audit, "compositions.tsv"), String)
        lines = split(chomp(original_groups), '\n')
        reordered = first(lines) * "\n" * join(reverse(lines[2:end]), '\n') * "\n"
        write(joinpath(audit, "compositions.tsv"), replace(reordered, "Li1Na1O1\t" => "Na2O2Li2\t"))
        report = split_mp_recovery(snapshot, audit, joinpath(dir, "reordered"); synthetic=true, budgets=[1, 4])
        @test report.result == mp_recovery_splits(recovery_test_groups(); budgets=[1, 4])
        # Empty or too-small grouped pools fail before output reservation.
        @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "invalid-budget"); synthetic=true, budgets=[5])
        @test !ispath(joinpath(dir, "invalid-budget"))
        @test_throws ArgumentError split_mp_recovery(snapshot, audit, joinpath(dir, "unfrozen"); seeds=[0], budgets=[1])
        @test !ispath(joinpath(dir, "unfrozen"))
    end
end
