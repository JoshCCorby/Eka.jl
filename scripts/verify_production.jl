using Eka, SQLite, DBInterface, SHA, Test

# Independent reference for the supplied original script's strict threshold and
# element-set semantics. Stream rows instead of retaining the whole source table.
function reference_query(path; elements, nary, threshold)
    output = Tuple{String,Float64}[]
    Eka.with_database(path) do db
        for (n, table) in ((2, "data2"), (3, "data3"), (4, "data4ionic"), (5, "data5ionic"))
            n in nary || continue
            statement = SQLite.Stmt(db, "SELECT * FROM $table WHERE score > ?")
            try
                for row in DBInterface.execute(statement, (threshold,))
                    symbols = Set(String(getproperty(row, Symbol("ele$i"))) for i in 1:n)
                    if all(in(symbols), elements)
                        push!(output, (String(row.composition), Float64(row.score)))
                    end
                end
            finally
                DBInterface.close!(statement)
            end
        end
    end
    return output
end

function verify_production(path; full_audit=false)
    checksum = open(sha256, path)
    println("SHA-256: ", bytes2hex(checksum))
    println("Schema: ", database_info(path))
    if full_audit
        println("Auditing every row (read-only)…")
        flush(stdout)
        audit = @timed validate_database(path; strict=false)
        println("Full audit: ", audit.value, " in ", round(audit.time; digits=3), " seconds")
    end
    @testset "Original-script query semantics (canonical formulas)" begin
        for (elements, nary, threshold) in ((["Al", "Si", "O"], [4], 0.01),
                (["N"], [4], 0.01), (["Mg", "Zn"], [2, 3], 0.01),
                (["Mg", "Zn"], [2], 0.01), (["Mg", "Zn"], [2, 3], 0.3), (["N"], [5], 0.3))
            raw = reference_query(path; elements, nary, threshold)
            reference = Tuple{Composition,Float64}[]
            unsupported = String[]
            for (formula, score) in raw
                try
                    push!(reference, (Composition(formula), score))
                catch error
                    error isa ArgumentError || rethrow()
                    push!(unsupported, formula)
                end
            end
            if isempty(unsupported)
                actual = query_compositions(path; elements, nary, threshold, inclusive=false)
                sort!(reference; by=r -> (-r[2], formula(r[1])))
                @test actual == reference
                @test actual == query_compositions(path; elements=reverse(elements), nary, threshold, inclusive=false)
                println(join(elements, "-"), " n=", nary, " threshold>", threshold, ": ", length(actual), " results match")
            else
                @test_throws ArgumentError query_compositions(path; elements, nary, threshold, inclusive=false)
                println(join(elements, "-"), " n=", nary, " threshold>", threshold, ": strict rejection verified; ",
                    length(unsupported), " unsupported formulas among ", length(raw), " original results (e.g. ", first(unsupported), ")")
            end
        end
        @test open(sha256, path) == checksum
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("usage: julia --project=. scripts/verify_production.jl DATABASE [--full-audit]")
    verify_production(first(ARGS); full_audit="--full-audit" in ARGS)
end
