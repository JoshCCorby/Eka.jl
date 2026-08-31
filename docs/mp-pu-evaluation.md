# Verified positive–unlabelled baseline evaluation

Day 3 adds `eka benchmark-pu`, separate from the existing binary `eka benchmark`.
It verifies saved split bundles, then evaluates random and training-only element
popularity at every declared budget. Joshua Corbett is the author of this
implementation and documentation.

This is a **baseline-only milestone**. The similarity comparator and its primary
paired comparison remain Day 4 work. Real rankings are deferred until the planned
implementation freeze. Synthetic test results are not scientific evidence.
The [frozen protocol](mp-recovery-protocol.md) remains the unchanged pre-evaluation
record; its statement that the CLI was not yet available describes the freeze date.

## Offline end-to-end example

Run from the repository root with Python 3.11+ and installed Julia dependencies.
No MP client, API key, or private data is required. Every output directory must be
new; change the names when repeating this example.

```sh
mkdir -p reports/local
python3 examples/mp_recovery/make_snapshot.py reports/local/pu-example-snapshot
julia --project=. bin/eka audit-mp \
  --snapshot reports/local/pu-example-snapshot \
  --output reports/local/pu-example-audit
julia --project=. bin/eka split-mp \
  --snapshot reports/local/pu-example-snapshot \
  --audit reports/local/pu-example-audit \
  --output reports/local/pu-example-splits \
  --synthetic --budget 1 4
julia --project=. bin/eka benchmark-pu \
  --splits reports/local/pu-example-splits \
  --snapshot reports/local/pu-example-snapshot \
  --audit reports/local/pu-example-audit \
  --output reports/local/pu-example-results \
  --synthetic
```

The example has 20 splits, two methods and two budgets, producing 80 metric rows.
Every split contains eight training positives, two held-out positives and four
candidates. These arbitrary fixtures test software, not physical plausibility.
Both methods use identical candidate membership within each split.

The CLI accepts `--splits`, `--snapshot`, `--audit`, `--output`, and explicit
`--synthetic` mode. Budgets and all three kinds of seed come from the verified
bundle; the evaluator does not offer overrides to select favorable subsets.
Synthetic mode must match both the bundle and the original snapshot. Real mode
is pinned to the preserved real v1 snapshot and all its declared splits/budgets.
Keep real outputs local and do not run them before the experiment freeze.

## Verification before scoring

`load_mp_recovery(bundle, snapshot, audit; synthetic=false)`:

1. Captures and verifies the bundle manifest, frozen protocol, original snapshot
   and audit provenance, and copied provenance files.
2. Verifies the expected split list, counts, algorithm, scope, seeds, budgets,
   implementation-copy hashes, split-manifest hashes, and membership hashes.
3. Reconstructs every expected split from the verified original grouped records
   and compares the exact training/candidate/holdout/label file bytes.
4. Completes validation of **all splits** before any ranker can run.

Updating a corrupted label file and its checksums is insufficient: reconstruction
still detects disagreement with the frozen source. Missing splits, altered seeds,
noncanonical/duplicate memberships, train/pool overlap, and extra manifest file
paths fail validation. Only fixed allowlisted filenames are read from manifest
structures; stored source code is never executed.

Compatibility is based on schema v1, the fixed split algorithm, verified original
inputs and complete membership reconstruction. Historical wrapper/CLI code need
not equal the current evaluator. Preserved source-copy hashes prove internal
integrity, not the authenticity of an unknown producer. Reconstructed membership
and the pinned real source provide the scientific validation; synthetic bundles
make no real-data authenticity claim.

The loader returns separate `inputs` and evaluator-owned `evaluation` fields,
plus captured provenance bytes. This is a software interface boundary, not an OS
sandbox for arbitrary third-party code.

## Ranker and metric interfaces

```julia
using Eka

training = ["CaTiO3", "BaTiO3"]
candidates = ["MgTiO3", "SrTiO3", "CaZrO3", "MgAl2O4"]
ranked = pu_rank(training, candidates; method="popularity",
                 ranking_seed=10000, tie_seed=20260901)
# Arbitrary synthetic heldout example; evaluator data is not passed to pu_rank.
metrics = pu_metrics([r.composition for r in ranked], ["SrTiO3"]; budgets=[1, 4])
```

`pu_rank` accepts only training/candidate compositions, method, ranking seed and
tie seed. No labels, provenance flags, stored scores, source IDs, or bundle paths
are accepted. Duplicate canonical compositions and train/pool overlap fail.

Popularity counts each element once per training composition and scores c as
`sum(training_frequency[e] for e in species(c)) / (length(c) * training_count)`.
Counts are rebuilt per call; unseen elements contribute zero. Oxygen contributes
a constant 1/3 in this ternary pool. Scores are finite Float64 values, ordered
descending with the frozen score-independent hash tie policy.

Random ranks by the ascending exact SHA-256 key from the protocol, then shared
tie key and formula. It has no fitted numeric score: the saved score cell is
empty, and `random_key` records the exact ordering key. Popularity's `random_key`
cell is empty. Both retain `tie_key`. Neither method consults evaluator labels.

`pu_metrics` accepts a complete, duplicate-free ordering and a nonempty held-out
subset. Every holdout must appear in the ordering. Invalid budgets and zero
holdout denominators fail explicitly. It reports:

| Field | Meaning |
| --- | --- |
| `hits` | Held-out positives among the first k candidates |
| `observed_label_fraction` | hits / k; **not** synthesis success rate |
| `heldout_recall` | hits / total holdouts |
| `observed_label_enrichment` | (hits / k) / (holdouts / candidates) |
| `random_expected_hits` | k × holdouts / candidates, shown numerically |
| `random_expected_hits_numerator`, `random_expected_hits_denominator` | The same expectation as an exact reduced fraction |

Uniform-random expectation is analytical sampling without replacement. Individual
hash-based random runs need not equal it. Unlabelled candidates are never assigned
confirmed-negative labels. No specificity, false-positive rate, ordinary negative
accuracy, significance test or population confidence interval is computed.

## Reports and reproducibility

`benchmark_pu(bundle, snapshot, audit, output; synthetic=false)` saves:

| Artifact | Contents |
| --- | --- |
| `config.toml` | Protocol and input hashes, methods/budgets/seeds, runtime versions, source/dependency-file hashes, deterministic output hashes |
| `metrics.tsv` | Every method × split × budget, with raw counts and metric denominators |
| `split-XX/random.tsv`, `popularity.tsv` | Complete ranks, canonical formulas, scores/keys, and labels attached **after** ranking |
| `report.md` | All metric rows and interpretation limits; prominently identifies synthetic/baseline-only status |
| `runtime.tsv` | Ranking seconds for every method/split, including any first-call compilation |
| `inputs/` | Captured bundle manifests, membership and provenance used by the evaluator |
| `implementation/` | Relevant current code, Project.toml, and Manifest.toml when present |

The writer reserves a new directory exclusively and never overwrites an existing
path. Failure removes only the new directory created by that invocation. Input
bundles and source snapshots are never modified. Exact rerun comparisons exclude
only `runtime.tsv`; scientific outputs and deterministic configuration should
match under the same source bytes, inputs and environment.

The report distinguishes split sensitivity from independent experiments. It does
not claim success merely because one baseline wins. Day 5 still needs the full
primary comparison, implementation commit/dependency freeze and real experiment.
The [data handling restrictions](mp-data-provenance-review.md) still apply.

## Tests

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
```

Tests cover hand-calculated hit/recall/enrichment cases, no hits, full recovery,
exact random expectation, invalid denominators/budgets, golden hash keys and ties,
training-only counts, evaluation-label independence, corrupted bundles including
rewritten checksums, complete split validation before scoring, complete rankings,
CLI behaviour, no-overwrite and deterministic reruns. GitHub CI also executes the
Python fixture → Julia audit → split → PU evaluation workflow on Linux.
