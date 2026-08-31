function cli_settings()
    settings = ArgParseSettings(
        prog = "eka",
        description = "Explore precomputed chemical-composition scores in SQLite.",
        epilog = "Additional commands: eka import --help; eka validate --help; eka benchmark --help; eka audit-mp --help",
        add_help = false,
        exit_after_help = false,
        exc_handler = (_, error) -> throw(error),
    )
    @add_arg_table! settings begin
        "--help", "-h"
            help = "Show this help message and exit"
            action = :store_true
        "--database", "-d"
            help = "Existing SQLite database (required)"
            arg_type = String
            required = true
        "--elements", "-e"
            help = "Require all listed element symbols; an empty list is unrestricted"
            arg_type = String
            nargs = '*'
        "--nary", "-n"
            help = "Allowed numbers of distinct elements; an empty list matches nothing"
            arg_type = Int
            nargs = '*'
            default = [3]
        "--threshold"
            help = "Inclusive minimum stored score"
            arg_type = Float64
            default = 0.01
        "--strict-threshold"
            help = "Use score > threshold, matching the original script (default: >=)"
            action = :store_true
        "--rank"
            help = "Ranking method: score or similarity (threshold still filters stored scores)"
            arg_type = String
            default = "score"
            range_tester = x -> x in ("score", "similarity")
        "--reference"
            help = "Reference formula required for --rank similarity"
            arg_type = String
    end
    return settings
end

"""
    main(args=ARGS; out=stdout, err=stderr) -> Int

Run the CLI, returning 0 on success/help or 2 for invalid input/database errors.
The library does not exit the calling process; only `bin/eka` calls `exit`.
"""
function main(args=ARGS; out::IO=stdout, err::IO=stderr)
    settings = cli_settings()
    try
        !isempty(args) && first(args) == "audit-mp" && return mp_audit_main(args[2:end]; out)
        !isempty(args) && first(args) == "benchmark" && return benchmark_main(args[2:end]; out)
        !isempty(args) && first(args) == "import" && return import_main(args[2:end]; out)
        !isempty(args) && first(args) == "validate" && return validate_main(args[2:end]; out)
        # Handle help through the supplied stream, including when -d is absent.
        if any(arg -> arg in ("-h", "--help"), args)
            ArgParse.show_help(out, settings; exit_when_done=false)
            return 0
        end
        parsed = parse_args(args, settings)
        method = if parsed["rank"] == "similarity"
            parsed["reference"] === nothing && throw(ArgumentError("--rank similarity requires --reference FORMULA"))
            SimilarityRanking(parsed["reference"])
        else
            parsed["reference"] === nothing || throw(ArgumentError("--reference requires --rank similarity"))
            ScoreRanking()
        end
        results = query_compositions(parsed["database"];
            elements=parsed["elements"], nary=parsed["nary"], threshold=parsed["threshold"],
            inclusive=!parsed["strict-threshold"], ranking=method)
        info = database_info(parsed["database"])
        if info.schema == :legacy
            available = [t.nary for t in info.tables]
            absent = setdiff(parsed["nary"], available)
            isempty(absent) || println(err, "eka: note: no source tables for nary ", join(absent, ", "))
            ionic = [t.nary for t in info.tables if t.ionic_only && t.nary in parsed["nary"]]
            isempty(ionic) || println(err, "eka: note: nary ", join(ionic, ", "), " covers ionic compositions only in this database")
        end
        println(out, method isa SimilarityRanking ? "# Composition, Score, Similarity" : "# Composition, Score")
        for (composition, score) in results
            if method isa SimilarityRanking
                @printf(out, "%s   %.5f   %.5f\n", formula(composition), score, ranking_value(method, composition, score))
            else
                @printf(out, "%s   %.5f\n", formula(composition), score)
            end
        end
        return 0
    catch error
        if error isa Union{ArgumentError,ArgParse.ArgParseError,SQLite.SQLiteException,SystemError,Base.IOError}
            println(err, "eka: error: ", sprint(showerror, error))
            return 2
        end
        rethrow()
    end
end

function import_main(args; out::IO)
    settings = ArgParseSettings(prog="eka import", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Build a NEW query database from already-scored TSV records.")
    @add_arg_table! settings begin
        "--help", "-h"
            help = "Show import help"
            action = :store_true
        "--input"
            help = "TSV source with composition and score columns"
            arg_type = String
            required = true
        "--database", "-d"
            help = "New output database; existing files are never overwritten"
            arg_type = String
            required = true
        "--source"
            help = "Source/version description recorded in import metadata"
            arg_type = String
            required = true
        "--duplicates"
            help = "Canonical duplicates: error or keep (no score aggregation)"
            arg_type = String
            default = "error"
            range_tester = x -> x in ("error", "keep")
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    parsed = parse_args(args, settings)
    result = import_tsv(parsed["input"], parsed["database"]; source=parsed["source"], duplicates=Symbol(parsed["duplicates"]))
    println(out, "Imported ", result.rows, " records into ", result.path)
    println(out, "Canonical records SHA-256: ", result.records_sha256)
    return 0
end

function validate_main(args; out::IO)
    settings = ArgParseSettings(prog="eka validate", add_help=false,
        exc_handler=(_, error) -> throw(error), description="Audit all SQLite records without modifying the database.")
    @add_arg_table! settings begin
        "--help", "-h"
            help = "Show validation help"
            action = :store_true
        "--database", "-d"
            help = "Existing database to audit"
            arg_type = String
            required = true
        "--report"
            help = "Scan all rows and report unsupported/invalid records (exit 2 if any)"
            action = :store_true
    end
    if any(a -> a in ("-h", "--help"), args)
        ArgParse.show_help(out, settings; exit_when_done=false)
        return 0
    end
    parsed = parse_args(args, settings)
    result = validate_database(parsed["database"]; strict=!parsed["report"])
    println(out, "Validated ", result.valid_rows, " records; ", result.invalid_rows, " invalid or unsupported")
    for name in sort!(collect(keys(result.tables)))
        println(out, name, ": ", result.tables[name], " rows; ", result.invalid_by_table[name], " invalid or unsupported")
    end
    for category in sort!(collect(keys(result.categories)))
        println(out, category, ": ", result.categories[category], " (example: ", result.category_examples[category], ")")
    end
    for issue in result.issues
        println(out, issue.table, " row ", issue.row, ": ", issue.error)
    end
    return result.invalid_rows == 0 ? 0 : 2
end
