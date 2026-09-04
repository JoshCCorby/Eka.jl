# Verified positive–unlabelled recovery evaluation

`eka benchmark-pu` is separate from the existing binary `eka benchmark`. It
verifies saved split bundles, then evaluates every declared method at every
declared budget: random, training-only element popularity, and maximum
training-composition similarity. Joshua Corbett is the author of this
implementation and documentation.

All three primary methods declared by the protocol are implemented. The full real
pilot has now completed after the implementation freeze, with all scientific
outputs reproduced exactly from a clean checkout. Results remain local; see the
[evidence and restore guide](mp-pilot-reproduction.md).
External scores are **not** a method here; the
[external score review](mp-external-score-provenance.md) records that decision.
The [frozen protocol](mp-recovery-protocol.md) remains the unchanged pre-evaluation
record; its statement that the CLI was not yet available describes the freeze date.

## Offline end-to-end example

Run from the repository root with installed Julia dependencies. No Python,
MP client, API key, or private data is required for this core pipeline. Every
output directory must be new; change the names when repeating this example.

```sh
mkdir -p reports/local
julia --project=. examples/mp_recovery/make_snapshot.jl reports/local/pu-example-snapshot
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

The example has 20 splits, three methods and two budgets, producing 120 metric
rows. Every split contains eight training positives, two held-out positives and
four candidates. These arbitrary fixtures test software, not physical
plausibility. All three methods use identical candidate membership within each
split.

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
using EkaCompositions

training = ["CaTiO3", "BaTiO3"]
candidates = ["MgTiO3", "SrTiO3", "CaZrO3", "MgAl2O4"]
ranked = pu_rank(training, candidates; method="similarity",
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

Similarity scores each candidate by the **maximum** cosine similarity of its
reduced element-count vector to any single training composition:
`max(dot(c,t) / (norm(c) * norm(t)) for t in training)`, clamped to [0,1]. It is
the pairwise cosine Eka's `similarity` already computes, maximised over the
training set; the tests assert exact Float64 equality with that function rather
than a tolerance. No reference is chosen using held-out labels, there is no atom
weighting, learned embedding, oxidation feature, fitting step, or search over
similarity variants, and the stored-score tie breaker of the SQLite
`SimilarityRanking` path is **not** inherited. Ordering uses the same frozen
score-independent hash tie policy as popularity.

References are rebuilt from the training argument on every call, so per-split
training isolation holds by construction and a candidate's score depends on the
training set alone, never on the rest of the candidate pool. Comparisons are
streamed one candidate at a time: peak working memory is proportional to the
number of compositions, and no candidate-by-training matrix is ever allocated.

Random ranks by the ascending exact SHA-256 key from the protocol, then shared
tie key and formula. It has no fitted numeric score: the saved score cell is
empty, and `random_key` records the exact ordering key. The popularity and
similarity `random_key` cells are empty. All three methods retain `tie_key`, and
none of them consults evaluator labels.

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
| `split-XX/random.tsv`, `popularity.tsv`, `similarity.tsv` | Complete ranks, canonical formulas, scores/keys, and labels attached **after** ranking |
| `report.md` | All metric rows and interpretation limits; prominently identifies synthetic status |
| `runtime.tsv` | Ranking seconds for every method/split, including any first-call compilation |
| `inputs/` | Captured bundle manifests, membership and provenance used by the evaluator |
| `implementation/` | Relevant current code, Project.toml, and Manifest.toml when present |

The writer reserves a new directory exclusively and never overwrites an existing
path. Failure removes only the new directory created by that invocation. Input
bundles and source snapshots are never modified. Exact rerun comparisons exclude
only `runtime.tsv`; scientific outputs and deterministic configuration should
match under the same source bytes, inputs and environment.

The report distinguishes split sensitivity from independent experiments. It does
not claim success merely because one method wins. The paired primary comparison
(similarity minus popularity hits at k=100 on each identical split) is computed
during analysis from these raw per-split rows; `benchmark_pu` deliberately writes
the inputs to that comparison rather than a summary verdict. The implementation
freeze, real experiment, paired report and clean-checkout reproduction are now
complete locally. `scripts/analyze_pu_pilot.py` independently validates saved
outputs and generates the predefined paired and descriptive summaries. The
[data handling restrictions](mp-data-provenance-review.md) still apply.

The follow-on [label-sensitivity workflow](mp-label-sensitivity.md) is separately
versioned and does not change this v1 runner or its scientific outputs. Its
original-policy controls verify exact compatibility with the preserved pilot.

## Runtime and memory

The frozen protocol implies about 35.2 million candidate/training pairs per split
(4,288 training positives x 8,218 candidates). `scripts/benchmark_pu_similarity.jl`
measures that size on generated formulas only; it reads no snapshot, split
bundle, MP record, or label, and produces no recovery result.

```sh
julia --startup-file=no --project=. scripts/benchmark_pu_similarity.jl
```

Measured on Julia 1.12.6, macOS, Apple silicon, 31 August 2026:

| Step | Time | Allocated |
| --- | ---: | ---: |
| Streamed maximum similarity, 35.2M pairs | 0.132 s | 3.2 MiB |
| `pu_rank` similarity, including tie keys and sort | 0.141 s | 21.8 MiB |
| `pu_rank` popularity, same pool | 0.015 s | 20.3 MiB |
| `pu_rank` random, same pool | 0.015 s | 20.9 MiB |

A full candidate-by-training Float64 matrix would need 268.9 MiB per split; the
streamed maximum never allocates one, and most of `pu_rank`'s allocation is the
per-candidate SHA-256 tie and random keys shared by all three methods. At about
0.14 s per split, all 20 splits cost a few seconds, so no batching tier, caching,
or approximation is needed and none was added. These are one machine's numbers,
not a target or a performance claim; record fresh timings alongside a real run.

## Tests

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
```

Tests cover hand-calculated hit/recall/enrichment cases, no hits, full recovery,
exact random expectation, invalid denominators/budgets, golden hash keys and ties,
training-only counts, evaluation-label independence, corrupted bundles including
rewritten checksums, complete split validation before scoring, complete rankings,
CLI behaviour, no-overwrite and deterministic reruns.

Similarity additionally has hand-calculated cosine values, exactly tied scores
resolved by the shared tie policy, agreement to the last bit with Eka's existing
`similarity` over a generated pool, evidence that the score is the maximum over
training rather than the first or last reference, per-split training isolation
(widening and narrowing the training set, and scoring a candidate alone), score
invariance under changed evaluation labels, untouched global RNG state, repeated
identical reruns, and an allocation bound proving no pairwise matrix is built.
GitHub CI also executes the Python fixture → Julia audit → split → PU evaluation
workflow on Linux.
