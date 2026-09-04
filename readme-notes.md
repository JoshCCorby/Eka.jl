# README reconnaissance notes

Reconnaissance date: 2026-09-04.

## Identity and metadata

| Fact | Evidence |
| --- | --- |
| Product name is Eka; package and top-level module are `EkaCompositions`; CLI is `eka`. | `README.md:1-8`; `Project.toml:1`; `src/EkaCompositions.jl:4`; `bin/eka:3-5` |
| Package UUID is `c7a2c8e1-9a94-4aec-99d6-21468f025a93`; version is `0.1.0`; author is Joshua Corbett. | `Project.toml:2-4` |
| Minimum Julia compatibility is 1.10. | `Project.toml:27` |
| Direct external dependencies are ArgParse, DBInterface, JSON3, PrecompileTools and SQLite. Dates, Printf, SHA and TOML are Julia standard libraries. | `Project.toml:6-15` |
| Every dependency and Julia has a compatibility entry. | `Project.toml:17-27` |
| The package is MIT licensed, copyright 2026 Joshua Corbett. | `LICENSE:1-20` |
| Citation metadata describes “Eka: composition ranking and reproducible recovery benchmarks”, version 0.1.0, by Joshua Corbett. No DOI is present. | `CITATION.cff:1-20` |
| The repository has third-party notices covering reused Seko examples, separately obtained Materials Project data and dependency licences. | `THIRD_PARTY_NOTICES.md:1-81` |
| No `.zenodo.json` or Codecov configuration exists. | repository search: `find . -maxdepth 2` for `.zenodo.json`, `codecov.yml`, `.codecov.yml` returned no files |

### CI and earned badges

| Capability | Repository evidence | Badge status |
| --- | --- | --- |
| Tests | Julia CI runs on pushes and pull requests. It tests Julia 1.10 and current stable on Ubuntu, plus current stable on macOS and Windows. | Earned: workflow status badge for `.github/workflows/ci.yml`. |
| Python validation | Python 3.11 runs the release audit and MP exporter tests in its own Ubuntu job. The current-Julia Ubuntu job also runs four Python analysis test files after the end-to-end example. | Covered by the Julia CI workflow badge. |
| Source release audit | CI runs `test_release_audit.py` and `scripts/verify_release.py --archive HEAD`. | Covered by the Julia CI workflow badge. |
| Documentation deploy | No documentation deployment workflow exists. | No docs badge. |
| Coverage | No coverage job or Codecov configuration exists. | No coverage badge. |
| Release automation | TagBot reacts to JuliaTagBot issue comments and manual dispatch. | Automation exists, but this is not a test badge. |
| DOI/paper | `CITATION.cff` has no DOI and there is no Zenodo metadata. | No DOI or paper badge. |
| Licence | Root `LICENSE` is MIT. | Earned: MIT licence badge. |

Evidence: `.github/workflows/ci.yml:1-58`; `.github/workflows/TagBot.yml:1-16`; `LICENSE:1`; `CITATION.cff:1-20`.

Badge and destination URLs checked with redirected HTTP GETs on 2026-09-04:

| Badge | Image URL | Destination | Check |
| --- | --- | --- | --- |
| CI | `https://github.com/JoshCCorby/EkaCompositions.jl/actions/workflows/ci.yml/badge.svg` | `https://github.com/JoshCCorby/EkaCompositions.jl/actions/workflows/ci.yml` | Both HTTP 200 |
| Release | `https://img.shields.io/github/v/release/JoshCCorby/EkaCompositions.jl` | `https://github.com/JoshCCorby/EkaCompositions.jl/releases/latest` | Both HTTP 200 |
| Licence | `https://img.shields.io/github/license/JoshCCorby/EkaCompositions.jl` | `https://github.com/JoshCCorby/EkaCompositions.jl/blob/main/LICENSE` | Both HTTP 200 |

## CLI surface

`bin/eka` imports `EkaCompositions` and exits with the integer returned by
`EkaCompositions.main()` (`bin/eka:1-5`). `main` dispatches six named
subcommands before parsing the default query mode (`src/cli.jl:52-76`).

### Commands and options from the parser

| Entry mode | Options and defaults | Evidence |
| --- | --- | --- |
| query (no subcommand) | `-h/--help` off; `-d/--database` required; `-e/--elements` unrestricted; `-n/--nary` `[3]`; `--threshold` `0.01`; `--strict-threshold` off, meaning `>=`; `--rank` `score`, allowed values `score` or `similarity`; `--reference` unset and required only for similarity | `src/cli.jl:1-42`, `src/cli.jl:61-92` |
| `import` | `-h/--help` off; `--input` required; `-d/--database` required and must be new; `--source` required; `--duplicates` `error`, allowed values `error` or `keep` | `src/cli.jl:103-136` |
| `validate` | `-h/--help` off; `-d/--database` required; `--report` off | `src/cli.jl:139-170` |
| `benchmark` | `-h/--help` off; `--input`, `--training`, `--output` and `--source` required; `--methods` `score,random,popularity`; `--budget` `[25, 50, 100]`; `--seeds` `[0, 1, 2]` | `src/benchmark.jl:212-259` |
| `audit-mp` | `-h/--help` off; `--snapshot` and `--output` required | `src/mp_audit.jl:302-327` |
| `split-mp` | `-h/--help` off; `--snapshot`, `--audit` and `--output` required; `--synthetic` off; `--seeds` `0:19`; `--budget` `[20, 50, 100, 200]` | `src/mp_recovery.jl:323-363` |
| `benchmark-pu` | `-h/--help` off; `--splits`, `--snapshot`, `--audit` and `--output` required; `--synthetic` off | `src/mp_pu.jl:350-381` |

### Saved live help output

Commands run from the repository root on 2026-09-04:

```bash
julia --startup-file=no --project=. bin/eka --help
julia --startup-file=no --project=. bin/eka import --help
julia --startup-file=no --project=. bin/eka validate --help
julia --startup-file=no --project=. bin/eka benchmark --help
julia --startup-file=no --project=. bin/eka audit-mp --help
julia --startup-file=no --project=. bin/eka split-mp --help
julia --startup-file=no --project=. bin/eka benchmark-pu --help
```

All returned status 0. Output:

```text
usage: eka [-h] -d DATABASE [-e [ELEMENTS...]] [-n [NARY...]]
           [--threshold THRESHOLD] [--strict-threshold] [--rank RANK]
           [--reference REFERENCE]

Explore precomputed chemical-composition scores in SQLite.

optional arguments:
  -h, --help            Show this help message and exit
  -d, --database DATABASE
                        Existing SQLite database (required)
  -e, --elements [ELEMENTS...]
                        Require all listed element symbols; an empty
                        list is unrestricted
  -n, --nary [NARY...]  Allowed numbers of distinct elements; an empty
                        list matches nothing (type: Int64, default: [3])
  --threshold THRESHOLD Inclusive minimum stored score (type: Float64,
                        default: 0.01)
  --strict-threshold    Use score > threshold, matching the original
                        script (default: >=)
  --rank RANK           Ranking method: score or similarity (threshold
                        still filters stored scores) (default: "score")
  --reference REFERENCE Reference formula required for --rank similarity

Additional commands: eka import --help; eka validate --help; eka benchmark
--help; eka audit-mp --help; eka split-mp --help; eka benchmark-pu --help

usage: eka import [-h] --input INPUT -d DATABASE --source SOURCE
                  [--duplicates DUPLICATES]

Build a NEW query database from already-scored TSV records.

optional arguments:
  -h, --help            Show import help
  --input INPUT         TSV source with composition and score columns
  -d, --database DATABASE
                        New output database; existing files are never overwritten
  --source SOURCE       Source/version description recorded in import metadata
  --duplicates DUPLICATES
                        Canonical duplicates: error or keep (no score aggregation)
                        (default: "error")

usage: eka validate [-h] -d DATABASE [--report]

Audit all SQLite records without modifying the database.

optional arguments:
  -h, --help            Show validation help
  -d, --database DATABASE
                        Existing database to audit
  --report              Scan all rows and report unsupported/invalid records
                        (exit 2 if any)

usage: eka benchmark [-h] --input INPUT --training TRAINING --output OUTPUT
                     --source SOURCE [--methods METHODS]
                     [--budget BUDGET [BUDGET...]] [--seeds SEEDS [SEEDS...]]

Compare rankings on explicit labelled candidates at fixed budgets.

optional arguments:
  -h, --help            Show benchmark help
  --input INPUT         Candidate TSV: composition, score, outcome (0 or 1)
  --training TRAINING   Known-positive training TSV: composition
  --output OUTPUT       New report directory; parent must exist
  --source SOURCE       Describe dataset/version, outcome meaning, split, and
                        score provenance
  --methods METHODS     Comma-separated methods: score,random,popularity
                        (default: "score,random,popularity")
  --budget BUDGET [BUDGET...]
                        Positive candidate budgets, each <= pool size
                        (default: [25, 50, 100])
  --seeds SEEDS [SEEDS...]
                        Nonnegative random baseline seeds (default: [0, 1, 2])

usage: eka audit-mp [-h] --snapshot SNAPSHOT --output OUTPUT

Audit an MP pilot snapshot without interpreting unlabelled compounds as failures.

optional arguments:
  -h, --help           Show MP audit help
  --snapshot SNAPSHOT  Directory containing records.tsv, records.jsonl, and
                       snapshot.toml
  --output OUTPUT      New audit directory; parent must exist

usage: eka split-mp [-h] --snapshot SNAPSHOT --audit AUDIT --output OUTPUT
                    [--synthetic] [--seeds SEEDS [SEEDS...]]
                    [--budget BUDGET [BUDGET...]]

Generate composition-safe MP recovery splits; no ranking.

optional arguments:
  -h, --help
  --snapshot SNAPSHOT  Preserved original snapshot directory
  --audit AUDIT        Audit generated from this snapshot
  --output OUTPUT      New local output directory; parent must exist
  --synthetic          Require synthetic inputs; never bypass checks for real inputs
  --seeds SEEDS [SEEDS...]
                       Split seeds; overrides permitted only for synthetic inputs
                       (default: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
                       14, 15, 16, 17, 18, 19])
  --budget BUDGET [BUDGET...]
                       Planned budgets; overrides permitted only for synthetic inputs
                       (default: [20, 50, 100, 200])

usage: eka benchmark-pu [-h] --splits SPLITS --snapshot SNAPSHOT
                        --audit AUDIT --output OUTPUT [--synthetic]

Verify split bundles and evaluate the declared PU random, popularity and
similarity methods.

optional arguments:
  -h, --help
  --splits SPLITS      Verified Day 2 split bundle
  --snapshot SNAPSHOT
  --audit AUDIT
  --output OUTPUT      New local output directory
  --synthetic          Require synthetic snapshot and split bundle
```

The saved text above preserves every option/default while wrapping some long help
lines more compactly. The parser locations in the option table are authoritative.

### CLI freshness against README

| Check | Result | Evidence |
| --- | --- | --- |
| Missing or removed command names | None. All six subcommands and query mode appear in the README command table. | `README.md:109-125`; dispatch in `src/cli.jl:52-60` |
| Missing, renamed or default-changed query options | None. The query table matches the parser, including `nary=[3]`, threshold `0.01`, score ranking, unrestricted elements and similarity reference requirement. | `README.md:127-143`; `src/cli.jl:10-42`, `src/cli.jl:67-76` |
| Subcommand options | The command table gives purposes only. Options are distributed across later examples/docs and are not enumerated centrally. | `README.md:109-125`; parser locations in the table above |

## Library surface

The top-level module exports 28 names (`src/EkaCompositions.jl:16-23`).

| Export | Signature | Purpose | Evidence |
| --- | --- | --- | --- |
| `Composition` | `Composition(formula::AbstractString)`; `Composition(pairs)` | Construct an immutable, canonical, reduced composition. | `src/compositions.jl:16-61` |
| `formula` | `formula(composition::Composition)` | Return the canonical formula with explicit counts. | `src/compositions.jl:64-65` |
| `species` | `species(composition::Composition)` | Return the immutable tuple of element symbols. | `src/compositions.jl:67-68` |
| `query_compositions` | `query_compositions(path; elements=nothing, nary=nothing, threshold=0.01, inclusive=true, ranking=ScoreRanking())` | Query supported SQLite schemas and return ranked `(Composition, Float64)` rows. | `src/database.jl:135-171` |
| `main` | `main(args=ARGS; out=stdout, err=stderr) -> Int` | Run CLI parsing without exiting the calling process. | `src/cli.jl:46-101` |
| `AbstractRankingMethod` | abstract type | Extension point for SQLite ranking strategies. | `src/ranking.jl:37-38` |
| `ScoreRanking` | `ScoreRanking()` | Rank by the stored database score. | `src/ranking.jl:40-41`, `src/ranking.jl:53` |
| `SimilarityRanking` | `SimilarityRanking(reference::Composition)`; `SimilarityRanking(reference::AbstractString)` | Rank by cosine similarity to one reference composition. | `src/ranking.jl:45-55` |
| `ranking_value` | `ranking_value(method, composition, stored_score)` | Compute one strategy-specific ranking value; users extend this method for custom strategies. | `src/ranking.jl:37`, `src/ranking.jl:53-64` |
| `rank_compositions` | `rank_compositions(results, method::AbstractRankingMethod=ScoreRanking())` | Return a ranked copy of scored composition rows. | `src/ranking.jl:77-87` |
| `rank_by_score` | `rank_by_score(results)` | Rank a copy using `ScoreRanking`. | `src/ranking.jl:89` |
| `rank_by_similarity` | `rank_by_similarity(results, reference)` | Rank a copy using `SimilarityRanking`. | `src/ranking.jl:90` |
| `similarity` | `similarity(a::Composition, b::Composition)` | Compute composition-vector cosine similarity in `[0, 1]`. | `src/ranking.jl:66-67` |
| `database_info` | `database_info(path::AbstractString)` | Inspect supported tables and arity/ionic coverage without loading records. | `src/database.jl:71-78` |
| `validate_database` | `validate_database(path; strict=true, max_issues=20)` | Run SQLite `quick_check` and audit all formula, score and legacy fields without modifying data. | `src/database.jl:178-224` |
| `import_compositions` | `import_compositions(records, destination; source, duplicates=:error)` | Build and validate a new query database from existing scored records. | `src/import.jl:79-101` |
| `import_tsv` | `import_tsv(input, destination; source, duplicates=:error)` | Import strict `composition<TAB>score` data and retain exact/canonical hashes. | `src/import.jl:103-125` |
| `benchmark_rankings` | `benchmark_rankings(records, training; budgets=[25, 50, 100], seeds=[0, 1, 2], methods=["score", "random", "popularity"])` | Evaluate supplied binary-labelled rankings and baselines at fixed budgets. | `src/benchmark.jl:17-112` |
| `benchmark_tsv` | `benchmark_tsv(input, training, output; source, kwargs...)` | Read benchmark TSVs and write a new provenance-preserving report. | `src/benchmark.jl:134-209` |
| `audit_mp_snapshot` | `audit_mp_snapshot(snapshot, output)` | Verify an MP-shaped snapshot and group records into positive, unlabelled or unresolved compositions. | `src/mp_audit.jl:103-300` |
| `mp_recovery_splits` | `mp_recovery_splits(groups; seeds=0:19, budgets=[20, 50, 100, 200])` | Compute deterministic composition-safe PU memberships. | `src/mp_recovery.jl:49-94` |
| `split_mp_recovery` | `split_mp_recovery(snapshot, audit, output; synthetic=false, seeds=0:19, budgets=[20, 50, 100, 200])` | Verify provenance and save a new split bundle. | `src/mp_recovery.jl:199-320` |
| `write_synthetic_mp_snapshot` | `write_synthetic_mp_snapshot(documents, target; database_version)` | Write an offline synthetic MP-shaped snapshot for testing. | `src/mp_snapshot.jl:83-152` |
| `load_mp_recovery` | `load_mp_recovery(bundle, snapshot, audit; synthetic=false)` | Verify and load a split bundle against its original snapshot and audit. | `src/mp_pu.jl:20-109` |
| `pu_rank` | `pu_rank(training, candidates; method, ranking_seed=10000, tie_seed=20260901)` | Rank composition-only PU candidates by random, popularity or maximum training similarity. | `src/mp_pu.jl:171-212` |
| `pu_metrics` | `pu_metrics(ranking, heldout; budgets)` | Calculate hits, observed-label fraction, recall, enrichment and expected random hits. | `src/mp_pu.jl:214-239` |
| `benchmark_pu` | `benchmark_pu(bundle, snapshot, audit, output; synthetic=false)` | Verify all splits, evaluate all declared PU methods and save rankings, metrics and provenance. | `src/mp_pu.jl:250-347` |

### README snippet verification

All Julia snippets in the current README ran unchanged on 2026-09-04. The ranking
extension block depends on the `rows` variable created by the preceding ranking
block, as presented in the README.

| README snippet | Result | Evidence |
| --- | --- | --- |
| Composition construction plus `query_compositions` loop | Passed all four assertions and printed five rows from `test/fixtures/tiny_test.db`. | `README.md:147-162`; execution during recon |
| `rank_by_score`, `rank_by_similarity` and direct `SimilarityRanking` query | Ran successfully and returned five binary rows. | `README.md:206-212`; execution during recon |
| Custom `PreferBinary <: AbstractRankingMethod` | Ran successfully after the preceding block and ranked the five rows. | `README.md:216-222`; execution during recon |
| `import_compositions` | Ran unchanged in a fresh temporary working directory and imported two rows into `new.sqlite`. | `README.md:240-245`; execution during recon |

Verified output from the main library snippet:

```text
Al2Ba2O7Si1 => 0.74232
Al2O12Si3Zn3 => 0.4814
Al1Li1O12Si5 => 0.41613
Al2Ba3O14Si4 => 0.39355
Al2O14Si4Sr3 => 0.34611
```

## Offline pipeline and research workflows

### CI pipeline

The current-Julia Ubuntu job runs this order: Julia synthetic snapshot generator →
`eka audit-mp` → `eka split-mp` → `eka benchmark-pu` → Python analysis. It then
runs the pilot, label-sensitivity, system-holdout and element-pair Python tests
(`.github/workflows/ci.yml:46-58`). Exact commands:

```bash
julia --project=. examples/mp_recovery/make_snapshot.jl "$RUNNER_TEMP/pu-snapshot"
julia --project=. bin/eka audit-mp --snapshot "$RUNNER_TEMP/pu-snapshot" --output "$RUNNER_TEMP/pu-audit"
julia --project=. bin/eka split-mp --snapshot "$RUNNER_TEMP/pu-snapshot" --audit "$RUNNER_TEMP/pu-audit" --output "$RUNNER_TEMP/pu-splits" --synthetic --budget 1 4
julia --project=. bin/eka benchmark-pu --splits "$RUNNER_TEMP/pu-splits" --snapshot "$RUNNER_TEMP/pu-snapshot" --audit "$RUNNER_TEMP/pu-audit" --output "$RUNNER_TEMP/pu-results" --synthetic
python scripts/analyze_pu_pilot.py "$RUNNER_TEMP/pu-results" "$RUNNER_TEMP/pu-analysis"
python -m unittest discover -s test -p 'test_pu_analysis.py' -v
python -m unittest discover -s test -p 'test_label_sensitivity_analysis.py' -v
python -m unittest discover -s test -p 'test_system_holdout_analysis.py' -v
python -m unittest discover -s test -p 'test_element_pair_analysis.py' -v
```

The synthetic snapshot generator writes `records.tsv`, `records.jsonl` and
`snapshot.toml` (`examples/mp_recovery/make_snapshot.jl:1-41`;
`src/mp_snapshot.jl:83-152`). The audit writes grouped/excluded records and audit
metadata (`docs/mp-pilot.md:69-95`). Splitting writes composition-only ranker
inputs separately from evaluator labels (`src/mp_recovery.jl:199-320`). PU
evaluation writes complete rankings, metrics, provenance and runtime
(`src/mp_pu.jl:250-347`). The Python analyser independently validates saved
membership, order, popularity and metrics (`scripts/analyze_pu_pilot.py:1-10`).

### Research workflow map and status

| Workflow | What it measures | Runner | Documentation | Status from project docs |
| --- | --- | --- | --- | --- |
| Binary labelled ranking | Supplied scores versus score-independent random and training-element-popularity baselines on an explicit labelled pool. | `eka benchmark` (`src/benchmark.jl:212-259`) | `docs/benchmarking.md` | Software workflow complete; supplied labels/scores remain the experimenter's responsibility (`docs/benchmarking.md:3-7`, `docs/benchmarking.md:26-54`). |
| MP recovery pilot | Recovery of held-out compositions with experimental provenance using random, training-only popularity and maximum training-composition similarity. | `eka audit-mp`, `eka split-mp`, `eka benchmark-pu`; `scripts/analyze_pu_pilot.py` | `docs/mp-pilot.md`, `docs/mp-recovery-splits.md`, `docs/mp-pu-evaluation.md`, frozen `docs/mp-recovery-protocol.md` | All 20 real splits, three methods and four budgets completed and reproduced locally; detailed outputs remain local (`docs/mp-pilot-reproduction.md:1-7`, `docs/mp-pu-evaluation.md:10-16`). |
| Label sensitivity | Evaluation-only and full-pipeline changes under original, exclude-mixed and unlabel-mixed positive-label policies. | `scripts/run_label_sensitivity.jl`; `scripts/analyze_label_sensitivity.py` | `docs/mp-label-sensitivity.md`, frozen `docs/mp-label-sensitivity-protocol.md` | Full local experiment and exact reproduction complete; outputs ignored under `reports/local/` (`docs/mp-label-sensitivity.md:1-14`). |
| Chemical-system holdout | Formula holdout versus whole-system holdout across all three full-pipeline label policies. | `scripts/run_system_holdout.jl`; `scripts/analyze_system_holdout.py` | `docs/mp-system-holdout.md`, frozen `docs/mp-system-holdout-protocol.md` | Frozen real run and complete separate-checkout reproduction preserved locally (`docs/mp-system-holdout.md:71-87`). |
| Element-pair comparator | A fixed rank-four nonnegative factor model fitted to training non-O element-pair counts. | `scripts/run_element_pair.jl`; `scripts/analyze_element_pair.py`; synthetic gate `scripts/run_pair_feasibility.jl` | `docs/mp-element-pair.md`, frozen `docs/mp-element-pair-protocol.md`, `docs/mp-learned-feasibility.md`, `docs/mp-learned-decision.md` | Frozen evaluation and same-platform exact refit reproduction complete; records, rankings, factors and environments remain local (`docs/mp-element-pair.md:31-74`). |

The ordered benchmark series is complete locally. Further tuning or a larger model
requires a new question and prospective protocol (`docs/recovery-roadmap.md:36-49`,
`docs/recovery-findings.md:104-121`). Sharing review for any record-level bundle
remains separate (`docs/publication-permissions.md:74-89`).

### Commands exercised during recon

On 2026-09-04 a fresh temporary directory was used to run the binary benchmark,
synthetic snapshot/audit/split/pilot, independent pilot analysis, all three
subsequent research runners, and all three independent analysers. All commands
completed successfully. The chain produced 10 binary candidates, 87 synthetic
records grouped into 55 positive, 21 unlabelled and one unresolved composition,
two splits, 12 pilot metric rows, 72 sensitivity rows, 72 system-holdout rows and
24 element-pair rows. Those counts describe this compact software check only.

```bash
readme_run=$(mktemp -d /tmp/eka-readme-recon.XXXXXX)
julia --startup-file=no --project=. bin/eka benchmark --input examples/benchmark/candidates.tsv --training examples/benchmark/training.tsv --methods score,random,popularity --budget 2 5 10 --seeds 0 1 2 --source 'Synthetic software example v1; arbitrary scores and outcomes, disjoint hand-authored pools' --output "$readme_run/binary"
julia --startup-file=no --project=. examples/mp_recovery/make_system_snapshot.jl "$readme_run/snapshot"
julia --startup-file=no --project=. bin/eka audit-mp --snapshot "$readme_run/snapshot" --output "$readme_run/audit"
julia --startup-file=no --project=. bin/eka split-mp --snapshot "$readme_run/snapshot" --audit "$readme_run/audit" --output "$readme_run/splits" --synthetic --seeds 0 1 --budget 1 4
julia --startup-file=no --project=. bin/eka benchmark-pu --splits "$readme_run/splits" --snapshot "$readme_run/snapshot" --audit "$readme_run/audit" --output "$readme_run/pilot" --synthetic
python3 scripts/analyze_pu_pilot.py "$readme_run/pilot" "$readme_run/pilot-analysis"
julia --startup-file=no --project=. scripts/run_label_sensitivity.jl "$readme_run/snapshot" "$readme_run/audit" "$readme_run/pilot" "$readme_run/sensitivity" --synthetic
python3 scripts/analyze_label_sensitivity.py "$readme_run/sensitivity" "$readme_run/sensitivity-analysis"
julia --startup-file=no --project=. scripts/run_system_holdout.jl "$readme_run/snapshot" "$readme_run/audit" "$readme_run/sensitivity" "$readme_run/system" --synthetic
python3 scripts/analyze_system_holdout.py "$readme_run/system" "$readme_run/system-analysis"
julia --startup-file=no --project=. scripts/run_element_pair.jl "$readme_run/snapshot" "$readme_run/audit" "$readme_run/system" "$readme_run/pair" --synthetic
python3 scripts/analyze_element_pair.py "$readme_run/pair" "$readme_run/pair-analysis"
```

## Documentation inventory

The repository contains 27 Markdown documents under `docs/`. “Linked” means the
current `README.md` contains a direct link to that file.

| Document | Summary | Linked? | Evidence |
| --- | --- | --- | --- |
| `docs/audit-hardening-compatibility.md` | Confirms hardened snapshot/source audits preserve the frozen v1 scientific evidence. | No | lines 1-57 |
| `docs/benchmarking.md` | Defines the binary-labelled fixed-budget inputs, methods, metrics, report format and rerun API. | Yes | lines 1-137 |
| `docs/design.md` | Records the separation of querying, importing and benchmarking plus SQLite engineering choices. | Yes | lines 1-34 |
| `docs/mp-data-provenance-review.md` | Historical MP provenance review, superseded where noted by the later terms/permissions records. | Yes | lines 1-87 |
| `docs/mp-element-pair-protocol.md` | Frozen prospective contract for the rank-four element-pair comparator. | No | lines 1-122 |
| `docs/mp-element-pair.md` | Gives element-pair execution, output and exact local reproduction evidence. | Yes | lines 1-75 |
| `docs/mp-external-score-provenance.md` | Records why external Seko scores fail the primary pilot's training-independence gate. | Yes | lines 1-113 |
| `docs/mp-label-sensitivity-protocol.md` | Frozen contract for evaluation-only and full-pipeline positive-label policies. | No | lines 1-164 |
| `docs/mp-label-sensitivity.md` | Gives label-sensitivity runners, outputs and exact local reproduction status. | Yes | lines 1-120 |
| `docs/mp-learned-decision.md` | Records the go decision for one fixed element-pair evaluation. | No | lines 1-46 |
| `docs/mp-learned-feasibility.md` | Defines the element-pair model and its feasibility gate before the scientific protocol was frozen. | No | lines 1-130 |
| `docs/mp-pilot-reproduction.md` | Records the frozen v1 pilot environment, restore process and completed checks. | Yes | lines 1-112 |
| `docs/mp-pilot.md` | Defines MP export, audit, scope, provenance grouping and offline verification. | Yes | lines 1-177 |
| `docs/mp-pu-evaluation.md` | Defines split verification, three PU methods, metrics, reports and synthetic pipeline. | Yes | lines 1-231 |
| `docs/mp-recovery-protocol.md` | Historical frozen pre-evaluation scientific contract for the v1 recovery pilot. | Yes | lines 1-228 |
| `docs/mp-recovery-splits.md` | Defines composition-safe membership generation and its provenance/file contract. | Yes | lines 1-189 |
| `docs/mp-system-holdout-protocol.md` | Frozen prospective contract for composition versus whole-system holdout. | No | lines 1-156 |
| `docs/mp-system-holdout.md` | Gives system-holdout execution, diagnostics and completed local reproduction evidence. | Yes | lines 1-87 |
| `docs/mp-terms-evidence.md` | Records the supplied/live MP terms, CC BY 4.0 handling and remaining artifact review. | Yes | lines 1-69 |
| `docs/one-week-roadmap.md` | Preserves the original pilot schedule and its subsequently completed checklist. | Yes | lines 1-185 |
| `docs/performance.md` | Records local fixture and production SQLite timing methodology and observations. | Yes | lines 1-47 |
| `docs/production-validation.md` | Records the read-only audit and reference queries against the external Seko database. | Yes | lines 1-67 |
| `docs/publication-permissions.md` | Separates software, dependency and data rights by artifact and lists open data-bundle actions. | Yes | lines 1-89 |
| `docs/recovery-findings.md` | Summarises all completed methods, limitations, attribution and the reassessment decision. | Yes | lines 1-121 |
| `docs/recovery-roadmap.md` | Tracks the ordered recovery programme, now complete locally, and gates any future experiment. | Yes | lines 1-214 |
| `docs/release-readiness.md` | Defines and records the passing source-only archive release gate. | Yes | lines 1-56 |
| `docs/session-summary-2026-08-31.md` | Historical session record of the pilot, sensitivity, system holdout, licensing and later comparator work. | No | lines 1-164 |

The README correctly frames `docs/mp-recovery-protocol.md` as a historical
pre-evaluation freeze: the document itself says it was frozen before ranking and
its status text reflects the freeze-date implementation state
(`README.md:104-107`; `docs/mp-recovery-protocol.md:1-9`). The original
`docs/one-week-roadmap.md` also explicitly says it schedules work rather than
asserting implementation, and its closing update says the plan completed on
31 August 2026 (`docs/one-week-roadmap.md:1-9`, `docs/one-week-roadmap.md:160-175`).

## Data, attribution and licensing

| Topic | Required fact | Evidence |
| --- | --- | --- |
| Bundled data | The source archive contains synthetic examples/tests and the noticed tiny fixture. It does not contain a production Seko database, MP snapshot, candidate-level rankings, factors or a complete dependency environment. | `docs/release-readiness.md:3-19`; `THIRD_PARTY_NOTICES.md:30-35` |
| Tiny fixture | `test/fixtures/tiny_test.db` has 12 rows: eight match Seko README examples and four are project-authored tests. The reused pairs are software checks, not Eka predictions. | `README.md:33`; `THIRD_PARTY_NOTICES.md:6-35`; direct SQLite count during recon returned 12 |
| Seko notice | The eight reused pairs retain the upstream BSD 3-Clause notice. The notice does not clear redistribution of the full database or underlying ICSD, ICDD or Springer Materials records. | `THIRD_PARTY_NOTICES.md:30-67` |
| Production database | The separately obtained `recommender-2024-07-01.sqlite` has 4,736,551 records in `data2`, `data3`, `data4ionic` and `data5ionic`; 21,928 are unsupported by the current symbol contract. It stays outside Git and was opened read-only. | `docs/production-validation.md:1-28` |
| Materials Project source | The research used MP database version 2026.04.13, retrieved 31 August 2026 at 12:16:39 UTC. Eka normalised/grouped compositions, applied labels/holdouts and computed scores/metrics; GNoME was excluded. | `docs/recovery-findings.md:88-100` |
| MP licence/attribution | Reviewed MP terms allow API analysis and covered Content under CC BY 4.0 with credit, licence link, retained notices and change indication. They prohibit implying endorsement. | `docs/mp-terms-evidence.md:18-32` |
| MP limits | MP identifiers do not grant rights to underlying ICSD/Pauling records. Any record-level data/results bundle still needs file-specific exception, credential, provenance and attribution review. | `docs/mp-terms-evidence.md:41-53`, `docs/mp-terms-evidence.md:55-69`; `docs/publication-permissions.md:74-89` |
| Git exclusions | SQLite/database files except the tiny fixture, `Manifest.toml`, coverage, local data/reports, MP virtual environment and environment-secret files are ignored. | `.gitignore:1-23` |
| MIT scope | MIT covers original Eka code, documentation and original test material. It does not relicense MP/Seko datasets, third-party records, derivatives, dependencies or a complete runtime. | `LICENSE:1-20`; `THIRD_PARTY_NOTICES.md:1-4`, `THIRD_PARTY_NOTICES.md:69-81`; `docs/publication-permissions.md:7-24` |

The following Seko citation request must be preserved verbatim from the current
README (`README.md:346-350`):

> For academic use of the Seko database, its authors request citation of:
> A. Seko, H. Hayashi, H. Kashima, and I. Tanaka, “Matrix- and tensor-based recommender
> systems for the discovery of currently unknown inorganic compounds,”
> *Physical Review Materials* **2**, 013805 (2018).
> [DOI: 10.1103/PhysRevMaterials.2.013805](https://doi.org/10.1103/PhysRevMaterials.2.013805).

The Materials Project attribution to preserve verbatim comes from the current
README (`README.md:336-339`):

> **Materials Project:** the recovery pilot and label-sensitivity experiments use
> an API snapshot from [Materials Project](https://materialsproject.org/), with
> grouping, splits and ranking implemented in EkaCompositions. Seko's scores are excluded
> from these comparisons; see the [score provenance review](docs/mp-external-score-provenance.md).

The database version, retrieval time, GNoME exclusion, non-endorsement statement,
CC BY basis and Jain et al. reference come from the tracked aggregate findings
(`docs/recovery-findings.md:90-100`).

## Freshness diff

| README claim | Repository reality | Result | Evidence |
| --- | --- | --- | --- |
| Package is `EkaCompositions.jl`; CLI is `eka`. | Project, module and entry point agree. | Current | `README.md:7-11`; `Project.toml:1`; `src/EkaCompositions.jl:4`; `bin/eka:1-5` |
| Requires Julia 1.10+. | Compat is `julia = "1.10"`; CI tests 1.10 and current stable. | Current | `README.md:17`; `Project.toml:27`; `.github/workflows/ci.yml:21-41` |
| Python 3.11+ is used for independent validators. | CI selects Python 3.11; analysers use `tomllib`, available in Python 3.11. | Current | `README.md:94-95`, `README.md:267-269`; `.github/workflows/ci.yml:8-20`, `.github/workflows/ci.yml:42-58`; `scripts/analyze_pu_pilot.py:1-16` |
| Quick-start fixture query prints five stated rows. | Exact command reproduced the exact five rows during recon. | Current | `README.md:15-31`; `test/test_cli.jl:55-67`; recon execution |
| Fixture has 12 rows, eight reused Seko examples and four original cases. | Direct SQLite count returned 12; notices enumerate the eight reused rows and describe the other four. | Current | `README.md:33`; `THIRD_PARTY_NOTICES.md:6-35`; recon SQLite query |
| Production snapshot contains 4,736,551 rows and supported legacy tables. | The production audit totals the same count across the same four tables. | Current | `README.md:43`; `docs/production-validation.md:1-19` |
| Commands table lists the CLI. | Query mode and all six dispatched subcommands are present. | Current | `README.md:109-125`; `src/cli.jl:52-60` |
| Query option names/defaults. | All seven query options and defaults match the parser; there is no result-limit option. | Current | `README.md:127-143`; `src/cli.jl:10-42` |
| Pilot has 20 splits, three methods and four budgets and was reproduced. | Frozen pilot record states the same completed grid and reproduction. | Current | `README.md:78-88`; `docs/mp-pilot-reproduction.md:1-7` |
| Label sensitivity has 1,440 metrics and is reproduced. | Six branches × 20 splits × three methods × four budgets; exact reproduction complete. | Current | `README.md:85`; `docs/mp-label-sensitivity.md:1-14`, `docs/mp-label-sensitivity.md:46-51`, `docs/mp-label-sensitivity.md:90-94` |
| System holdout has 1,440 metrics and is reproduced. | Workflow and evidence document state 1,440 rows and exact local reproduction. | Current | `README.md:86`; `docs/mp-system-holdout.md:42-49`, `docs/mp-system-holdout.md:71-83` |
| Element-pair evaluation has 480 new metrics and exact refit reproduction. | Workflow states 480 rows and exact same-platform refit reproduction. | Current | `README.md:87`; `docs/mp-element-pair.md:46-57`, `docs/mp-element-pair.md:72-75` |
| Real data/details remain outside Git “pending final release review”. | Data remain outside Git, but the source-only final review is complete. A separate record-level bundle still requires artifact-specific review. | Stale wording | `README.md:13`; `docs/release-readiness.md:44-56`; `docs/publication-permissions.md:74-89` |
| Sharing row says the source-release review passes locally. | The tracked gate says the source archive is ready; CI also runs it on pushes/PRs. The README understates the completed release state. | Stale wording | `README.md:88`; `docs/release-readiness.md:21-56`; `.github/workflows/ci.yml:8-20` |
| Recovery work is described with a “Day N” milestone table. | The facts remain accurate, but `docs/recovery-roadmap.md` says the ordered benchmark work is complete locally. The day-based table is development history. | Accurate but poorly framed | `README.md:78-88`; `docs/recovery-roadmap.md:12-49` |
| Frozen recovery protocol is historical and its unavailable-command statements reflect freeze date. | The protocol labels itself frozen before evaluation and retains its old implementation-status statement. | Current | `README.md:104-107`; `docs/mp-recovery-protocol.md:1-9` |
| Every path in the Layout table exists. | All 28 listed files were checked and exist. | Current | `README.md:298-317`; repository path checks during recon |
| Internal Markdown links resolve. | All 19 unique local Markdown targets in the README exist. | Current | `README.md`; repository path checks during recon |
| External README URLs are live. | GitHub CI and Seko URLs returned HTTP 200. DOI and Materials Project returned HTTP 403 to automated requests, so reachability could not be confirmed by this check. | Partly unconfirmed | `README.md:279`, `README.md:336-350`; recon HTTP checks |
| Citation matches package metadata. | README contains source citations but no concise software-citation section. `CITATION.cff` identifies Eka v0.1.0 by Joshua Corbett and has no DOI. | Missing README summary | `README.md:331-363`; `CITATION.cff:1-20` |

No `.zenodo.json`, docs deployment, coverage workflow or Codecov configuration was
found. Therefore no DOI, docs or coverage badge is justified (repository search;
`.github/workflows/ci.yml:1-58`; `.github/workflows/TagBot.yml:1-16`).

## Draft TODOs

None. Every fact needed by `README.draft.md` was verified during recon.

## Caveat preservation map

The following caveat-bearing statements were removed from their old positions or
compressed. Each has an equivalent in the named draft section.

| Current README sentence(s) cut or consolidated | Draft destination |
| --- | --- |
| “It does not establish stability, synthesizability, or experimental validity.” (`README.md:13`) | **Scope and limitations**, bullets 2 and 4 |
| “The Materials Project pilot, label-sensitivity analyses, system-holdout comparison and element-pair evaluation have been run and reproduced locally; data and detailed results remain outside Git pending final release review.” (`README.md:13`) | **Benchmarks**, status table, corrected to artefact-specific review |
| “They are not predictions generated by Eka.” (`README.md:33`) | **Scope and limitations**, synthetic-output bullet; **Citation, authorship and data sources**; **Licence** |
| “Installation downloads Julia dependencies; queries and tests need no network access after installation.” (`README.md:33`) | Cut as setup detail; offline behaviour remains demonstrated by **Quick start**, **Pipeline overview**, and the synthetic benchmark commands |
| “Some rows use unsupported isotope notation such as `D`; strict queries that encounter those rows fail rather than silently changing or dropping them.” (`README.md:43`) | **Library usage**, composition rules; **Database contract** strict-validation sentence; production details linked |
| “No production database is bundled, and SQLite queries do not download or modify one.” (`README.md:43`) | **Database contract** and **Licence** |
| “Local production databases are ignored by Git.” (`README.md:43`) | **Licence**, via publication-permissions link; full fact retained in `readme-notes.md` data table |
| “Verify data-source permissions before redistributing derivatives.” (`README.md:43`) | **Licence** |
| “This evaluates supplied rankings; it does not train a predictive model or establish stability or synthesizability.” (`README.md:64-65`) | **Scope and limitations**, bullet 2 |
| “The example labels are arbitrary software fixtures.” (`README.md:65`) | **Scope and limitations**, synthetic-output bullet |
| “Unobserved compounds are not negative outcomes, and upstream scores must be generated without evaluation leakage.” (`README.md:66-67`) | **Scope and limitations**, bullet 3 |
| “Its initial scope is oxygen-containing ternaries; oxide chemistry is not yet validated.” (`README.md:72-74`) | **Scope and limitations**, bullet 4 |
| “Unlabelled compositions are not confirmed negatives and must not be supplied as failed outcomes to the separate binary benchmark above.” (`README.md:74-76`) | **Scope and limitations**, bullets 3 and 4 |
| “Real snapshots and detailed derived reports remain local and ignored by Git.” (`README.md:100-102`) | **Benchmarks**, locked status row |
| “The supplied MP terms support preparation of attributed results and covered data under CC BY 4.0.” (`README.md:102-103`) | **Citation, authorship and data sources**, verbatim MP attribution; **Licence** |
| “The frozen protocol is a historical pre-evaluation record: statements there about unavailable commands describe the freeze date, not the current CLI.” (`README.md:105-107`) | Removed from scan path; historical framing remains in `readme-notes.md` and the draft links current workflow guides rather than presenting the old status as current |
| “Explicit `-n` with no values matches nothing; explicit `-e` with no values imposes no element restriction.” (`README.md:139`) | **Commands**, query-option defaults; detailed edge case remains discoverable through `--help` and recon notes |
| “Symbols are case-sensitive: `Mg` is valid, `mg` is not. Matching uses parsed symbols: asking for `N` does not match `Na`.” (`README.md:139`) | **Library usage**, valid-symbol rule; exact filtering detail retained in parser/library recon notes |
| “Output rounding does not affect ordering or threshold comparisons. No results produces just the header. Invalid input/database errors go to stderr with exit code 2; success and help return 0. There is no result limit.” (`README.md:141`) | Removed from overview; verified CLI contract retained in `readme-notes.md`; **Commands** points to `--help` |
| “The threshold always applies to the stored score. Legacy ionic-only coverage and unavailable arities are reported on stderr; stdout stays machine-readable.” (`README.md:143`) | **Commands**, threshold row; **Database contract**, legacy coverage; detailed stream behaviour retained in recon notes |
| “Normalization intentionally loses the original formula order and overall scale. This represents composition ratios, not molecular identity or crystal structure.” (`README.md:175`) | **Library usage**, rules; **Scope and limitations**, bullet 1 |
| “SQLite queries retain two database rows that normalize to the same composition as separate scored records; scores are not silently averaged or deduplicated.” (`README.md:175`) | Removed from overview; exact return contract remains in `readme-notes.md` library table and `docs/design.md` |
| “The MP recovery workflow instead groups records by canonical composition before splitting, so equivalent formulas cannot cross the training/candidate boundary.” (`README.md:175`) | **Pipeline overview** and linked split guide |
| “Mixing unrelated matching tables is an error rather than an arbitrary choice.” (`README.md:179`) | **Database contract**, strict validation; implementation detail moved to linked design/production docs |
| “These labels describe source coverage, not a new chemical classification performed by this package.” (`README.md:189`) | **Scope and limitations**, MP classification bullet; **Database contract** |
| “Ordinary queries are not full-file integrity audits. Missing files are never created by the query API.” (`README.md:191`) | **Database contract** |
| “We do not add indexes to user databases.” (`README.md:193`) | Moved to linked `docs/design.md` and `docs/production-validation.md` from **Database contract** |
| “Rows excluded by the SQL threshold are not a whole-dataset validation pass. Scores must be finite numbers, but are not constrained to `[0, 1]`: the source model determines their interpretation.” (`README.md:195`) | **Database contract**, strict formula/finite-score statement; full detail retained in linked production docs and recon notes |
| “Reference similarity here compares each candidate with one supplied formula; it is not the PU comparator...” (`README.md:199-204`) | **Pluggable ranking**, explicit separation of SQLite and PU interfaces |
| “It does not use learned embeddings, oxidation states, or tensor factors, and is not a probability or a chemical-substitution model.” (`README.md:214`) | **Scope and limitations**, similarity bullet |
| “This pipeline imports existing numeric scores; it does not train a model or generate predictions from unscored compounds.” (`README.md:228`) | **Scope and limitations**, stored-score bullet; `import` purpose in **Commands** |
| “Canonical duplicates fail by default... there is no silent aggregation.” (`README.md:247`) | `import --duplicates` default preserved in recon notes; duplicate/ratio behaviour remains in **Library usage** and linked design notes |
| “Existing files, including the supplied production database, are never overwritten. This is a rebuild workflow, not an append/upsert API.” (`README.md:249`) | `import` described as building a new database in **Commands**; linked design notes retain publication details |
| “Unsupported does not mean scientifically invalid... They are neither mapped to hydrogen nor silently skipped.” (`README.md:261`) | **Library usage**, unsupported isotope rule; **Database contract**, strict validation; linked production validation |
| “Routine tests require neither production data nor API credentials.” (`README.md:271`) | **Development** uses repository tests; data absence and local handling are in **Licence** |
| “A new CLI invocation starts a new Julia process. It is not equivalent to a second function call in an existing process.” (`README.md:294`) | Moved to linked **performance notes** from **Development** |
| “Warm measurements can benefit from OS file caching. Fixture measurements are not evidence of production-dataset performance.” (`README.md:296`) | Moved to linked **performance notes**; **Scope and limitations** retains synthetic-evidence boundary |
| “Further model development requires a new question and prospective design...” and “External scores stay outside the primary comparison until a new protocol version can establish training independence.” (`README.md:321-324`) | **Benchmarks**, in-progress status; **Scope and limitations**, external-score bullet |
| “Isotope representation and additional scored-source adapters remain separate backlog items.” (`README.md:324-326`) | Removed as development history; roadmap link follows **Repository layout** |
| “Full Seko/tensor reproduction and production model deployment remain out of scope.” (`README.md:326-327`) | **Scope and limitations**, stored-score and external-score bullets |
| “Eka supports its schema and query conventions; it does not bundle their Python script or implement their tensor model.” (`README.md:340-344`) | **Scope and limitations** and **Licence**; Seko attribution remains verbatim |
| “Preserve Materials Project source/version information and applicable citations when using MP data.” (`README.md:351-352`) | **Citation, authorship and data sources**, verbatim MP attribution |
| “MIT does not grant redistribution rights over Materials Project or Seko datasets, third-party records, or data-derived artifacts.” (`README.md:359-362`) | **Licence**, expanded to cover dependencies and runtime bundles |
| “Scientific citation requests do not add conditions to MIT.” (`README.md:363`) | Consolidated into **Licence** and the separation between citation/data-source text and MIT scope |
