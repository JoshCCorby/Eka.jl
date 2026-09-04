const MP_SNAPSHOT_HEADER = "material_id\tcomposition\ttheoretical\tsource_ids\tnormalization_issue\n"
const MP_SNAPSHOT_SELECTED_FIELDS = ["material_id", "composition", "formula_pretty", "theoretical",
    "database_IDs", "deprecated"]

mp_document_value(document::NamedTuple, key::Symbol, default=nothing) =
    hasproperty(document, key) ? getproperty(document, key) : default
function mp_document_value(document::AbstractDict, key::Symbol, default=nothing)
    haskey(document, key) && return document[key]
    return get(document, string(key), default)
end

function mp_snapshot_formula(amounts)
    amounts isa AbstractDict && !isempty(amounts) || return ".", "missing_composition"
    terms = String[]
    for raw_symbol in sort!(collect(keys(amounts)); by=string)
        symbol = string(raw_symbol)
        occursin(r"\A[A-Z][a-z]?\z", symbol) || return ".", "unsupported_species"
        raw = amounts[raw_symbol]
        raw isa Bool && return ".", "invalid_counts"
        raw isa Real || return ".", "invalid_counts"
        value = try
            BigFloat(raw)
        catch
            return ".", "invalid_counts"
        end
        isfinite(value) && value > 0 || return ".", "invalid_counts"
        isinteger(value) || return ".", "fractional_counts"
        value <= typemax(Int64) || return ".", "count_overflow"
        push!(terms, symbol * string(Int64(value)))
    end
    return join(terms), "."
end

function mp_snapshot_cell(value)
    text = string(value)
    !isempty(text) && !any(c -> c in ('\t', '\r', '\n'), text) ||
        throw(ArgumentError("invalid empty or multiline TSV field in synthetic source data"))
    return text
end

function mp_snapshot_document(document)
    document isa Union{NamedTuple,AbstractDict} ||
        throw(ArgumentError("synthetic snapshot records must be named tuples or dictionaries"))
    material_id = mp_document_value(document, :material_id)
    material_id isa AbstractString && occursin(r"\Amp-(?:[0-9]+|[a-z]+)\z", material_id) ||
        throw(ArgumentError("unexpected or missing MP material ID"))
    formula_value, issue = mp_snapshot_formula(mp_document_value(document, :composition))
    theoretical = mp_document_value(document, :theoretical)
    theoretical === nothing || theoretical isa Bool ||
        throw(ArgumentError("malformed theoretical flag"))
    deprecated = mp_document_value(document, :deprecated, false)
    deprecated === false || throw(ArgumentError("synthetic records must not be deprecated"))
    source_ids = mp_document_value(document, :database_IDs, nothing)
    source_ids === nothing || source_ids isa AbstractDict ||
        throw(ArgumentError("malformed database_IDs"))
    sources = String[]
    normalized_sources = Dict{String,Vector{String}}()
    for (raw_source, raw_ids) in something(source_ids, Dict())
        source = string(raw_source)
        raw_ids isa AbstractVector && all(id -> id isa AbstractString, raw_ids) ||
            throw(ArgumentError("malformed source identifiers"))
        ids = String.(raw_ids)
        normalized_sources[source] = ids
        append!(sources, source * ":" * id for id in ids)
    end
    flag = theoretical === nothing ? "unknown" : lowercase(string(theoretical))
    row = Tuple(mp_snapshot_cell(value) for value in
        (material_id, formula_value, flag, isempty(sources) ? "." : join(sort!(unique!(sources)), ';'), issue))
    composition = mp_document_value(document, :composition)
    normalized_composition = composition isa AbstractDict ?
        Dict(string(key) => value for (key, value) in composition) : composition
    saved = Dict{String,Any}(
        "material_id" => String(material_id),
        "composition" => normalized_composition,
        "formula_pretty" => string(mp_document_value(document, :formula_pretty, "synthetic")),
        "theoretical" => theoretical,
        "database_IDs" => normalized_sources,
        "deprecated" => false,
    )
    return row, saved
end

"""
    write_synthetic_mp_snapshot(documents, target; database_version)

Write an offline, explicitly synthetic Materials Project-shaped snapshot for
testing Eka's audit and recovery workflows. The target must not exist. This
function performs no network access and must not be used to label real records
as synthetic.
"""
function write_synthetic_mp_snapshot(documents, target::AbstractString; database_version::AbstractString)
    destination = abspath(target)
    (ispath(destination) || islink(destination)) &&
        throw(ArgumentError("snapshot output already exists: $destination"))
    isdir(dirname(destination)) || throw(ArgumentError("snapshot parent directory does not exist"))
    isempty(strip(database_version)) && throw(ArgumentError("database_version must not be empty"))
    pairs = [mp_snapshot_document(document) for document in documents]
    isempty(pairs) && throw(ArgumentError("synthetic snapshot needs at least one record"))
    sort!(pairs; by=pair -> pair[1][1])
    ids = first.(first.(pairs))
    length(unique(ids)) == length(ids) || throw(ArgumentError("duplicate material IDs in synthetic snapshot"))
    records = Vector{UInt8}(codeunits(MP_SNAPSHOT_HEADER *
        join((join(row, '\t') * "\n" for (row, _) in pairs))))
    raw = try
        Vector{UInt8}(codeunits(join((JSON3.write(document) * "\n" for (_, document) in pairs))))
    catch
        throw(ArgumentError("synthetic snapshot records must be JSON serializable"))
    end
    metadata = Dict{String,Any}(
        "schema_version" => 2,
        "dataset" => "Materials Project",
        "database_version" => String(database_version),
        "retrieved_at_utc" => Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
        "endpoint" => "https://api.materialsproject.org/materials/summary/",
        "scope" => "oxygen-containing ternaries; not oxidation-state-validated oxides",
        "query_elements" => ["O"], "query_num_elements" => 3,
        "query_deprecated" => false, "query_include_gnome" => false,
        "fields" => MP_SNAPSHOT_SELECTED_FIELDS, "record_count" => length(pairs),
        "producer" => "Eka.write_synthetic_mp_snapshot",
        "producer_language" => "Julia",
        "producer_version" => string(Base.pkgversion(@__MODULE__)),
        "producer_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "julia_version" => string(VERSION),
        "records_sha256" => bytes2hex(sha256(records)),
        "jsonl_sha256" => bytes2hex(sha256(raw)),
        "normalization" => "exact positive integral element counts only; Julia reduces ratios",
        "date_policy" => "no first-discovery dates inferred from database timestamps",
        "redistribution_status" => "synthetic software fixture; not scientific evidence",
        "terms_url" => "https://materialsproject.org/about/terms",
        "is_synthetic" => true,
    )
    mkdir(destination)
    try
        write(joinpath(destination, "records.tsv"), records)
        write(joinpath(destination, "records.jsonl"), raw)
        open(joinpath(destination, "snapshot.toml"), "w") do io
            TOML.print(io, metadata; sorted=true)
        end
    catch
        rm(destination; recursive=true)
        rethrow()
    end
    return destination
end
