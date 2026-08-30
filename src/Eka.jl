"""
Explore precomputed chemical-composition scores with validated, canonical formulas.
"""
module Eka

using SQLite
using DBInterface
using ArgParse
using Printf
using SHA
using PrecompileTools: @compile_workload

export Composition, formula, species, query_compositions, main
export AbstractRankingMethod, ScoreRanking, SimilarityRanking, ranking_value
export rank_compositions, rank_by_score, rank_by_similarity, similarity
export database_info, validate_database, import_compositions, import_tsv

include("compositions.jl")
include("ranking.jl")
include("database.jl")
include("import.jl")
include("cli.jl")
include("precompile.jl")

end
