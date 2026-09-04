# Fixed-budget ranking experiments

This first milestone evaluates supplied scores against simple baselines on one
explicit, labelled candidate pool. It does not fit Seko's model, generate outcomes,
split a dataset, or claim to establish real discovery performance. The synthetic
example exercises the software only. Its outcomes are arbitrary test labels, **not
claims about the named compounds**.

From the repository root:

```bash
julia --project=. bin/eka benchmark \
  --input examples/benchmark/candidates.tsv \
  --training examples/benchmark/training.tsv \
  --methods score,random,popularity \
  --budget 2 5 10 --seeds 0 1 2 \
  --source "Synthetic software example v1; arbitrary scores and outcomes, disjoint hand-authored pools" \
  --output /tmp/eka-benchmark-demo
```

The output directory must not exist; its parent must exist. No database is changed
and no network access is needed. An input validation failure creates no report.
Writing errors remove the newly created report; abrupt process termination can
leave an incomplete directory. Existing outputs are never overwritten.

## Inputs and experimental responsibility

Candidates are UTF-8 TSV with the exact header `composition<TAB>score<TAB>outcome`.
Each row has a supported simple formula, a finite score, and literal `0` or `1`.
Training is a separate known-positive reference set with the exact single-column
header `composition`. LF and CRLF are accepted; blank lines, extra columns,
quoting, and unknown outcomes are not supported. Both sets must be nonempty.
Canonical duplicates and cross-set overlap are errors, including scaled formulas.

For a real experiment, define the outcome first: for example, a specific measured
criterion or recovery of held-out documented compounds. A missing database entry
is not evidence of an unsuccessful candidate. If only positives and unlabelled
records exist, this binary evaluation protocol is unsuitable without additional
labels; do not turn unlabelled records into negatives.

Construct the training/evaluation split **before** fitting the upstream score
model. Generate scores for the entire declared evaluation pool using training
information only. An old precomputed database may already encode held-out
compounds; disjoint TSVs alone cannot prevent that leakage. Record dataset version,
label definition, split construction, score-model version/training provenance,
and candidate-generation rules in `--source`. The tool records your description
but cannot verify those claims. Do not interpret the `score` method as a validated
Seko reproduction unless you have independently established that provenance.

All methods evaluate the same pool without score thresholds. Choose a chemical
family upstream and record its definition; there is no implicit `--family oxides`
filter or family classification. Results apply to the supplied pool and sampling
scheme, not to all possible chemistry. Verify redistribution rights before sharing
reports: they include full input snapshots and labels.

## Methods

| Method | Ranking | Ties |
| --- | --- | --- |
| `score` | Descending supplied score | Ascending canonical formula |
| `popularity` | Mean training occurrence fraction of the candidate's distinct elements | Ascending canonical formula |
| `random` | Ascending SHA-256 of `eka-random-v1\nSEED\nCANONICAL_FORMULA` | Ascending canonical formula |

Training occurrence counts each element once per unique training composition.
Unseen elements have frequency zero. This is an intentionally simple element
popularity baseline, not a learned substitution or stoichiometry model.
Baselines never consult evaluation outcomes or use supplied scores as tie breakers.
Hash ordering provides a deterministic pseudorandom baseline independent of input
order and global RNG state. Seeds are nonnegative machine-sized integers.
Each random seed is reported separately; deterministic methods run once. Seeds
measure random-baseline variability on this pool, not dataset uncertainty or
confidence intervals. Stronger conclusions require independent splits and datasets.

## Metrics

For budget `k`, select exactly the first `k` unique candidates. Budgets must be
positive and no larger than the pool; the tool never silently clips them.

| Field | Definition |
| --- | --- |
| `hits` | Number of selected candidates with outcome 1 |
| `precision` | Hits / k |
| `recall` | Hits / number of positive candidates in the entire evaluation pool |
| `enrichment` | Precision / positive fraction of the entire evaluation pool |
| `novel_system_fraction` | Fraction selected whose element set is absent from training |
| `unique_system_fraction` | Number of distinct selected element sets / k |
| `element_coverage` | Number of distinct selected elements / number of distinct pool elements |

Recall and enrichment are JSON `null` if the pool contains no positives. Chemical
systems ignore stoichiometry: FeO and Fe2O3 have the same system. Novelty and
unique-system fraction are simple composition-level proxies, not measures of
physical usefulness, chemical distance, or new crystal structures. Every candidate
is composition-disjoint from training, so exact-formula novelty would trivially
equal one; element-set novelty is more informative here.

## Reports and reruns

```text
report/
  config.toml       # parameters, source, input hashes, runtime/package/code versions
  input.tsv        # exact original candidate bytes
  training.tsv     # exact original training bytes
  candidates.csv   # complete rankings, stored scores, method values, labels
  metrics.json     # schema_version=1; per-method/seed/budget results
  benchmark.md     # readable table, definitions, and limitations
```

CSV's seed cell is empty for deterministic methods; JSON uses `null`. For random
rankings the `ranking_value` column contains a hex digest (ascending); other
methods have numeric descending ranking values. Preserve its type when importing.
Reports have no timestamps or absolute paths, so identical inputs/options and
software produce identical files. The benchmark source hash identifies changes
within a package version; preserve the repository revision and Julia environment
as well for archival reproduction. No plots or aggregate significance claims are
generated in this milestone.

Rerun through the library using the saved configuration (with a fresh output path):

```julia
using EkaCompositions, TOML
report = "/tmp/eka-benchmark-demo"
config = TOML.parsefile(joinpath(report, "config.toml"))
benchmark_tsv(joinpath(report, config["input"]),
    joinpath(report, config["training"]), "/tmp/eka-benchmark-rerun";
    source=config["source"], methods=config["methods"],
    budgets=config["budgets"], seeds=config["seeds"])
```

For in-memory experiments, `benchmark_rankings(records, training; budgets, seeds,
methods)` accepts `(formula_or_Composition, score, integer_outcome)` tuples and
training formulas or `Composition` values. It returns canonical inputs, complete
rankings, metrics, and resolved settings without writing files or mutating inputs.

The next milestones can add split generation and model fitting (including a
matrix-factorization baseline), then uncertainty/diversity selection and sequential
reveal/retrain simulations. Those require explicit leakage-safe training adapters;
they are not implemented by this evaluation command.
