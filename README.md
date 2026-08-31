# Eka.jl

**Reading the gaps in the inorganic record.**

Created by **Joshua Corbett**.

A Julia library and command-line toolkit for **composition ranking and reproducible recovery benchmarks**. Explore precomputed scores in SQLite, import already-scored records, or audit Materials Project snapshots and evaluate positive–unlabelled (PU) recovery methods on verified composition splits.

The SQLite workflow supports score and reference-composition similarity ranking. The separate PU workflow implements the three declared methods: random, training-only element popularity, and maximum similarity to the training compositions. It does not train or reimplement tensor factorization, or establish stability, synthesizability, or experimental validity. **Real-data PU rankings have not yet been run; current end-to-end evaluation results are synthetic software checks.**

## Quick start: query stored scores

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

The reference production database inspected for this project uses the supported `data2`, `data3`, `data4ionic`, and `data5ionic` layout. That snapshot contains 4,736,551 records. **Some rows use unsupported isotope notation such as `D`; strict queries that encounter those rows fail rather than silently changing or dropping them.** Use `eka validate --report` with a database path to inspect coverage. An earlier Julia prototype provides the reference query semantics; the package separates those operations into reusable, tested components. See `docs/production-validation.md` for measured compatibility and limitations. No production database is bundled, and SQLite queries do not download or modify one. Local production databases are ignored by Git. Verify data-source permissions before redistributing derivatives.

## Binary labelled ranking benchmarks

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

The pilot measures recovery of held-out compositions with experimental provenance
from a pool of positives and unlabelled compositions. Its initial scope is
oxygen-containing ternaries; oxide chemistry is not yet validated. Unlabelled
compositions are **not confirmed negatives** and must not be supplied as failed
outcomes to the separate binary benchmark above.

| Milestone | Current state |
| --- | --- |
| Day 1: data and protocol | Local snapshot audited; scope and provenance rules frozen in the [recovery protocol](docs/mp-recovery-protocol.md) |
| Day 2: composition splits | `eka split-mp` generates deterministic holdouts, verifies provenance, and separates ranker inputs from evaluation labels; [split guide](docs/mp-recovery-splits.md) |
| Day 3: PU baseline evaluator | `eka benchmark-pu` verifies complete split bundles and evaluates random and training-only popularity; [evaluation guide](docs/mp-pu-evaluation.md) |
| Day 4: similarity comparator | Maximum training-composition similarity is implemented, streamed and benchmarked; external scores are excluded from the primary comparison by the [score provenance review](docs/mp-external-score-provenance.md) |
| Implementation freeze and real evaluation | Pending; no real-data PU rankings or recovery metrics have been run |

To try the complete pipeline without an API key or private data, follow the
[offline synthetic example](docs/mp-pu-evaluation.md#offline-end-to-end-example).
It runs fixture generation → audit → split → PU evaluation and produces
full rankings, fixed-budget recovery metrics, hashes, and reproducibility reports.
It requires Python 3.11+ and installed Julia dependencies. Output directories must
be new; synthetic results are not scientific evidence. To measure the similarity
comparator at the size a real split implies, on generated formulas only, run
`julia --startup-file=no --project=. scripts/benchmark_pu_similarity.jl`.

The [MP pilot guide](docs/mp-pilot.md) covers API setup and export/audit commands.
Real snapshots and detailed derived reports remain local and ignored by Git;
redistribution questions remain unresolved in the
[data/provenance review](docs/mp-data-provenance-review.md). The
[one-week roadmap](docs/one-week-roadmap.md) records the planned sequence. The frozen
protocol is a historical pre-evaluation record: statements there about unavailable
commands describe the freeze date, not the current CLI.

## Commands

Use `julia --project=. bin/eka` from the repository root, followed by:

| Command | Purpose |
| --- | --- |
| `--database PATH [query options]` | Query and rank stored SQLite scores; no subcommand needed |
| `import` | Build a new SQLite database from already-scored TSV records |
| `validate` | Audit a SQLite database |
| `benchmark` | Evaluate supplied scores and baselines against explicit binary outcomes |
| `audit-mp` | Verify and group an exported MP snapshot |
| `split-mp` | Generate deterministic composition-safe PU splits |
| `benchmark-pu` | Verify split bundles and evaluate the random, popularity and similarity PU methods |

Append `--help` to any subcommand for its own options; bare `--help` describes
SQLite queries. The MP exporter is a separate Python script,
`scripts/export_mp_pilot.py`, documented in the MP pilot guide.

## SQLite query options

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

Normalization intentionally loses the original formula order and overall scale. This represents **composition ratios**, not molecular identity or crystal structure. SQLite queries retain two database rows that normalize to the same composition as separate scored records; scores are not silently averaged or deduplicated. The MP recovery workflow instead groups records by canonical composition before splitting, so equivalent formulas cannot cross the training/candidate boundary.

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

The numeric threshold and requested elements are SQL parameters. Table identifiers come only from inspected metadata and are quoted safely. Legacy queries select only the requested arity tables and match exact `eleN` values in SQL before parsing. Standard-table element/arity filtering happens in Julia. Parsed results are checked again and held in memory for sorting. The inspected legacy source has no indexes; even filtered queries can require scans. We do not add indexes to user databases.

Candidate formulas and scores are validated. NULL scores are explicitly rejected. Rows excluded by the SQL threshold are not a whole-dataset validation pass. Scores must be finite numbers, but are not constrained to `[0, 1]`: the source model determines their interpretation.

## Pluggable SQLite ranking

These strategies rank stored-score records. Reference similarity here compares
each candidate with one supplied formula; it is not the PU comparator, which
takes the maximum over the training set and shares only the pairwise cosine
calculation. PU methods use separate `pu_rank` and `pu_metrics` interfaces. PU
rankers take no stored scores; ties use the frozen hash policy rather than the
stored-score fallback used here.

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
# Python 3.11+; offline exporter tests need no MP client or API key.
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
```

Tests cover normalization/hashing, seeded generative properties, exact filters, threshold boundaries, ordering invariance, both schemas, read-only enforcement, unsupported-isotope reports, custom ranking dispatch, import rollback/duplicates/provenance, and CLI output/exit behaviour. They also cover MP provenance/grouping, deterministic composition splits, bundle tampering (including rewritten checksums), label-independent PU ranking, hand-calculated recovery and similarity values, per-split training isolation, streaming allocation bounds, and deterministic reruns. Synthetic fixtures are built in temporary directories; routine tests require neither production data nor API credentials.

The fixture generator refuses to overwrite existing files. To create a separate copy:

```bash
julia --project=. test/fixtures/build_fixture.jl /path/to/new-fixture.db
```

[GitHub Actions](https://github.com/JoshCCorby/Eka.jl/actions/workflows/ci.yml) runs Julia 1.10 and current stable on Linux, current stable on macOS and Windows, and Python 3.11 exporter tests. The current-Julia Linux job also runs the offline Python fixture → Julia audit → split → PU evaluation example. Check the linked workflow for the status of a specific commit.

## SQLite query performance

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

| Module | Responsibility |
| --- | --- |
| `src/compositions.jl` | Canonical formulas, equality and hashing |
| `src/database.jl`, `src/ranking.jl`, `src/import.jl` | SQLite adapters/audits, query ranking, and scored-record ingestion |
| `src/benchmark.jl` | Binary labelled ranking benchmarks |
| `scripts/export_mp_pilot.py`, `src/mp_audit.jl` | MP snapshot export, provenance audit, and composition grouping |
| `src/mp_recovery.jl` | Deterministic PU splits and preserved provenance |
| `src/mp_pu.jl` | Split verification, training-only ranking methods, recovery metrics, and reports |
| `src/cli.jl`, `bin/eka` | Command parsing/output; only `bin/eka` exits the process |

Next is the implementation and dependency freeze, then the real experiment and
its paired analysis. External scores stay outside the primary comparison until a
new protocol version can establish training independence. Isotope
representation and additional scored-source adapters remain separate backlog
items; model training and tensor factorization remain out of scope. See the
[original design notes](docs/design.md) for SQLite engineering context and the
[roadmap](docs/one-week-roadmap.md) for the recovery pilot sequence.

## Author and research attribution

Joshua Corbett is the sole author of this Julia package and its project documentation. His contributions include the package and CLI architecture, canonical composition model, schema adapters, ranking interface, validated imports, Materials Project exporter and provenance audit, recovery benchmark protocol, deterministic composition splits, verified PU evaluation with its training-only comparators, external-score eligibility review, tests, and performance analysis.

The original recommender research and precomputed database are separate work by Atsuto Seko and collaborators, available from [sekocha/recommender](https://github.com/sekocha/recommender). This package does not claim authorship of that model or dataset. For academic use of the database, cite:

A. Seko, H. Hayashi, H. Kashima, and I. Tanaka, “Matrix- and tensor-based recommender systems for the discovery of currently unknown inorganic compounds,” *Physical Review Materials* **2**, 013805 (2018). [DOI: 10.1103/PhysRevMaterials.2.013805](https://doi.org/10.1103/PhysRevMaterials.2.013805).
