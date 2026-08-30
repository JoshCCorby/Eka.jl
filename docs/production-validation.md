# Production database verification

The upstream `recommender-2024-07-01.sqlite` was inspected locally on 2026-08-30 with Julia 1.12.6 and SQLite.jl 1.8.2. It remains outside the repository, is explicitly ignored by Git, and was opened read-only. SHA-256 before and after verification:

```text
9ee6f6a81f80cab74d967b70d4b0ad5d61c55ecf70e6b689c8a2c59e489a58fb
```

## Schema and full audit

| Table | Scope | Rows | Invalid/unsupported under this package's contract | Score range |
| --- | --- | ---: | ---: | --- |
| `data2` | Binary | 208,299 | 5,793 | 0.01–1.0364 |
| `data3` | Ternary | 1,474,012 | 16,135 | 0.01–1.18551 |
| `data4ionic` | Ionic quaternary | 2,588,412 | 0 | 0.001–1.12303 |
| `data5ionic` | Ionic quinary | 465,828 | 0 | 0.001–1.17031 |
| Total | | 4,736,551 | 21,928 | |

SQLite `quick_check` passed. The streaming record audit accepted **4,714,623** rows and reported **21,928** rows with unsupported element symbols. Example: `Dy1D2` contains `D`, outside the MVP's 118-element symbol set. All audited rows in the two ionic tables passed the formula/score/redundant-column checks. These are software-contract checks, not validation of scientific plausibility.

Strict validation stops on the first unsupported row. Report mode counts all affected records without modifying them. Queries remain strict and can fail on an unsupported candidate; they do not silently filter out such records or equate isotopes with ordinary hydrogen. Explicit isotope support requires a separate type/filtering decision. Consequently this package does **not** claim complete compatibility with every production record or every original query.

The unsupported symbols observed in the source columns are:

- `data2`: `Bx`, `Cx`, `Cz`, `D`, `Fx`, `Hx`, `Ix`, `Nx`, `Ox`, `Px`, `Sx`, `T`, `Vx`.
- `data3`: `D`, `Hx`, `Kx`.

20,120 rows contain `D` or `T` (counting each row once). The remaining 1,808 rejected rows involve other unsupported labels. No meaning is assumed for labels such as `Bx` or `Cz`; their source conventions must be established before designing an adapter. Simply accepting every token as an element would break the validated composition contract.

## Reference-query comparisons

`scripts/verify_production.jl` uses a separate streaming reference matching the earlier Julia prototype's element-set and strict-threshold semantics. It canonicalizes supported formulas for comparison and applies the new deterministic tie-break; it does not claim byte-for-byte output parity. It also verifies that unsupported queries fail explicitly.

| Elements | Nary | Stored score constraint | Result |
| --- | --- | --- | --- |
| Al, Si, O | 4 | `> 0.01` | All 1,106 results match |
| N | 4 | `> 0.01` | All 4,434 results match |
| Mg, Zn | 2 | `> 0.01` | All 83 results match |
| Mg, Zn | 2, 3 | `> 0.3` | All 6 results match |
| N | 5 | `> 0.3` | Both return zero results |
| Mg, Zn | 2, 3 | `> 0.01` | Original returns 1,762 rows, including 5 unsupported formulas; package rejects explicitly |

The last case includes `D1Mg1Zn1`; supporting the table layout alone does not make those isotope-containing candidates compatible with the element-only `Composition` type. The verification script reports this as an expected limitation, not successful parity.

The original script uses `score > threshold`. The package preserves its MVP default of `>=`; `--strict-threshold` or `inclusive=false` selects original semantics. For example, Al–Si–O with nary 4 returns **1,108** rows at `>= 0.01`, versus **1,106** at `> 0.01`.

## Reproduce

```bash
julia --project=. scripts/verify_production.jl /path/to/recommender-2024-07-01.sqlite
julia --project=. scripts/verify_production.jl /path/to/recommender-2024-07-01.sqlite --full-audit
julia --project=. bin/eka validate -d /path/to/recommender-2024-07-01.sqlite --report
```

The verification script passes its supported-query and expected-rejection assertions; that is **not** an assertion that the full database is supported. The standalone `validate --report` command exits 2 for this database because unsupported records were found.

## Ranking example

With binary Mg–Zn candidates above an inclusive stored-score threshold of 0.3, similarity to `Mg2Zn` produces:

```text
# Composition, Score, Similarity
Mg2Zn1   0.37147   1.00000
Mg3Zn1   0.39168   0.98995
```

The stored score is unchanged; similarity is a separate untrained mathematical measure. This is an example of reordering existing predictions, not new scientific scoring.
