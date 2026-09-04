"""Synthetic-stage element-pair factor model; an internal research module, outside the frozen CLI."""
module ElementPairModel
using ...EkaCompositions
using SHA

const MODEL_ID="eka-element-pair-symnmf-v1"
const ELEMENTS=sort!([e for e in EkaCompositions.ELEMENT_SYMBOLS if e!="O"])
const INDEX=Dict(e=>i for (i,e) in enumerate(ELEMENTS))
check(ok,message)=ok || throw(ArgumentError(message))

Base.@kwdef struct Settings
    rank::Int=4
    missing_weight::Float64=0.01
    regularization::Float64=0.01
    seed::Int=20260902
    max_iterations::Int=2000
    tolerance::Float64=1e-4
end

function validate(settings)
    check(1<=settings.rank<=length(ELEMENTS),"rank must be between 1 and 117")
    check(isfinite(settings.missing_weight) && 0<settings.missing_weight<=1,"missing weight must be in (0,1]")
    check(isfinite(settings.regularization) && settings.regularization>0,"regularization must be positive and finite")
    check(settings.seed>=0 && settings.max_iterations>=1,"invalid seed or iteration limit")
    check(isfinite(settings.tolerance) && 0<settings.tolerance<1,"tolerance must be in (0,1)")
end

function pair(c::Composition)
    check(length(c)==3 && "O" in species(c),"model requires oxygen-containing ternaries")
    a,b=filter(e->e!="O",species(c))
    return INDEX[a],INDEX[b]
end

function training_data(training)
    cs=sort!(EkaCompositions.pu_compositions(training,"training");by=formula)
    n=length(ELEMENTS);counts=zeros(Int,n,n);active=falses(n)
    for c in cs
        a,b=pair(c);counts[a,b]+=1;counts[b,a]+=1;active[a]=active[b]=true
    end
    target=log1p.(counts)./log1p(length(cs))
    return (;compositions=cs,counts,target,active)
end

function initialize(active,settings)
    f=zeros(length(ELEMENTS),settings.rank)
    for i in eachindex(active), k in 1:settings.rank
        if active[i]
            bytes=bytes2hex(sha256("$MODEL_ID\n$(settings.seed)\n$(ELEMENTS[i])\n$k"))
            u=parse(UInt64,bytes[1:13];base=16)/4503599627370496.0
            f[i,k]=(0.5+u)/sqrt(10.0*settings.rank)
        end
    end
    return f
end

# Unordered pair objective; diagonal entries have no role. Explicit loops keep
# accumulation deterministic and avoid a new dependency or threaded BLAS state.
function objective_gradient(f,target,weights,lambda)
    n,r=size(f);gradient=lambda.*f
    loss=0.0
    for value in f;loss+=0.5*lambda*value*value;end
    for a in 1:n-1, b in a+1:n
        predicted=0.0
        for k in 1:r;predicted+=f[a,k]*f[b,k];end
        residual=predicted-target[a,b];weighted=weights[a,b]*residual
        loss+=0.5*weighted*residual
        for k in 1:r
            gradient[a,k]+=weighted*f[b,k]
            gradient[b,k]+=weighted*f[a,k]
        end
    end
    return loss,gradient
end

residual(f,g)=sqrt(sum((f.-max.(0.0,f.-g)).^2))

struct Model
    settings::Settings
    factors::Matrix{Float64}
    active::BitVector
    counts::Matrix{Int}
    training::Vector{String}
    trace::Vector{NamedTuple{(:iteration,:objective,:projected_gradient),Tuple{Int,Float64,Float64}}}
    termination::String
end

function fit(training;settings=Settings())
    validate(settings)
    data=training_data(training);f=initialize(data.active,settings)
    weights=ifelse.(data.counts.>0,1.0,settings.missing_weight)
    loss,g=objective_gradient(f,data.target,weights,settings.regularization)
    initial=residual(f,g);threshold=settings.tolerance*max(1.0,initial)
    trace=[(iteration=0,objective=loss,projected_gradient=initial)]
    step=1.0;termination="iteration_limit"
    for iteration in 1:settings.max_iterations
        if last(trace).projected_gradient<=threshold
            termination="projected_gradient";break
        end
        accepted=false;nextf=f;nextloss=loss;nextg=g
        for attempt in 1:60
            nextf=max.(0.0,f.-step.*g)
            delta=nextf.-f
            nextloss,nextg=objective_gradient(nextf,data.target,weights,settings.regularization)
            if isfinite(nextloss) && all(isfinite,nextg) && nextloss<=loss+1e-4*sum(g.*delta)
                accepted=true;break
            end
            step*=0.5
        end
        check(accepted,"line search failed; no valid model produced")
        f,loss,g=nextf,nextloss,nextg
        push!(trace,(;iteration,objective=loss,projected_gradient=residual(f,g)))
        step=min(1.0,2*step)
    end
    last(trace).projected_gradient<=threshold && (termination="projected_gradient")
    check(all(isfinite,f) && all(>=(0),f),"invalid fitted factors")
    return Model(settings,f,data.active,data.counts,formula.(data.compositions),trace,termination)
end

function score(model::Model,c::Composition)
    a,b=pair(c)
    known=model.active[a] && model.active[b]
    value=0.0
    if known
        for k in axes(model.factors,2);value+=model.factors[a,k]*model.factors[b,k];end
    end
    check(isfinite(value) && value>=0,"invalid candidate score")
    return (score=value,coverage=known ? "known_elements" : "unseen_element_zero",observed_training_pair=model.counts[a,b]>0)
end
score(model::Model,f::AbstractString)=score(model,Composition(f))

function rank_candidates(model,candidates;tie_seed=20260901)
    check(tie_seed isa Integer && !(tie_seed isa Bool) && tie_seed>=0,"invalid tie seed")
    cs=EkaCompositions.pu_compositions(candidates,"candidates")
    check(isempty(intersect(Set(model.training),Set(formula.(cs)))),"training/candidate composition overlap")
    rows=[(composition=c,score(model,c)...,tie_key=bytes2hex(sha256("eka-pu-tie-v1\n$tie_seed\n$(formula(c))"))) for c in cs]
    return sort!(rows;by=r->(-r.score,r.tie_key,formula(r.composition)))
end
end
