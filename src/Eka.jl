"""
Explore precomputed chemical-composition scores with validated, canonical formulas.
"""
module Eka

using SQLite
using DBInterface
using Dates
using JSON3
using ArgParse
using Printf
using SHA
using TOML
using PrecompileTools: @compile_workload

export Composition, formula, species, query_compositions, main
export AbstractRankingMethod, ScoreRanking, SimilarityRanking, ranking_value
export rank_compositions, rank_by_score, rank_by_similarity, similarity
export database_info, validate_database, import_compositions, import_tsv
export benchmark_rankings, benchmark_tsv
export audit_mp_snapshot, mp_recovery_splits, split_mp_recovery
export write_synthetic_mp_snapshot
export load_mp_recovery, pu_rank, pu_metrics, benchmark_pu

include("compositions.jl")
include("ranking.jl")
include("database.jl")
include("import.jl")
include("benchmark.jl")
include("mp_snapshot.jl")
include("mp_audit.jl")
include("mp_recovery.jl")
include("mp_pu.jl")
include("cli.jl")
include("precompile.jl")

end
