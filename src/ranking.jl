const ScoredComposition = Tuple{Composition,Float64}

struct QueryFilters
    elements::Vector{String}
    nary::Union{Nothing,Vector{Int}}
    threshold::Float64
end

function query_filters(elements, nary, threshold)
    elements isa AbstractString && throw(ArgumentError("elements must be a collection, e.g. [\"Mg\", \"Zn\"]"))
    requested = elements === nothing ? String[] : sort!(unique!([validate_element(e) for e in elements]))
    arities = if nary === nothing
        nothing
    else
        nary isa Union{Integer,AbstractString} &&
            throw(ArgumentError("nary must be a collection of integers, e.g. [2, 3]"))
        values = Int[]
        for n in nary
            n isa Integer && !(n isa Bool) && 1 <= n <= length(ELEMENT_SYMBOLS) ||
                throw(ArgumentError("nary values must be integers between 1 and 118"))
            push!(values, Int(n))
        end
        sort!(unique!(values))
    end
    threshold isa Real && !(threshold isa Bool) && isfinite(threshold) ||
        throw(ArgumentError("threshold must be a finite real number"))
    value = Float64(threshold)
    isfinite(value) || throw(ArgumentError("threshold is outside the supported Float64 range"))
    return QueryFilters(requested, arities, value)
end

function matches_filters(composition::Composition, filters::QueryFilters)
    filters.nary === nothing || length(composition) in filters.nary || return false
    return all(symbol -> any(term -> first(term) == symbol, composition.terms), filters.elements)
end

"""Extend `ranking_value(method, composition, stored_score)` to add a ranking strategy."""
abstract type AbstractRankingMethod end

"""Rank by the supplied database score (no model fitting)."""
struct ScoreRanking <: AbstractRankingMethod end

composition_norm(c::Composition) = sqrt(sum(p -> Float64(last(p))^2, c.terms))

"""Rank by cosine similarity of element-count vectors to a reference composition."""
struct SimilarityRanking <: AbstractRankingMethod
    reference::Composition
    norm::Float64
    SimilarityRanking(reference::Composition) = new(reference, composition_norm(reference))
end
SimilarityRanking(reference::AbstractString) = SimilarityRanking(Composition(reference))

"""
    ranking_value(method::AbstractRankingMethod, composition::Composition, stored_score::Real)

Return the value used to order `composition` under `method`; larger values rank
first. Implement this to add a ranking strategy. The result must be finite, or
`rank_compositions` throws. `stored_score` is the score held in the database,
passed through unchanged, so a method may ignore it. Ties are broken by
descending stored score and then canonical formula.
"""
ranking_value(::ScoreRanking, ::Composition, stored_score::Real) = Float64(stored_score)

function ranking_value(method::SimilarityRanking, composition::Composition, ::Real)
    composition == method.reference && return 1.0
    product = 0.0
    for (symbol, count) in composition.terms
        for (other, amount) in method.reference.terms
            symbol == other && (product += Float64(count) * Float64(amount))
        end
    end
    return clamp(product / (composition_norm(composition) * method.norm), 0.0, 1.0)
end

"""Cosine similarity in [0, 1]; this measures stoichiometric overlap, not chemical plausibility."""
similarity(a::Composition, b::Composition) = ranking_value(SimilarityRanking(b), a, 0.0)

function rank!(results::Vector{ScoredComposition}, method::AbstractRankingMethod=ScoreRanking())
    # Evaluate custom strategies once per candidate; retain the original scores.
    values = [Float64(ranking_value(method, composition, score)) for (composition, score) in results]
    all(isfinite, values) || throw(ArgumentError("ranking method returned a non-finite value"))
    order = sortperm(eachindex(results); by=i -> (-values[i], -results[i][2], formula(results[i][1])))
    return permute!(results, order)
end

"""Return ranked copies of `(Composition, stored_score)` rows. Never mutate the input."""
function rank_compositions(results, method::AbstractRankingMethod=ScoreRanking())
    rows = ScoredComposition[]
    for (composition, score) in results
        composition isa Composition || throw(ArgumentError("ranking requires Composition values"))
        score isa Real && !(score isa Bool) && isfinite(score) && isfinite(Float64(score)) ||
            throw(ArgumentError("ranking requires finite numeric stored scores"))
        push!(rows, (composition, Float64(score)))
    end
    return rank!(rows, method)
end

"""
    rank_by_score(results)

Rank `(Composition, stored_score)` rows by stored score, descending. Shorthand
for `rank_compositions(results, ScoreRanking())`. The input is not mutated.
"""
rank_by_score(results) = rank_compositions(results, ScoreRanking())
"""
    rank_by_similarity(results, reference)

Rank `(Composition, stored_score)` rows by cosine similarity of element-count
vectors to `reference`, given as a `Composition` or a formula string. Shorthand
for `rank_compositions(results, SimilarityRanking(reference))`. Similarity
measures stoichiometric overlap, not chemical plausibility.
"""
rank_by_similarity(results, reference) = rank_compositions(results, SimilarityRanking(reference))
