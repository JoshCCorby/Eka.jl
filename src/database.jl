const SQLITE_HEADER = collect(codeunits("SQLite format 3\0"))
const LEGACY_TABLES = Dict("data2" => 2, "data3" => 3, "data4ionic" => 4, "data5ionic" => 5)

struct CompositionTable
    name::String
    nary::Union{Nothing,Int}
    ionic_only::Bool
end

function validate_database_file(path::AbstractString)
    isfile(path) || throw(ArgumentError("database file does not exist or is not a regular file: $path"))
    header = open(path, "r") do io
        read(io, 16)
    end
    header == SQLITE_HEADER || throw(ArgumentError("not a valid SQLite database (invalid file header): $path"))
    return nothing
end

# URI mode=ro enforces read-only access at SQLite open time, including missing-file races.
function readonly_uri(path::AbstractString)
    absolute = abspath(path)
    Sys.iswindows() && (absolute = "/" * replace(absolute, '\\' => '/'))
    return "file:" * replace(absolute, "%" => "%25", "?" => "%3F", "#" => "%23") * "?mode=ro"
end

function with_database(f, path::AbstractString)
    validate_database_file(path)
    db = nothing
    try
        db = SQLite.DB(readonly_uri(path))
        return f(db)
    catch error
        error isa SQLite.SQLiteException || rethrow()
        throw(ArgumentError("cannot query SQLite database $(repr(path)): $(sprint(showerror, error))"))
    finally
        db === nothing || DBInterface.close!(db)
    end
end

# Identifiers come only from inspected metadata and are quoted, never bound as values.
quote_identifier(name::AbstractString) = "\"" * replace(name, "\"" => "\"\"") * "\""

function composition_tables(db::SQLite.DB)
    names = String[]
    for row in DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type = ? ORDER BY name", ("table",))
        name = String(row.name)
        startswith(name, "sqlite_") || push!(names, name)
    end
    tables = CompositionTable[]
    for name in names
        columns = Set{String}()
        for row in DBInterface.execute(db, "PRAGMA table_info($(quote_identifier(name)))")
            push!(columns, lowercase(String(row.name)))
        end
        if "composition" in columns && "score" in columns
            arity = get(LEGACY_TABLES, lowercase(name), nothing)
            if arity !== nothing
                required = vcat(["ele$i" for i in 1:arity], ["int$i" for i in 1:arity])
                all(in(columns), required) || throw(ArgumentError("legacy table $name requires ele1…ele$arity and int1…int$arity columns"))
            end
            push!(tables, CompositionTable(name, arity, arity in (4, 5)))
        end
    end
    isempty(tables) && throw(ArgumentError("database needs a table with composition and score columns"))
    if length(tables) > 1 && any(t -> t.nary === nothing, tables)
        throw(ArgumentError("ambiguous database schema: multiple tables have composition and score columns outside the recognized legacy layout"))
    end
    return tables
end

"""Inspect supported tables and coverage without loading composition records."""
function database_info(path::AbstractString)
    with_database(path) do db
        tables = composition_tables(db)
        return (schema=all(t -> t.nary !== nothing, tables) ? :legacy : :standard,
            tables=[(name=t.name, nary=t.nary, ionic_only=t.ionic_only) for t in tables])
    end
end

function parse_scored_row(raw_composition, raw_score)::ScoredComposition
    raw_composition isa AbstractString || throw(ArgumentError("database composition must be non-NULL text"))
    raw_score isa Real && !(raw_score isa Bool) && isfinite(raw_score) && isfinite(Float64(raw_score)) ||
        throw(ArgumentError("database score for $(repr(raw_composition)) must be a finite number"))
    composition = try
        Composition(raw_composition)
    catch error
        error isa ArgumentError || rethrow()
        throw(ArgumentError("invalid database composition $(repr(raw_composition)): $(error.msg)"))
    end
    return (composition, Float64(raw_score))
end

function parse_table_row(row, table::CompositionTable)
    result = parse_scored_row(row.composition, row.score)
    if table.nary !== nothing
        entries = Pair{String,Int}[]
        for i in 1:table.nary
            symbol = validate_element(getproperty(row, Symbol("ele$i")))
            amount = getproperty(row, Symbol("int$i"))
            amount isa Integer && 0 < amount <= typemax(Int) ||
                throw(ArgumentError("invalid stoichiometry in $(table.name) for $(repr(row.composition))"))
            push!(entries, symbol => Int(amount))
        end
        length(result[1]) == table.nary && Composition(entries) == result[1] ||
            throw(ArgumentError("formula and element/stoichiometry columns disagree in $(table.name): $(repr(row.composition))"))
    end
    return result
end

selected_tables(tables, nary) = filter(t -> t.nary === nothing || nary === nothing || t.nary in nary, tables)

function select_sql(table::CompositionTable, filters::Union{Nothing,QueryFilters}; inclusive=true)
    columns = ["composition AS composition", "score AS score"]
    if table.nary !== nothing
        append!(columns, ["ele$i AS ele$i" for i in 1:table.nary])
        append!(columns, ["int$i AS int$i" for i in 1:table.nary])
    end
    sql = "SELECT $(join(columns, ", ")) FROM $(quote_identifier(table.name))"
    parameters = Any[]
    if filters !== nothing
        comparison = inclusive ? ">=" : ">"
        sql *= " WHERE (score $comparison ? OR score IS NULL)"
        push!(parameters, filters.threshold)
        if table.nary !== nothing
            symbols = join(["ele$i" for i in 1:table.nary], ", ")
            for element in filters.elements
                sql *= " AND ? IN ($symbols)"
                push!(parameters, element)
            end
        end
    end
    return sql, parameters
end

"""
    query_compositions(path; elements=nothing, nary=nothing, threshold=0.01,
                       inclusive=true, ranking=ScoreRanking())

Query a standard composition/score table or the legacy data2/data3/data4ionic/
data5ionic layout. Require all requested elements. `nary=nothing` is unrestricted;
an empty nary list matches nothing. Legacy arities 4 and 5 cover ionic records only.
Thresholds apply to the stored score, including with similarity ranking. Set
`inclusive=false` for the original script's strict `score > threshold` semantics.
Return `(Composition, Float64)` tuples, retaining source scores and duplicate rows.
Only selected candidate rows are validated; use `validate_database` for a full audit.
"""
function query_compositions(path::AbstractString; elements=nothing, nary=nothing,
        threshold=0.01, inclusive::Bool=true, ranking::AbstractRankingMethod=ScoreRanking())
    filters = query_filters(elements, nary, threshold)
    results = ScoredComposition[]
    with_database(path) do db
        tables = selected_tables(composition_tables(db), filters.nary)
        for table in tables
            sql, parameters = select_sql(table, filters; inclusive)
            statement = SQLite.Stmt(db, sql)
            try
                for row in DBInterface.execute(statement, parameters)
                    result = parse_table_row(row, table)
                    matches_filters(result[1], filters) && push!(results, result)
                end
            finally
                DBInterface.close!(statement)
            end
        end
    end
    return rank!(results, ranking)
end

function validation_category(message::AbstractString)
    occursin("invalid element symbol", message) && return :unsupported_symbol
    occursin("invalid simple formula", message) && return :unsupported_syntax
    occursin("disagree", message) && return :inconsistent_columns
    occursin("finite number", message) && return :invalid_score
    occursin("stoichiometry", message) && return :invalid_stoichiometry
    return :invalid_record
end

"""
    validate_database(path; strict=true, max_issues=20)

Read-only SQLite quick_check plus a streaming audit of every record, including
legacy redundant element/count fields. With `strict=false`, continue after invalid
rows and return counts, at most `max_issues` row errors, and bounded per-category
summaries/examples. Unsupported symbols are reported, never silently converted.
No filtering, scoring, or repair is performed.
"""
function validate_database(path::AbstractString; strict::Bool=true, max_issues::Int=20)
    max_issues >= 0 || throw(ArgumentError("max_issues must be nonnegative"))
    with_database(path) do db
        for row in DBInterface.execute(db, "PRAGMA quick_check")
            row[1] == "ok" || throw(ArgumentError("SQLite integrity check failed: $(row[1])"))
        end
        counts = Dict{String,Int}()
        invalid_counts = Dict{String,Int}()
        categories = Dict{Symbol,Int}()
        category_examples = Dict{Symbol,String}()
        issues = NamedTuple{(:table, :row, :error),Tuple{String,Int,String}}[]
        for table in composition_tables(db)
            count = 0
            invalid = 0
            sql, _ = select_sql(table, nothing)
            statement = SQLite.Stmt(db, sql)
            try
                for row in DBInterface.execute(statement)
                    count += 1
                    try
                        parse_table_row(row, table)
                    catch error
                        error isa ArgumentError || rethrow()
                        strict && throw(ArgumentError("$(table.name), scan row $count: $(error.msg)"))
                        invalid += 1
                        category = validation_category(error.msg)
                        categories[category] = get(categories, category, 0) + 1
                        get!(category_examples, category, "$(table.name), scan row $count: $(error.msg)")
                        length(issues) < max_issues && push!(issues, (table=table.name, row=count, error=error.msg))
                    end
                end
            finally
                DBInterface.close!(statement)
            end
            counts[table.name] = count
            invalid_counts[table.name] = invalid
        end
        total = sum(values(counts))
        invalid = sum(values(invalid_counts))
        return (rows=total, valid_rows=total - invalid, invalid_rows=invalid,
            tables=counts, invalid_by_table=invalid_counts, issues=issues,
            categories=categories, category_examples=category_examples)
    end
end
