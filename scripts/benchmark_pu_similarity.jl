using Eka, Printf, SHA

# Synthetic-only runtime and memory measurement for the PU similarity comparator.
# It uses generated formulas at the size the frozen protocol implies for one real
# split (4,288 training positives and 8,218 candidates). No snapshot, audit,
# split bundle, MP record, or evaluation label is read, and nothing here produces
# or inspects a recovery result. See docs/mp-pu-evaluation.md.

const NON_OXYGEN = [symbol for symbol in Eka.ELEMENT_SYMBOLS if symbol != "O"]

"""
    synthetic_pool(count; offset=0)

Deterministic distinct oxygen-containing ternary formulas. Element pairs are
enumerated in a fixed order and combined with coprime count triples, so a given
`offset` and `count` always name the same compositions and disjoint ranges stay
disjoint. These are stoichiometric fixtures, not plausible chemistry.
"""
function synthetic_pool(count::Int; offset::Int=0)
    triples = ((1, 1, 3), (1, 2, 4), (2, 3, 5))
    pairs = [(a, b) for a in NON_OXYGEN for b in NON_OXYGEN if a < b]
    total = length(pairs) * length(triples)
    offset + count <= total || error("synthetic pool exhausted: need $(offset + count) of $total")
    return map(offset:(offset + count - 1)) do i
        (a, b) = pairs[div(i, length(triples)) + 1]
        (x, y, z) = triples[mod(i, length(triples)) + 1]
        Composition("$a$x$b$y" * "O$z")
    end
end

function report(label, measurement, pairs)
    @printf("%-34s %9.3f s  %12.1f MiB allocated  %8.1f ns/pair\n", label,
        measurement.time, measurement.bytes / 2^20, measurement.time * 1e9 / pairs)
end

function benchmark_pu_similarity(; training_count::Int=4288, candidate_count::Int=8218, repeats::Int=3)
    training = synthetic_pool(training_count)
    candidates = synthetic_pool(candidate_count; offset=training_count)
    @assert isempty(intersect(Set(training), Set(candidates)))
    pairs = training_count * candidate_count
    println("Julia ", VERSION, " | synthetic PU similarity workload")
    println(training_count, " training compositions x ", candidate_count, " candidates = ", pairs, " pairs per split")
    matrix = pairs * sizeof(Float64) / 2^20
    @printf("A full candidate-by-training Float64 matrix would need %.1f MiB; the streamed maximum never allocates it.\n", matrix)

    # Warm up compilation outside the reported measurements.
    Eka.pu_max_similarity(candidates[1:8], training[1:8])
    pu_rank(training[1:8], candidates[1:8]; method="similarity")

    scores = @timed Eka.pu_max_similarity(candidates, training)
    report("Streamed maximum similarity", scores, pairs)
    @assert length(scores.value) == candidate_count && all(s -> 0.0 <= s <= 1.0, scores.value)

    ranked = [@timed(pu_rank(training, candidates; method="similarity")) for _ in 1:repeats]
    sort!(ranked; by=r -> r.time)
    report("pu_rank similarity (fastest)", first(ranked), pairs)
    report("pu_rank similarity (middle)", ranked[cld(repeats, 2)], pairs)
    for method in ("popularity", "random")
        pu_rank(training[1:8], candidates[1:8]; method)
        report("pu_rank $method (reference)", @timed(pu_rank(training, candidates; method)), pairs)
    end
    order = [formula(r.composition) for r in first(ranked).value]
    @assert length(order) == candidate_count
    println("Ranking digest (deterministic): ", bytes2hex(sha256(join(order, '\n')))[1:16])
    println("pu_rank totals include SHA-256 tie/random keys and the final sort, not only the pairwise loop.")
    println("Allocated bytes are cumulative allocation, not peak resident memory; the loop reuses one candidate vector at a time.")
    println("Timings depend on this machine and Julia version. Record them alongside a run; do not treat them as a target.")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    benchmark_pu_similarity()
end
