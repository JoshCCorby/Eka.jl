const ELEMENT_SYMBOLS = Tuple(split("""
H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni
Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe
Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg
Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg
Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og
"""))

function validate_element(value)
    value isa AbstractString || throw(ArgumentError("element symbols must be strings"))
    symbol = String(value)
    symbol in ELEMENT_SYMBOLS || throw(ArgumentError("invalid element symbol: $(repr(symbol))"))
    return symbol
end

"""
    Composition(formula::AbstractString)
    Composition(pairs)

An immutable composition of valid element symbols and positive integer amounts.
Repeated symbols are combined, amounts are reduced by their greatest common divisor,
and symbols are sorted alphabetically. The stored pairs and strings are immutable.
Only simple formulas are accepted (no parentheses, charges, or fractional amounts).
"""
struct Composition
    terms::Tuple{Vararg{Pair{String,Int}}}
    canonical::String

    function Composition(entries)
        counts = Dict{String,Int}()
        for entry in entries
            entry isa Pair || throw(ArgumentError("composition entries must be element => amount pairs"))
            symbol = validate_element(first(entry))
            amount = last(entry)
            amount isa Integer && !(amount isa Bool) && 0 < amount <= typemax(Int) ||
                throw(ArgumentError("amount for $symbol must be a positive machine-sized integer"))
            previous = get(counts, symbol, 0)
            amount <= typemax(Int) - previous ||
                throw(ArgumentError("total amount for $symbol exceeds the integer limit"))
            counts[symbol] = previous + Int(amount)
        end
        isempty(counts) && throw(ArgumentError("composition must contain at least one element"))
        divisor = reduce(gcd, values(counts))
        terms = Tuple(symbol => div(counts[symbol], divisor) for symbol in sort!(collect(keys(counts))))
        canonical = join(string(first(term), last(term)) for term in terms)
        return new(terms, canonical)
    end
end

function Composition(input::AbstractString)
    occursin(r"\A(?:[A-Z][a-z]?(?:[1-9][0-9]*)?)+\z", input) ||
        throw(ArgumentError("invalid simple formula: $(repr(input)); use symbols with positive integer amounts"))
    entries = Pair{String,Int}[]
    for token in eachmatch(r"([A-Z][a-z]?)([0-9]*)", input)
        symbol = String(token.captures[1])
        digits = token.captures[2]
        amount = isempty(digits) ? 1 : tryparse(Int, digits)
        amount === nothing && throw(ArgumentError("amount in $(repr(input)) exceeds the integer limit"))
        push!(entries, symbol => amount)
    end
    return Composition(entries)
end

"""Return the alphabetically ordered, reduced formula, including explicit ones."""
formula(composition::Composition) = composition.canonical

"""Return an immutable tuple of the distinct element symbols."""
species(composition::Composition) = map(first, composition.terms)

Base.length(composition::Composition) = length(composition.terms)
Base.:(==)(a::Composition, b::Composition) = a.terms == b.terms
Base.isequal(a::Composition, b::Composition) = isequal(a.terms, b.terms)
Base.hash(composition::Composition, seed::UInt) = hash(composition.terms, hash(:Composition, seed))
Base.show(io::IO, composition::Composition) = print(io, formula(composition))
