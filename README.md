# Eka.jl

**Reading the gaps in the inorganic record.**

Created by **Joshua Corbett**.

A reusable Julia library and command-line tool for exploring **precomputed chemical-composition scores** in SQLite. Filter by required elements, number of distinct elements, and minimum score; get validated, canonical compositions in deterministic order.

This is a scientific software engineering project, not a new prediction model. It queries supplied scores, offers an explicit composition-similarity ranking, and imports already-scored records. It does not train or reimplement tensor factorization, or establish stability, synthesizability, or experimental validity.

## Quick start

Requires Julia 1.10 or newer. Run these commands from the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --project=. bin/eka -e Al Si O -n 4 -d test/fixtures/tiny_test.db
```

```text
# Composition, Score
Al2Ba2O7Si1   0.74232
Al2O12Si3Zn3   0.48140
Al1Li1O12Si5   0.41613
Al2Ba3O14Si4   0.39355
Al2O14Si4Sr3   0.34611
```

The included fixture has 12 hand-authored rows for software testing. Its scores are illustrative, not scientific predictions. Installation downloads Julia dependencies; queries and tests need no network access after installation.

With a separately obtained, compatible database:

```bash
julia --project=. bin/eka -e Al Si O -n 4 -d /path/to/recommender-2024-07-01.sqlite
julia --project=. bin/eka -e Mg Zn -n 2 3 --threshold 0.3 -d /path/to/recommender-2024-07-01.sqlite
julia --project=. bin/eka --help
```

The upstream production database uses the supported `data2`, `data3`, `data4ionic`, and `data5ionic` layout. It contains 4,736,551 records. **Some rows use unsupported isotope notation such as `D`; strict queries that encounter those rows fail rather than silently changing or dropping them.** Use the audit command below to inspect coverage. An earlier Julia prototype provides the reference query semantics; the package separates those operations into reusable, tested components. See `docs/production-validation.md` for measured compatibility and limitations. No production database is downloaded, modified, or redistributed; it is explicitly ignored by Git. Verify data-source permissions before redistributing derivatives.

## Fixed-budget ranking benchmarks

Compare supplied scores against random and training-element-popularity baselines
on an explicit labelled candidate pool:

```bash
julia --project=. bin/eka benchmark \
  --input examples/benchmark/candidates.tsv \
  --training examples/benchmark/training.tsv \
  --budget 2 5 10 --seeds 0 1 2 \
  --source "Synthetic software example v1; arbitrary scores/outcomes and disjoint pools" \
  --output /tmp/eka-benchmark-demo
```

The output path must be new. Reports include input snapshots and hashes, full
rankings, Hits@k/precision, recall, enrichment, element-set novelty/diversity proxies,
element coverage, and reproducibility settings. Canonical duplicates, training/pool
overlap, missing labels, and oversized budgets fail explicitly.

This evaluates supplied rankings; it does not train Seko's model or establish
stability or synthesizability. The example labels are arbitrary software fixtures.
Unobserved compounds are **not** negative outcomes, and upstream scores must be
generated without evaluation leakage. See [the benchmark protocol](docs/benchmarking.md)
for exact input/metric definitions, limitations, and library/rerun examples.

## Materials Project recovery pilot

The next research milestone is recovery of held-out compositions with experimental
provenance. A separate MP exporter and `eka audit-mp` now prepare the **data audit**:
snapshot hashes, canonical composition groups, positive/unlabelled/unresolved
counts, and explicit exclusions. The initial scope is oxygen-containing ternaries;
oxide chemistry is not yet validated. No real discovery result is implied.

See [the MP pilot guide](docs/mp-pilot.md) for secure API setup, export/audit commands,
provenance rules, and remaining work. This is separate from the binary benchmark;
unlabelled compositions must not be supplied as failed outcomes.

The [one-week roadmap](docs/one-week-roadmap.md) sets out the next implementation,
validation, and reporting milestones for 1–7 September 2026.

Day 1 choices are frozen in the [MP recovery protocol](docs/mp-recovery-protocol.md).
The [data/provenance review](docs/mp-data-provenance-review.md) records the local-only
data handling decision and unresolved redistribution questions.

Day 2 adds `eka split-mp`: deterministic composition-safe holdouts with verified
snapshot/audit provenance, manifests, and separate ranker inputs and evaluation
labels. See [split generation and the offline synthetic example](docs/mp-recovery-splits.md).
Day 3 adds [verified PU baseline evaluation](docs/mp-pu-evaluation.md) through
`eka benchmark-pu`, with random and training-only popularity methods. Synthetic
end-to-end checks are available; no real-data PU rankings or recovery metrics have
been run. The similarity comparator remains the next implementation milestone.

## CLI contract

| Option | Meaning | Default |
| --- | --- | --- |
| `-d`, `--database PATH` | Existing SQLite file | Required |
| `-e`, `--elements [ELEMENTS ...]` | Require **all** listed elements | Unrestricted |
| `-n`, `--nary [NARY ...]` | Allowed numbers of **distinct elements**, not result count | `3` |
| `--threshold NUMBER` | Inclusive minimum stored score | `0.01` |
| `--strict-threshold` | Use `score > threshold`, as in the original script | Off (`>=`) |
| `--rank score\|similarity` | Ordering method; never changes the stored score | `score` |
| `--reference FORMULA` | Reference composition for similarity ranking | Required with similarity |

`-n 2 3` permits binary and ternary compositions. Explicit `-n` with no values matches nothing; explicit `-e` with no values imposes no element restriction. Symbols are case-sensitive: `Mg` is valid, `mg` is not. Matching uses parsed symbols: asking for `N` does not match `Na`.

Results are sorted by descending score, then ascending canonical formula. Output uses the header `# Composition, Score` and five decimal places for scores. The library preserves the database's numeric score as `Float64`; output rounding does not affect ordering or threshold comparisons. No results produces just the header. Invalid input/database errors go to stderr with exit code 2; success and help return 0. There is no result limit.

With `--rank similarity`, ordering is descending similarity, then stored score, then canonical formula, and output adds a separately labelled `Similarity` column. The threshold **always** applies to the stored score. Legacy ionic-only coverage and unavailable arities are reported on stderr; stdout stays machine-readable.

## Library usage

```julia
using Eka

composition = Composition("Zn1Mg2")
@assert formula(composition) == "Mg2Zn1"
@assert composition == Composition("Mg2Zn1")
@assert Composition("Mg2Zn2") == Composition("MgZn")
@assert length(Set([Composition("MgZn"), Composition("Zn2Mg2")])) == 1

results = query_compositions("test/fixtures/tiny_test.db";
    elements=["Al", "Si", "O"], nary=[4], threshold=0.3)

for (composition, score) in results
    println(formula(composition), " => ", score)
end
```

`query_compositions` returns `Vector{Tuple{Composition,Float64}}`. Unlike the CLI, the library defaults to `nary=nothing` (all arities); `elements=nothing` is unrestricted and `threshold=0.01`. This keeps library filtering explicit while retaining the requested CLI default.

### Composition rules

- Immutable, alphabetically sorted `element => amount` pairs, with a cached canonical string.
- Only valid current element symbols and positive machine-sized integer amounts; omitted amounts mean 1.
- Repeated symbols are combined; overflow is rejected.
- Counts are reduced to the simplest integer ratio. Element order is irrelevant to equality and hashing.
- Printing includes explicit ones: `NaCl` becomes `Cl1Na1`; `Mg2Zn2` becomes `Mg1Zn1`.
- Parentheses, isotopes, charges, whitespace, zero/negative/fractional amounts, and leading-zero counts are unsupported.

Normalization intentionally loses the original formula order and overall scale. This represents **composition ratios**, not molecular identity or crystal structure. Two database rows that normalize to the same composition are retained as separate scored records; scores are not silently averaged or deduplicated.

## Database contract

The adapter supports either one ordinary table with `composition` and `score` columns, or recognized legacy tables. Mixing unrelated matching tables is an error rather than an arbitrary choice. A minimal standard schema is:

```sql
CREATE TABLE compositions (
    composition TEXT NOT NULL,
    score REAL NOT NULL
);
CREATE INDEX compositions_score_idx ON compositions(score);
```

Legacy tables additionally have `ele1` through `eleN` and `int1` through `intN`; their formulas must agree with those columns after ratio normalization. `data2` and `data3` cover binary/ternary compositions; `data4ionic` and `data5ionic` cover ionic quaternaries/quinaries only. These labels describe source coverage, not a new chemical classification performed by this package.

The file must already exist and have a SQLite header; SQLite must be able to read its schema and requested rows. Connections open with SQLite URI `mode=ro`, and statements/connections are closed even on errors. Ordinary queries are not full-file integrity audits. Missing files are never created by the query API.

The numeric threshold and requested elements are SQL parameters. Table identifiers come only from inspected metadata and are quoted safely. Legacy queries select only the requested arity tables and match exact `eleN` values in SQL before parsing. Standard-table element/arity filtering happens in Julia. Parsed results are checked again and held in memory for sorting. The supplied source has no indexes; even filtered queries can require scans. We do not add indexes to user databases.

Candidate formulas and scores are validated. NULL scores are explicitly rejected. Rows excluded by the SQL threshold are not a whole-dataset validation pass. Scores must be finite numbers, but are not constrained to `[0, 1]`: the source model determines their interpretation.

## Pluggable ranking

```julia
rows = query_compositions("test/fixtures/tiny_test.db"; nary=[2])
by_score = rank_by_score(rows)
by_similarity = rank_by_similarity(rows, "Mg2Zn")
direct = query_compositions("test/fixtures/tiny_test.db";
    nary=[2], ranking=SimilarityRanking("Mg2Zn"))
```

Both helpers return new vectors of `(Composition, stored_score)` tuples without mutating the input. Similarity is cosine similarity of element-count vectors (equivalently, atomic-fraction vectors). It is scale invariant, 1 for identical ratios, and 0 for disjoint element sets. It does **not** use learned embeddings, oxidation states, or the tensor factors, and is not a probability or a chemical-substitution model.

Extend the dispatch interface without changing database code:

```julia
struct PreferBinary <: AbstractRankingMethod end
Eka.ranking_value(::PreferBinary, c::Composition, score::Real) = length(c) == 2 ? 1.0 : 0.0
ranked = rank_compositions(rows, PreferBinary())
```

A strategy returns a finite numeric ranking value for each row. Values are computed once per candidate. Ties use descending stored score, then canonical formula. The CLI exposes the two built-in strategies; custom strategies are a library API.

## Rebuild a query database from scored source records

**Raw unscored compounds are insufficient to reconstruct the paper's predictions.** This pipeline imports supplied scores; it does not recreate the original tensor model or its proprietary training data. A rebuilt database uses this package's standard schema, not a byte-for-byte copy of the legacy source.

```bash
julia --project=. bin/eka import \
  --input examples/scored_compositions.tsv -d demo.sqlite \
  --source "synthetic example v1"
julia --project=. bin/eka -d demo.sqlite -n 2 4
julia --project=. bin/eka validate -d demo.sqlite
```

Input is UTF-8 TSV with the exact header `composition<TAB>score`. Each following line contains one simple formula and one finite numeric score. LF/CRLF are accepted; quoting, blank rows, extra columns, and missing scores are rejected. The example is synthetic. No CSV parsing dependency is required for this deliberately narrow interchange format.

For custom data adapters, stream records through the library:

```julia
import_compositions([("Zn1Mg2", 0.4), ("NaCl", 1.1)], "new.sqlite";
    source="my scored export v1", duplicates=:error)
```

Every row is validated and normalized in a transaction. Canonical duplicates fail by default, including proportional formulas. Use CLI `--duplicates keep` or library `duplicates=:keep` to retain separate rows and original scores; there is no silent aggregation. Empty sources fail. Original formulas, source-row positions, source description, canonical-record checksum, and software versions are retained; TSV imports also record the exact input-byte SHA-256. The stdlib `SHA` dependency is justified by this provenance check.

The importer builds and audits a temporary database beside the destination, then publishes it with an atomic, no-overwrite hard link. A failed import leaves no partial destination; repeating an import to an existing destination fails safely. The output directory must already exist and support hard links. Existing files—including the supplied production database—are never overwritten. This is a rebuild workflow, not an append/upsert API.

## Audit a database

```bash
# Strict: fail on the first invalid or unsupported record.
julia --project=. bin/eka validate -d /path/to/data.sqlite

# Report: scan all rows, count problems, show up to 20 examples; exit 2 if any.
julia --project=. bin/eka validate -d /path/to/data.sqlite --report
```

`validate_database(path; strict=false, max_issues=20)` returns total/valid/invalid counts, per-table counts, and bounded example errors. It runs SQLite `quick_check` and validates every formula/score and legacy redundant field. “Unsupported” does not mean scientifically invalid: isotope labels such as `D` are outside this package's current composition contract. They are neither mapped to hydrogen nor silently skipped. A query encountering one errors; unrelated legacy queries can still succeed because element filtering happens in SQL.

## Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests cover normalization/hashing, seeded generative properties, exact filters, threshold boundaries, ordering invariance, both schemas, read-only enforcement, unsupported-isotope reports, custom ranking dispatch, import rollback/duplicates/provenance, and CLI output/exit behaviour. Synthetic legacy tables are built in temporary directories; routine tests never require the production database.

The fixture generator refuses to overwrite existing files. To create a separate copy:

```bash
julia --project=. test/fixtures/build_fixture.jl /path/to/new-fixture.db
```

GitHub Actions is configured for Julia 1.10 and current stable on Linux, plus current stable on macOS and Windows. Local validation does not imply those remote jobs have run.

## Performance

```bash
# First query vs repeated calls in one Julia process; uses fixture by default.
julia --startup-file=no --project=. scripts/benchmark_query.jl

# Use the actual database when available.
julia --startup-file=no --project=. scripts/benchmark_query.jl /path/to/recommender-2024-07-01.sqlite

# Full process startup + loading + CLI parsing + query, on macOS/Linux.
/usr/bin/time -p julia --startup-file=no --project=. bin/eka -e Al Si O -n 4 -d test/fixtures/tiny_test.db
```

A new CLI invocation starts a new Julia process. It is **not** equivalent to a second function call in an existing process. A small precompilation workload exercises representative queries and CLI parsing against a temporary synthetic database to reduce repeated compilation costs. Initial installation/precompilation is a separate one-time cost and can recur after source/dependency changes.

The benchmark reports first-query and warm-query time/allocations separately; package loading is outside those internal timers. Warm measurements can benefit from OS file caching. Fixture measurements are not evidence of production-dataset performance. See `docs/performance.md` for the local measurements and methodology.

## Layout and next steps

`src/compositions.jl` owns formula invariants; `src/database.jl` owns schema adapters and audits; `src/ranking.jl` owns filtering and ranking dispatch; `src/import.jl` owns validated ingestion and provenance. `src/cli.jl` adapts those APIs to ArgParse and output streams. `bin/eka` is the only entry point that exits the process.

Next: establish the source conventions for isotope and nonstandard labels (`D`, `T`, `Bx`, `Cx`, etc.) before choosing an explicit representation policy, then add an adapter for an actual scored raw-source export. The supplied database is a scored artifact, not the raw training dataset. Model training and tensor factorization remain out of scope. See `docs/design.md` for research context and engineering trade-offs.

## Author and research attribution

Joshua Corbett is the sole author of this Julia package and its project documentation. His contributions include the package and CLI architecture, canonical composition model, schema adapters, ranking interface, validated imports, Materials Project exporter and provenance audit, recovery benchmark protocol, tests, and performance analysis.

The original recommender research and precomputed database are separate work by Atsuto Seko and collaborators, available from [sekocha/recommender](https://github.com/sekocha/recommender). This package does not claim authorship of that model or dataset. For academic use of the database, cite:

A. Seko, H. Hayashi, H. Kashima, and I. Tanaka, “Matrix- and tensor-based recommender systems for the discovery of currently unknown inorganic compounds,” *Physical Review Materials* **2**, 013805 (2018). [DOI: 10.1103/PhysRevMaterials.2.013805](https://doi.org/10.1103/PhysRevMaterials.2.013805).
