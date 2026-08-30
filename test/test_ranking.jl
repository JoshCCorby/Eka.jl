struct PreferBinary <: AbstractRankingMethod end
Eka.ranking_value(::PreferBinary, c::Composition, ::Real) = length(c) == 2 ? 1.0 : 0.0
struct InvalidRanking <: AbstractRankingMethod end
Eka.ranking_value(::InvalidRanking, ::Composition, ::Real) = NaN

@testset "Pluggable ranking" begin
    a, b = Composition("MgZn"), Composition("Mg2Zn")
    @test similarity(a, a) == 1.0
    @test similarity(a, Composition("Mg2Zn2")) == 1.0
    @test similarity(a, Composition("NaCl")) == 0.0
    @test similarity(a, b) ≈ similarity(b, a)
    @test similarity(a, b) ≈ 3 / sqrt(10)
    @test similarity(a, Composition("MgZnO")) < 1.0
    @test 0 <= similarity(Composition(["Mg" => typemax(Int), "Zn" => 1]), b) <= 1
    @test (@inferred ranking_value(SimilarityRanking(a), b, 0.3)) ≈ 3 / sqrt(10)

    rows = [(Composition("Mg2Zn"), 0.9), (Composition("MgZn"), 0.2), (Composition("NaClO"), 1.2)]
    snapshot = copy(rows)
    @test first(rank_by_score(rows))[2] == 1.2
    ranked = rank_by_similarity(rows, "MgZn")
    @test first(ranked) == (Composition("MgZn"), 0.2)
    @test Set(ranked) == Set(rows)
    @test rows == snapshot
    @test rank_compositions(rows, PreferBinary())[1] == rows[1]
    @test_throws ArgumentError rank_compositions(rows, InvalidRanking())
    @test_throws ArgumentError rank_by_score([(a, Inf)])
    @test_throws ArgumentError rank_by_score([(a, true)])
    @test isempty(rank_by_similarity(Tuple{Composition,Float64}[], a))
    tied = [(Composition("NaCl"), 0.3), (Composition("KCl"), 0.3)]
    @test formula(first(first(rank_by_similarity(tied, "MgZn")))) == "Cl1K1"
    @test rank_by_similarity(tied, "MgZn") == rank_by_similarity(reverse(tied), "MgZn")
    filtered = query_compositions(FIXTURE; elements=["Mg", "Zn"], nary=[2], threshold=0.3, ranking=SimilarityRanking("MgZn"))
    @test first(filtered)[1] == a
    @test all(r -> r[2] >= 0.3, filtered)
    @test Set(filtered) == Set(query_compositions(FIXTURE; elements=["Mg", "Zn"], nary=[2], threshold=0.3))
    @test length(query_compositions(FIXTURE; threshold=0.3)) == length(query_compositions(FIXTURE; threshold=0.3, inclusive=false)) + 2
end
