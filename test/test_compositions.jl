@testset "Composition" begin
    a, b = Composition("Mg2Zn1"), Composition("Zn1Mg2")
    @test a == b
    @test isequal(a, b)
    @test hash(a) == hash(b)
    @test length(Set([a, b])) == 1
    @test Dict(a => "found")[b] == "found"
    @test Composition("Mg2Zn2") == Composition("Mg1Zn1")
    @test Composition("MgMgZn") == a
    @test Composition(["Zn" => 2, "Mg" => 4]) == a
    @test Composition(Dict("Zn" => 2, "Mg" => 4)) == a
    @test formula(a) == "Mg2Zn1"
    @test sprint(show, a) == "Mg2Zn1"
    @test species(a) == ("Mg", "Zn")
    @test length(a) == 2
    @test (@inferred Composition("ZnMg2")) == a
    @test (@inferred formula(a)) == "Mg2Zn1"
    @test isimmutable(a) && isimmutable(a.terms)
    @test Composition("O2") == Composition("O")
    @test formula(Composition("NaCl")) == "Cl1Na1"
    @test length(Eka.ELEMENT_SYMBOLS) == 118
    for symbol in Eka.ELEMENT_SYMBOLS
        @test formula(Composition(symbol)) == symbol * "1"
    end
    for invalid in ("", "mg2Zn", "Xx2", "Mg0", "Mg01", "Mg-2", "2Mg", "Mg1.5Zn", "Mg(OH)2", "Mg Zn", "Mg\n", "Mg+", "Mg₂", "Mg999999999999999999999999")
        @test_throws ArgumentError Composition(invalid)
    end
    for entries in (Pair{String,Int}[], ["Mg" => 0], ["Mg" => -1], ["Mg" => 1.5], ["Mg" => true], ["Xx" => 1], ["Mg" => typemax(Int), "Mg" => 1])
        @test_throws ArgumentError Composition(entries)
    end
    @test_throws ArgumentError Composition("Mg$(typemax(Int))Mg")
    @test_throws ArgumentError Composition(["Mg" => big(typemax(Int)) + 1])

    # Seeded generative checks of the normalization contract.
    rng = MersenneTwister(42)
    for _ in 1:100
        selected = shuffle(rng, ["Mg", "Zn", "O", "Al", "Si"])[1:rand(rng, 1:5)]
        entries = [symbol => rand(rng, 1:20) for symbol in selected]
        original = Composition(entries)
        multiplier = rand(rng, 1:10)
        scaled = Composition(shuffle(rng, [first(p) => last(p) * multiplier for p in entries]))
        @test original == scaled
        @test hash(original) == hash(scaled)
        @test Composition(formula(original)) == original
        @test reduce(gcd, last.(original.terms)) == 1
    end
end
