include(joinpath(@__DIR__,"..","src","mp_system_holdout.jl"))
using .MPSystemHoldout

function main(args)
    flags=Set(filter(x->startswith(x,"--"),args))
    all(x->x in ("--synthetic","--preflight"),flags) || error("unknown option")
    paths=filter(x->!startswith(x,"--"),args)
    length(paths)==4 || error("usage: run_system_holdout.jl SNAPSHOT AUDIT SENSITIVITY_RESULTS NEW_OUTPUT [--synthetic] [--preflight]")
    result=MPSystemHoldout.run_system_holdout(paths...;synthetic="--synthetic" in flags,preflight_only="--preflight" in flags)
    println("System holdout: $(length(result.metrics)) metric rows; output: $(result.path)")
end
main(ARGS)
