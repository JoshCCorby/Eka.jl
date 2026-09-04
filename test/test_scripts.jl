# Coverage for the maintenance and measurement scripts. Each guards its own
# entry point with `abspath(PROGRAM_FILE) == @__FILE__`, so they can be included
# and their functions called directly. Each include is wrapped in its own module
# so same-named helpers (for example `report`) stay separate.
const SCRIPTS = normpath(joinpath(@__DIR__, "..", "scripts"))

# redirect_stdout has no IOBuffer method, so capture through a temporary file.
function capture_stdout(thunk)
    mktemp() do path, io
        redirect_stdout(thunk, io)
        flush(io)
        return read(path, String)
    end
end

module BenchmarkQueryScript
include(joinpath(normpath(joinpath(@__DIR__, "..", "scripts")), "benchmark_query.jl"))
end

module BenchmarkSimilarityScript
include(joinpath(normpath(joinpath(@__DIR__, "..", "scripts")), "benchmark_pu_similarity.jl"))
end

module VerifyProductionScript
include(joinpath(normpath(joinpath(@__DIR__, "..", "scripts")), "verify_production.jl"))
end

@testset "benchmark_query.jl" begin
    # Runs against the tiny fixture, as the script itself defaults to.
    output = capture_stdout(() -> BenchmarkQueryScript.benchmark_query(FIXTURE; repeats=2))
    @test occursin("First query in process", output)
    @test occursin("Warm query (minimum)", output)
    @test occursin(r"\d+ results", output)
end

@testset "benchmark_pu_similarity.jl" begin
    pool = BenchmarkSimilarityScript.synthetic_pool(12)
    @test length(pool) == 12
    # Deterministic, distinct, and disjoint across offsets.
    @test pool == BenchmarkSimilarityScript.synthetic_pool(12)
    @test length(unique(formula.(pool))) == 12
    @test isempty(intersect(Set(formula.(pool)),
        Set(formula.(BenchmarkSimilarityScript.synthetic_pool(12; offset=12)))))
    @test all(c -> "O" in species(c) && length(c) == 3, pool)
    output = capture_stdout(() -> BenchmarkSimilarityScript.benchmark_pu_similarity(
        training_count=16, candidate_count=24, repeats=1))
    @test occursin("Ranking digest (deterministic)", output)
end

@testset "verify_production.jl" begin
    mktempdir() do dir
        path = joinpath(dir, "legacy.db")
        db = SQLite.DB(path)
        try
            rows = Dict("data2" => [("Mg2Zn", 0.3), ("NaCl", 0.5)], "data3" => [("NaClO", 0.7)],
                "data4ionic" => [("Al2Ba2O7Si1", 0.74232)], "data5ionic" => [("MgZnAlSiO", 0.8)])
            for name in sort!(collect(keys(rows)))
                n = EkaCompositions.LEGACY_TABLES[name]
                columns = ["composition TEXT"]
                append!(columns, ["ele$i TEXT" for i in 1:n])
                append!(columns, ["int$i INTEGER" for i in 1:n])
                push!(columns, "score REAL")
                DBInterface.execute(db, "CREATE TABLE $name ($(join(columns, ", ")))")
                for (raw, score) in rows[name]
                    c = Composition(raw)
                    values = (raw, first.(c.terms)..., last.(c.terms)..., score)
                    DBInterface.execute(db, "INSERT INTO $name VALUES ($(join(fill("?", length(values)), ", ")))", values)
                end
            end
        finally
            DBInterface.close!(db)
        end
        before = read(path)
        # The script asserts the reference and package queries agree, and that it
        # left the database byte-identical.
        output = capture_stdout(() -> VerifyProductionScript.verify_production(path; full_audit=true))
        @test occursin("SHA-256: ", output)
        @test occursin("Full audit: ", output)
        @test read(path) == before
    end
end

@testset "run_pair_feasibility.jl" begin
    # No PROGRAM_FILE guard: it runs on include, so drive it as a subprocess.
    mktempdir() do dir
        target = joinpath(dir, "feasibility")
        project = normpath(joinpath(@__DIR__, ".."))
        script = joinpath(SCRIPTS, "run_pair_feasibility.jl")
        @test success(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$project $script $target`,
            stdout=devnull, stderr=devnull))
        for name in ("config.toml", "summary.tsv", "runtime.tsv")
            @test isfile(joinpath(target, name))
        end
        config = EkaCompositions.recovery_toml(read(joinpath(target, "config.toml")), "feasibility config")
        @test config["is_synthetic"] === true
        @test config["model_id"] == EkaCompositions.Research.ElementPairModel.MODEL_ID
        # Refuses to overwrite an existing output directory.
        @test !success(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$project $script $target`,
            stdout=devnull, stderr=devnull))
    end
end
