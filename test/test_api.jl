# The public API contract from docs/api-stability.md, made executable. Adding a
# name to `export` without classifying it here fails the partition test.
const API_STABLE = [
    :AbstractRankingMethod, :Composition, :ScoreRanking, :SimilarityRanking,
    :database_info, :formula, :import_compositions, :import_tsv,
    :query_compositions, :rank_by_score, :rank_by_similarity, :rank_compositions,
    :ranking_value, :similarity, :species, :validate_database,
]
# Stable command-line behaviour; Julia signatures may change within 0.1.x.
const API_CLI = [
    :audit_mp_snapshot, :benchmark_pu, :benchmark_rankings, :benchmark_tsv,
    :main, :split_mp_recovery,
]
const API_EXPERIMENTAL = [
    :load_mp_recovery, :mp_recovery_splits, :pu_metrics, :pu_rank,
    :write_synthetic_mp_snapshot,
]

# Docs.meta is internal and has moved between Julia versions. Probe it, and skip
# the documentation assertion rather than failing spuriously if it moves again.
# Docs.doc(::Docs.Binding) is not a usable alternative: it does not exist on 1.12.
function documented_names()
    try
        return Set(binding.var for binding in keys(Docs.meta(EkaCompositions)))
    catch err
        err isa Union{MethodError,UndefVarError} || rethrow()
        return nothing
    end
end

@testset "public API surface" begin
    exported = filter(n -> n != :EkaCompositions, names(EkaCompositions))
    classified = [API_STABLE; API_CLI; API_EXPERIMENTAL]

    @testset "every export is classified exactly once" begin
        @test sort(classified) == sort(exported)
        @test length(unique(classified)) == length(classified)
        for (a, b) in ((API_STABLE, API_CLI), (API_STABLE, API_EXPERIMENTAL), (API_CLI, API_EXPERIMENTAL))
            @test isempty(intersect(a, b))
        end
    end

    @testset "classified names resolve" begin
        for name in classified
            @test isdefined(EkaCompositions, name)
        end
    end

    @testset "stable names are documented" begin
        documented = documented_names()
        if documented === nothing
            @info "Docs.meta unavailable on this Julia; skipping docstring assertions"
        else
            for name in API_STABLE
                @test name in documented
            end
            # The whole exported surface is documented today; keep it that way.
            @test isempty(setdiff(exported, documented))
        end
    end

    @testset "research modules stay internal" begin
        research = EkaCompositions.Research
        for name in (:MPLabelSensitivity, :MPSystemHoldout, :ElementPairModel, :MPElementPair)
            submodule = getproperty(research, name)
            # `names` on a module with no exports returns just the module itself.
            @test names(submodule) == [name]
        end
        @test !(:Research in exported)
    end
end
