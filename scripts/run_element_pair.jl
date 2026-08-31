include(joinpath(@__DIR__,"..","src","mp_element_pair.jl"))
function main(args)
    synthetic=length(args)==5 && last(args)=="--synthetic"
    length(args)==(synthetic ? 5 : 4)||error("usage: run_element_pair.jl SNAPSHOT AUDIT V2_RESULTS NEW_OUTPUT [--synthetic]")
    result=MPElementPair.run_evaluation(args[1:4]...;synthetic)
    println("Element-pair evaluation: $(length(result.metrics)) metric rows; output: $(result.path)")
end
main(ARGS)
