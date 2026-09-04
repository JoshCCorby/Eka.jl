const MPElementPair = EkaCompositions.Research.MPElementPair
const MEP = MPElementPair

# Every path recorded in a provenance manifest must resolve, so that moving or
# renaming a source file fails here rather than silently writing a manifest key
# that points at nothing.
@testset "research provenance paths resolve" begin
    root = normpath(joinpath(@__DIR__, ".."))
    lists = Dict(
        "mp_element_pair" => ["src/element_pair_model.jl", "src/mp_element_pair.jl",
            "src/mp_system_holdout.jl", "src/mp_label_sensitivity.jl", "src/mp_recovery.jl",
            "src/mp_pu.jl", "src/compositions.jl", "src/mp_audit.jl", "src/benchmark.jl",
            "src/EkaCompositions.jl", "scripts/run_element_pair.jl",
            "scripts/analyze_element_pair.py", "scripts/analyze_system_holdout.py",
            "scripts/analyze_pu_pilot.py", "docs/mp-element-pair-protocol.md",
            "docs/mp-learned-feasibility.md", "Project.toml"],
        "pu_producer" => collect(EkaCompositions.PU_PRODUCER_FILES),
        # The mp_system_holdout list holds three of the five docs paths that are
        # manifest keys, and was previously unguarded.
        "mp_system_holdout" => ["src/mp_pu.jl", "src/mp_label_sensitivity.jl",
            "src/mp_system_holdout.jl", "scripts/run_system_holdout.jl",
            "scripts/analyze_system_holdout.py", "scripts/analyze_pu_pilot.py",
            "docs/mp-recovery-protocol.md", "docs/mp-label-sensitivity-protocol.md",
            "docs/mp-system-holdout-protocol.md"],
        "mp_label_sensitivity" => ["src/mp_pu.jl", "src/mp_label_sensitivity.jl",
            "scripts/run_label_sensitivity.jl"],
    )
    for (label, names) in lists, name in names
        @test isfile(joinpath(root, name)) || "$label: missing $name" == ""
    end
end

@testset "element-pair protocol pin" begin
    protocol = EkaCompositions.recovery_protocol(MEP.PROTOCOL)
    @test protocol.id == "eka-mp-element-pair-v1"
    @test protocol.file == "mp-element-pair-protocol.md"
    # The frozen baseline pin must stay a well-formed digest.
    @test length(MEP.BASELINE_SHA) == 64
    @test all(c -> c in "0123456789abcdef", MEP.BASELINE_SHA)
    @test MEP.digest(UInt8[]) == bytes2hex(sha256(UInt8[]))
end

@testset "element-pair output guards" begin
    mktempdir() do dir
        existing = joinpath(dir, "taken")
        mkdir(existing)
        # Refuses to overwrite, before touching any snapshot or baseline input.
        @test_throws ArgumentError MEP.run_evaluation("snapshot", "audit", "baseline", existing)
        missing_parent = joinpath(dir, "absent", "results")
        @test_throws ArgumentError MEP.run_evaluation("snapshot", "audit", "baseline", missing_parent)
    end
end

@testset "element-pair reaches its siblings" begin
    # The Research namespace must bind these to the same modules the package
    # loaded once, not to separately included copies.
    @test MEP.SH === EkaCompositions.Research.MPSystemHoldout
    @test MEP.EP === EkaCompositions.Research.ElementPairModel
    @test MEP.SH.LS === EkaCompositions.Research.MPLabelSensitivity
end
