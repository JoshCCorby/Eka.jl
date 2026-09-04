# API stability and compatibility

What callers may rely on in the 0.1.x series, and what may change without a
breaking release. Enforced by `test/test_api.jl`, which fails if an exported name
is added without being classified here.

Julia's `public` keyword requires 1.11 and this package supports 1.10, so this
document plus that test are the contract. Every name below is exported; anything
not exported is internal regardless of what this page says.

## Stable

Available for the life of 0.1.x. Signatures and observable behaviour will not
change incompatibly; new keyword arguments with defaults may be added.

| Name | Purpose |
| --- | --- |
| `Composition` | Canonical reduced element ratio |
| `formula` | Canonical formula string |
| `species` | Element symbols in a composition |
| `similarity` | Cosine overlap of element-count vectors |
| `query_compositions` | Read-only query over a score database |
| `database_info` | Schema inspection |
| `validate_database` | Record audit |
| `import_compositions`, `import_tsv` | Ingest already-scored records |
| `rank_compositions` | Rank rows under a ranking method |
| `ranking_value` | Extension point for a new ranking method |
| `AbstractRankingMethod`, `ScoreRanking`, `SimilarityRanking` | Ranking types |
| `rank_by_score`, `rank_by_similarity` | Shorthand rankers |

`Composition` equality and hashing ignore element order and overall scale. That
is load-bearing for callers using compositions as dictionary keys, and will not
change in 0.1.x.

## Stable command-line behaviour, experimental Julia signature

These back the frozen command-line interface. The **CLI behaviour is stable** for
0.1.x — the same arguments produce the same results and the same output format.
The **Julia function signatures are not**: they may gain, lose or reorder
arguments in a 0.1.x release, because they exist to serve the CLI and the
research protocols rather than as a general-purpose library surface.

| Name | Backs |
| --- | --- |
| `main` | The `eka` entry point |
| `benchmark_rankings`, `benchmark_tsv` | `eka benchmark` |
| `audit_mp_snapshot` | `eka audit-mp` |
| `split_mp_recovery` | `eka split-mp` |
| `benchmark_pu` | `eka benchmark-pu` |

The CLI offers six subcommands — `import`, `validate`, `benchmark`, `audit-mp`,
`split-mp`, `benchmark-pu` — plus the default mode, where `eka` with no
subcommand runs a stored-score query.

`main` is exported today, but the name is generic enough to collide with other
packages. The intent is to unexport it at 0.2.0 while keeping the function. Do
not rely on `using EkaCompositions` bringing `main` into scope.

## Experimental

Part of the research surface. These may change in any 0.1.x release; a change is
recorded in the changelog rather than in the version number.

`mp_recovery_splits`, `load_mp_recovery`, `pu_rank`, `pu_metrics`,
`write_synthetic_mp_snapshot`.

`pu_rank` and `pu_metrics` are the documented interfaces for positive–unlabelled
ranking, and are usable, but the positive–unlabelled work is research code whose
shape follows the protocols. Treat them as experimental.

## Internal

Everything under `EkaCompositions.Research` — `MPLabelSensitivity`,
`MPSystemHoldout`, `ElementPairModel`, `MPElementPair` — is internal. Nothing
there is exported, no research subcommand is wired into the CLI, and interfaces
may change between any two releases with no deprecation path. They live in the
package so they are precompiled, tested and loaded once, not because they are a
public API.

## Database schema compatibility

Two layouts are read, both read-only and validated strictly:

- A standard table with `composition` (text) and `score` (real) columns.
- The legacy `data2` / `data3` / `data4ionic` / `data5ionic` layout, with
  `ele1…eleN` and `int1…intN` columns alongside `composition` and `score`.

The legacy reader is frozen for 0.1.x: no table names will be added or removed,
and the strict validation behaviour will not be relaxed. Formulas that cannot be
parsed — isotope notation such as `D`, for example — cause a strict query to fail
rather than silently drop or alter rows. `eka validate --report` scans without
failing on the first problem.

Queries never create, modify or migrate a database.

## Generated report formats

Generated metadata carries a `schema_version` field. Its current state is not
uniform across producers, and this is documented as observed rather than as a
guarantee:

| Producer | Field value |
| --- | --- |
| `benchmark_rankings` (`src/benchmark.jl`) | integer `1` |
| `import_compositions` (`src/import.jl`) | **string** `"1"` |
| `write_synthetic_mp_snapshot` (`src/mp_snapshot.jl`) | integer `2` |
| MP audit output (`src/mp_audit.jl`) | integer `1`; reads accept `1` or `2` |

Readers should accept both an integer and a string for this field. The
string/integer inconsistency in the import path is a known wart; correcting it
would break existing readers, so it is deferred to 0.2.0.

Within a `schema_version`, keys may be **added** without a version change.
Removing a key, or changing the meaning or type of an existing one, requires a
`schema_version` bump.

Generated research bundles additionally record `protocol_id` and
`protocol_sha256`. Those identify a frozen protocol document and are not a
software compatibility signal: a changed protocol is a new experiment, not a new
release. See [the recovery protocol](mp-recovery-protocol.md).

## Julia compatibility

The floor is Julia 1.10. Raising it is a breaking change for 0.1.x purposes and
will not happen in this series.
