using Eka, Printf

function report(label, measurement)
    @printf("%-26s %10.3f ms  %10d bytes  %d results\n",
        label, measurement.time * 1000, measurement.bytes, length(measurement.value))
end

function benchmark_query(path; repeats=20)
    println("Julia ", VERSION, " | database: ", abspath(path))
    println("Includes opening, schema inspection, SQL query, parsing, filtering, and sorting.")
    # Compilation/loading of `using Eka` is outside these measurements.
    cold = @timed query_compositions(path; elements=["Al", "Si", "O"], nary=[4])
    report("First query in process", cold)
    samples = [@timed(query_compositions(path; elements=["Al", "Si", "O"], nary=[4])) for _ in 1:repeats]
    sort!(samples; by=s -> s.time)
    report("Warm query (minimum)", first(samples))
    report("Warm query (middle sample)", samples[cld(repeats, 2)])
    println("Warm results assume a running Julia process and may benefit from OS file caching.")
    println("For full fresh-process CLI latency, time bin/eka separately.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    path = isempty(ARGS) ? joinpath(@__DIR__, "..", "test", "fixtures", "tiny_test.db") : only(ARGS)
    benchmark_query(path)
end
