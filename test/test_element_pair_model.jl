const ElementPairModel = EkaCompositions.Research.ElementPairModel
const EP=ElementPairModel

@testset "Pair-factor objective and gradient" begin
    f=[0.5 0.2;0.7 0.3;0.1 0.8]
    y=[0.0 0.6 0.0;0.6 0.0 0.4;0.0 0.4 0.0]
    w=[0.0 1.0 0.01;1.0 0.0 1.0;0.01 1.0 0.0]
    loss,g=EP.objective_gradient(f,y,w,0.03)
    expected=0.5*((0.41-0.6)^2+0.01*0.21^2+(0.31-0.4)^2)+0.015*sum(f.^2)
    @test loss≈expected atol=1e-14
    for i in eachindex(f)
        plus=copy(f);minus=copy(f);plus[i]+=1e-6;minus[i]-=1e-6
        numerical=(first(EP.objective_gradient(plus,y,w,0.03))-first(EP.objective_gradient(minus,y,w,0.03)))/2e-6
        @test g[i]≈numerical atol=1e-9
    end
    # An analytical stationary point for a single observed pair and rank one.
    exact=fill(sqrt(0.49),2,1)
    _,gradient=EP.objective_gradient(exact,[0.0 0.5;0.5 0.0],[0.0 1.0;1.0 0.0],0.01)
    @test maximum(abs,gradient)<1e-14
end

@testset "Training-only pair fitting, coverage and ordering" begin
    training=["LiNaO","LiKO","NaKO","MgCaO","MgSrO","CaSrO","Li2NaO"]
    settings=EP.Settings(rank=2,max_iterations=500)
    a=EP.fit(training;settings);b=EP.fit(reverse(training);settings)
    @test a.factors==b.factors && a.counts==b.counts && a.trace==b.trace
    @test all(diff([r.objective for r in a.trace]).<=0)
    @test last(a.trace).objective<first(a.trace).objective
    @test all(isfinite,a.factors) && all(a.factors.>=0)
    @test a.termination in ("projected_gradient","iteration_limit")
    @test EP.fit(training;settings=EP.Settings(max_iterations=1,tolerance=1e-12)).termination=="iteration_limit"
    candidates=["LiNaO2","Li2NaO2","LiCaO2","FeZnO2"]
    original=copy(a.factors);ranked=EP.rank_candidates(a,candidates)
    @test length(ranked)==length(candidates)
    @test ranked==EP.rank_candidates(a,reverse(candidates))
    @test EP.score(a,"LiNaO2").score==EP.score(a,"Li2NaO2").score
    @test EP.score(a,"LiCaO2").coverage=="known_elements"
    @test !EP.score(a,"LiCaO2").observed_training_pair
    @test EP.score(a,"FeZnO2")== (score=0.0,coverage="unseen_element_zero",observed_training_pair=false)
    extra=EP.rank_candidates(a,vcat(candidates,["RbCsO2"]))
    @test filter(r->formula(r.composition)!=formula(Composition("RbCsO2")),extra)==ranked
    # Evaluation labels are consumed only by pu_metrics after fitting/ranking.
    order=[r.composition for r in ranked]
    x=pu_metrics(order,[order[1]];budgets=[1]);y=pu_metrics(order,[order[end]];budgets=[1])
    @test only(x).hits==1 && only(y).hits==0
    @test a.factors==original && EP.rank_candidates(a,candidates)==ranked
    @test a.training==sort(formula.(Composition.(training)))
    @test a.counts[EP.INDEX["Li"],EP.INDEX["Na"]]==2
    @test_throws ArgumentError EP.fit(vcat(training,["O2Li2Na2"]))
    @test_throws ArgumentError EP.fit(["LiNa"])
    @test_throws ArgumentError EP.fit(String[])
    @test_throws ArgumentError EP.rank_candidates(a,["LiNaO"])
    @test_throws ArgumentError EP.rank_candidates(a,["LiNaO2","Li2Na2O4"])
    @test_throws ArgumentError EP.score(a,"NaCl")
    for invalid in (EP.Settings(rank=0),EP.Settings(missing_weight=0),EP.Settings(missing_weight=NaN),EP.Settings(regularization=-1),EP.Settings(seed=-1),EP.Settings(max_iterations=0),EP.Settings(tolerance=Inf))
        @test_throws ArgumentError EP.fit(training;settings=invalid)
    end
end
