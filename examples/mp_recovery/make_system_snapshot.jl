#!/usr/bin/env julia

"""Create offline synthetic systems with unequal sizes and mixed labels."""
module MakeSystemSnapshot

using EkaCompositions

function documents()
    rows = NamedTuple[]
    function add(composition, theoretical)
        push!(rows, (material_id="mp-$(length(rows) + 1)", composition=composition,
            formula_pretty="synthetic", theoretical=theoretical,
            database_IDs=theoretical === false ? Dict("icsd" => ["synthetic"]) : Dict{String,Vector{String}}(),
            deprecated=false))
    end
    for (position, element) in enumerate(("Li", "K", "Rb", "Cs", "Be", "Mg", "Ca", "Sr", "Ba", "Al"))
        last = position == 1 ? 10 : 5
        for index in 1:last
            add(Dict(element => index, "Na" => 1, "O" => 1), false)
        end
        add(Dict(element => 1, "Na" => 1, "O" => 1), true)
        for index in last + 1:last + 2
            add(Dict(element => index, "Na" => 1, "O" => 1), true)
        end
    end
    add(Dict("Mg" => 1, "Al" => 1, "O" => 1), true)
    add(Dict("Fe" => 1, "Co" => 1, "O" => 1), nothing)
    return rows
end

function main(args=ARGS)
    length(args) == 1 || throw(ArgumentError("usage: make_system_snapshot.jl NEW_SNAPSHOT_DIRECTORY"))
    output = write_synthetic_mp_snapshot(documents(), only(args);
        database_version="synthetic-system-v2")
    println("Created synthetic system snapshot: $output")
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(MakeSystemSnapshot.main())
    catch error
        error isa ArgumentError || rethrow()
        println(stderr, "make_system_snapshot: error: ", sprint(showerror, error))
        exit(2)
    end
end
