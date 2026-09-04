#!/usr/bin/env julia

"""Create a tiny, explicitly synthetic recovery snapshot without network access."""
module MakeRecoverySnapshot

using EkaCompositions

function documents()
    rows = NamedTuple[]
    function add(composition, theoretical)
        push!(rows, (material_id="mp-$(length(rows) + 1)", composition=composition,
            formula_pretty="synthetic", theoretical=theoretical,
            database_IDs=theoretical === false ? Dict("icsd" => ["synthetic"]) : Dict{String,Vector{String}}(),
            deprecated=false))
    end
    for index in 1:10
        add(Dict("Li" => index, "Na" => 1, "O" => 1), false)
    end
    add(Dict("Li" => 2, "Na" => 2, "O" => 2), true)
    add(Dict("Mg" => 1, "Al" => 2, "O" => 4), true)
    add(Dict("Ca" => 1, "Ti" => 1, "O" => 3), true)
    add(Dict("Ba" => 1, "Ti" => 1, "O" => 3), nothing)
    add(Dict("Ba" => 2, "Ti" => 2, "O" => 6), true)
    return rows
end

function main(args=ARGS)
    length(args) == 1 || throw(ArgumentError("usage: make_snapshot.jl NEW_SNAPSHOT_DIRECTORY"))
    output = write_synthetic_mp_snapshot(documents(), only(args);
        database_version="synthetic-recovery-v2")
    println("Created synthetic snapshot: $output")
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(MakeRecoverySnapshot.main())
    catch error
        error isa ArgumentError || rethrow()
        println(stderr, "make_snapshot: error: ", sprint(showerror, error))
        exit(2)
    end
end
