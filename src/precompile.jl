# Compile representative paths using a private temporary database, not user data.
# mktemp cleanup closes the file and removes it even if the workload fails.
function precompile_workload()
    mktemp() do path, io
        close(io)
        db = SQLite.DB(path)
        try
            DBInterface.execute(db, "CREATE TABLE compositions (composition TEXT, score REAL)")
            for row in (("Al2Ba2O7Si1", 0.74232), ("ZnMg2", 0.4), ("NaClO", 0.5))
                DBInterface.execute(db, "INSERT INTO compositions VALUES (?, ?)", row)
            end
        finally
            DBInterface.close!(db)
        end
        main(["-d", path, "-e", "Al", "Si", "O", "-n", "4"]; out=devnull, err=devnull)
        main(["-d", path]; out=devnull, err=devnull)
        query_compositions(path; elements=["Mg", "Zn"], nary=[2], threshold=0.3)
        query_compositions(path)
        main(["-d", path, "-n", "2", "--rank", "similarity", "--reference", "MgZn"]; out=devnull, err=devnull)
    end
    return nothing
end

@compile_workload begin
    precompile_workload()
end
