using Test, Random, EkaCompositions, SQLite, DBInterface, JSON3

const FIXTURE = joinpath(@__DIR__, "fixtures", "tiny_test.db")
include("fixtures/build_fixture.jl")

@testset "Eka" begin
    include("test_compositions.jl")
    include("test_database.jl")
    include("test_ranking.jl")
    include("test_legacy.jl")
    include("test_inspect_external_scores.jl")
    include("test_import.jl")
    include("test_cli.jl")
    include("test_benchmark.jl")
    include("test_mp_snapshot.jl")
    include("test_mp_audit.jl")
    include("test_mp_recovery.jl")
    include("test_mp_pu.jl")
    include("test_mp_label_sensitivity.jl")
    include("test_mp_system_holdout.jl")
    include("test_element_pair_model.jl")
    include("test_mp_element_pair.jl")
end
