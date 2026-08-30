function checked_import_record(record, index)
    record isa Union{Tuple,NamedTuple} && length(record) == 2 ||
        throw(ArgumentError("source row $index must contain exactly (composition, score)"))
    raw, score = record
    original = raw isa Composition ? formula(raw) : raw
    try
        composition, value = parse_scored_row(original, score)
        return composition, value, String(original)
    catch error
        error isa ArgumentError || rethrow()
        throw(ArgumentError("source row $index: $(error.msg)"))
    end
end

function import_records(records, destination::AbstractString; source::AbstractString,
        duplicates::Symbol, extra_metadata=() -> Dict{String,String}())
    duplicates in (:error, :keep) || throw(ArgumentError("duplicates must be :error or :keep"))
    isempty(strip(source)) && throw(ArgumentError("source description must not be empty"))
    target = abspath(destination)
    (ispath(target) || islink(target)) && throw(ArgumentError("refusing to overwrite existing destination: $target"))
    isdir(dirname(target)) || throw(ArgumentError("destination directory does not exist: $(dirname(target))"))

    # Build beside the target. A hard link publishes the closed DB atomically and
    # fails if the destination appears concurrently; mktemp removes the private link.
    return mktemp(dirname(target)) do temporary, io
        close(io)
        db = SQLite.DB(temporary)
        count = 0
        digest = SHA.SHA2_256_CTX()
        records_sha256 = ""
        try
            DBInterface.transaction(db) do
                DBInterface.execute(db, "CREATE TABLE compositions (composition TEXT NOT NULL, score REAL NOT NULL, source_formula TEXT NOT NULL, source_row INTEGER NOT NULL)")
                DBInterface.execute(db, "CREATE TABLE import_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                DBInterface.execute(db, "CREATE INDEX compositions_formula_idx ON compositions(composition)")
                insert = SQLite.Stmt(db, "INSERT INTO compositions VALUES (?, ?, ?, ?)")
                lookup = SQLite.Stmt(db, "SELECT count(*) AS n FROM compositions WHERE composition = ?")
                try
                    for record in records
                        count += 1
                        composition, score, original = checked_import_record(record, count)
                        canonical = formula(composition)
                        if duplicates == :error
                            found = 0
                            for row in DBInterface.execute(lookup, (canonical,))
                                found = row.n
                            end
                            found == 0 || throw(ArgumentError("source row $count: duplicate canonical composition $canonical; use duplicates=:keep to retain separate scored records"))
                        end
                        DBInterface.execute(insert, (canonical, score, original, count))
                        SHA.update!(digest, codeunits(canonical * "\t" * repr(score) * "\n"))
                    end
                finally
                    DBInterface.close!(insert)
                    DBInterface.close!(lookup)
                end
                count > 0 || throw(ArgumentError("source contains no composition records"))
                DBInterface.execute(db, "CREATE INDEX compositions_score_idx ON compositions(score)")
                records_sha256 = bytes2hex(SHA.digest!(digest))
                metadata = Dict("schema_version" => "1", "source" => String(source),
                    "records_sha256" => records_sha256, "row_count" => string(count),
                    "duplicate_policy" => String(duplicates), "julia_version" => string(VERSION),
                    "package_version" => string(Base.pkgversion(@__MODULE__)))
                merge!(metadata, extra_metadata())
                for key in sort!(collect(keys(metadata)))
                    DBInterface.execute(db, "INSERT INTO import_metadata VALUES (?, ?)", (key, metadata[key]))
                end
            end
        finally
            DBInterface.close!(db)
        end
        # An audit is deliberately part of the publish boundary, not after publication.
        validate_database(temporary)
        Base.Filesystem.hardlink(temporary, target)
        return (path=target, rows=count, records_sha256=records_sha256)
    end
end

"""
    import_compositions(records, destination; source, duplicates=:error)

Stream `(formula_or_Composition, precomputed_score)` records into a new standard
SQLite database. Normalize and validate every row. Canonical duplicates error by
default; `:keep` preserves them without merging scores. Preserve original formula,
source-row number, and import metadata. Publish only after transaction commit and
validation; never overwrite a destination. The containing filesystem must support
hard links. This rebuilds a query database, NOT scores or a tensor model.
"""
function import_compositions(records, destination::AbstractString;
        source::AbstractString, duplicates::Symbol=:error)
    import_records(records, destination; source, duplicates)
end

function tsv_record(raw_line, line_number, digest)
    SHA.update!(digest, codeunits(raw_line))
    fields = split(chomp(raw_line), '\t'; keepempty=true)
    length(fields) == 2 || throw(ArgumentError("TSV line $line_number must have exactly two tab-separated fields"))
    score = tryparse(Float64, fields[2])
    score === nothing && throw(ArgumentError("TSV line $line_number has an invalid score"))
    return (String(fields[1]), score)
end

"""
    import_tsv(input, destination; source, duplicates=:error)

Import UTF-8 tab-separated `composition\tscore` records, with an exact header.
No CSV quoting, blank rows, or extra columns. LF and CRLF line endings are accepted.
The SHA-256 of the exact input bytes is stored as `source_sha256`; a separate hash
identifies canonical scored records. Scores must already exist in the source.
"""
function import_tsv(input::AbstractString, destination::AbstractString;
        source::AbstractString, duplicates::Symbol=:error)
    isfile(input) || throw(ArgumentError("source file does not exist: $input"))
    open(input, "r") do io
        digest = SHA.SHA2_256_CTX()
        eof(io) && throw(ArgumentError("TSV source is empty"))
        header = readline(io; keep=true)
        chomp(header) == "composition\tscore" || throw(ArgumentError("TSV header must be composition<TAB>score"))
        SHA.update!(digest, codeunits(header))
        records = (tsv_record(line, index + 1, digest) for (index, line) in enumerate(eachline(io; keep=true)))
        metadata = () -> Dict("source_sha256" => bytes2hex(SHA.digest!(digest)), "source_filename" => basename(input), "source_format" => "tsv")
        return import_records(records, destination; source, duplicates, extra_metadata=metadata)
    end
end
