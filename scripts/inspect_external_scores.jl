#!/usr/bin/env julia

"""Read-only coverage inspection for an external composition-score database."""
module InspectExternalScores

using ArgParse
using DBInterface
using Eka
using Printf
using SHA

const LABELS = ("positive", "unlabelled", "unresolved")

function read_audit(path::AbstractString)
    lines = readlines(path)
    isempty(lines) && throw(ArgumentError("audit file is empty"))
    header = split(first(lines), '\t'; keepempty=true)
    length(header) >= 3 && header[1:3] == ["composition", "chemical_system", "label"] ||
        throw(ArgumentError("unexpected audit header"))
    groups = Dict{String,String}()
    for (offset, line) in enumerate(lines[2:end])
        number = offset + 1
        row = split(line, '\t'; keepempty=true)
        length(row) >= 3 || throw(ArgumentError("malformed audit row $number"))
        composition = formula(Composition(row[1]))
        row[3] in LABELS || throw(ArgumentError("unexpected label on audit row $number"))
        haskey(groups, composition) &&
            throw(ArgumentError("duplicate canonical audited composition: $composition"))
        groups[composition] = row[3]
    end
    return groups
end

function read_scores(path::AbstractString; element="O", table="data3")
    Eka.validate_element(element)
    scores = Dict{String,Vector{Float64}}()
    rows = 0
    in_scope = 0
    duplicates = 0
    Eka.with_database(path) do database
        tables = Eka.composition_tables(database)
        selected = findfirst(candidate -> candidate.name == table, tables)
        selected === nothing && throw(ArgumentError("score database has no supported table named $table"))
        descriptor = tables[selected]
        descriptor.nary == 3 || throw(ArgumentError("table $table is not a legacy ternary table"))
        query = "SELECT ele1, ele2, ele3, int1, int2, int3, score FROM " * Eka.quote_identifier(table)
        for row in DBInterface.execute(database, query)
            rows += 1
            elements = String[row.ele1, row.ele2, row.ele3]
            element in elements && length(unique(elements)) == 3 || continue
            in_scope += 1
            counts = Int[row.int1, row.int2, row.int3]
            composition = formula(Composition([elements[index] => counts[index] for index in eachindex(elements)]))
            haskey(scores, composition) && (duplicates += 1)
            score = row.score
            score isa Real && !(score isa Bool) && isfinite(score) ||
                throw(ArgumentError("non-finite score in $table"))
            push!(get!(scores, composition, Float64[]), Float64(score))
        end
    end
    return (scores=scores, rows=rows, in_scope=in_scope, duplicates=duplicates)
end

function inspect(scores_path::AbstractString, audit_path::AbstractString;
        element="O", table="data3", out::IO=stdout)
    groups = read_audit(audit_path)
    result = read_scores(scores_path; element, table)
    covered = Dict(label => 0 for label in LABELS)
    totals = Dict(label => 0 for label in LABELS)
    for (composition, label) in groups
        totals[label] += 1
        haskey(result.scores, composition) && (covered[label] += 1)
    end
    println(out, "score database: ", scores_path)
    println(out, "score database sha256: ", bytes2hex(open(sha256, scores_path)))
    counts = join(("$label=$(totals[label])" for label in LABELS), ", ")
    println(out, "audited composition groups: ", length(groups), " (", counts, ")")
    println(out, "$table rows: $(result.rows); distinct-element $element-containing ternary rows: $(result.in_scope)")
    println(out, "distinct canonical scored compositions in scope: $(length(result.scores)); duplicate canonical score rows: $(result.duplicates)")
    println(out, "coverage of the audited pool, by label:")
    for label in LABELS
        totals[label] == 0 && continue
        percentage = 100 * covered[label] / totals[label]
        @printf(out, "  %s: %d/%d = %.2f%%\n", label, covered[label], totals[label], percentage)
    end
    total_covered = sum(values(covered))
    total = sum(values(totals))
    println(out, "  all labels: $total_covered/$total")
    if !isempty(result.scores)
        overlap = 100 * total_covered / length(result.scores)
        @printf(out, "scored compositions that appear in the audited pool: %.2f%%\n", overlap)
        values_flat = reduce(vcat, values(result.scores))
        println(out, "score range in scope: $(minimum(values_flat)) to $(maximum(values_flat)) (uncalibrated; not a probability)")
    end
    println(out, "Coverage only. No ranking, hit count, or recovery metric is computed here.")
    return (groups=groups, covered=covered, totals=totals, result=result)
end

function settings()
    options = ArgParseSettings(description="Inspect external-score coverage without computing ranking metrics.")
    @add_arg_table! options begin
        "--scores"
            required = true
            help = "External score SQLite database, opened read-only"
        "--audit"
            required = true
            help = "Audited compositions.tsv from eka audit-mp"
        "--table"
            default = "data3"
        "--element"
            default = "O"
    end
    return options
end

function main(args=ARGS; out::IO=stdout, err::IO=stderr)
    try
        parsed = parse_args(args, settings())
        inspect(parsed["scores"], parsed["audit"];
            table=parsed["table"], element=parsed["element"], out)
        return 0
    catch error
        error isa Union{ArgumentError,ArgParse.ArgParseError,SystemError,Base.IOError} || rethrow()
        println(err, "inspect_external_scores: error: ", sprint(showerror, error))
        return 2
    end
end

end


if abspath(PROGRAM_FILE) == @__FILE__
    exit(InspectExternalScores.main())
end
