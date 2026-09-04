import Aqua

# Package-quality checks. Ambiguities, unbound type parameters and piracy are
# clean; the dependency-compat check inspects [extras] as well as [deps], which
# is why Aqua, Random and Test carry their own [compat] entries.
@testset "Aqua" begin
    Aqua.test_all(EkaCompositions)
end
