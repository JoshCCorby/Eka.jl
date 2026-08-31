# Research entry point; the v1 benchmark-pu CLI is intentionally unchanged.
include(joinpath(@__DIR__, "..", "src", "mp_label_sensitivity.jl"))
using .MPLabelSensitivity

function main(args)
    synthetic = length(args) == 5 && last(args) == "--synthetic"
    length(args) == (synthetic ? 5 : 4) || error("usage: run_label_sensitivity.jl SNAPSHOT AUDIT PILOT NEW_OUTPUT [--synthetic]")
    result = MPLabelSensitivity.run_sensitivity(args[1], args[2], args[3], args[4]; synthetic)
    println("Label sensitivity: $(length(result.metrics)) metric rows; output: $(result.path)")
end

main(ARGS)
