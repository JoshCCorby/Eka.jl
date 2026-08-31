using Test, Random, Eka, SQLite, DBInterface

const FIXTURE = joinpath(@__DIR__, "fixtures", "tiny_test.db")
include("fixtures/build_fixture.jl")

@testset "Eka" begin
    include("test_compositions.jl")
    include("test_database.jl")
    include("test_ranking.jl")
    include("test_legacy.jl")
    include("test_import.jl")
    include("test_cli.jl")
    include("test_benchmark.jl")
end
