# Element-pair comparator: execution and evidence

The [feasibility specification](mp-learned-feasibility.md),
[go decision](mp-learned-decision.md) and frozen
[evaluation protocol](mp-element-pair-protocol.md) define this separate research
workflow. The SQLite CLI and the original three-method evaluators are unchanged.
No new Julia dependency was added.

The model fits a rank-four nonnegative factor matrix to training non-O element
pair counts. Missing pairs receive the declared weak zero-target penalty; they
are not verified-negative compounds. Every candidate receives an association
score, with zero and an explicit flag for an unseen element. Scores cannot
separate stoichiometries within a system. Optimization is deliberately capped at
2,000 iterations, with convergence and cap status reported separately.

## Synthetic demonstration and tests

```sh
julia --startup-file=no --project=. scripts/run_pair_feasibility.jl /absolute/path/to/new-demo
julia --startup-file=no --project=. test/runtests.jl
python3 -m unittest discover -s test -p 'test_element_pair_analysis.py' -v
```

The demonstration accepts only a new output path; it cannot read real input or
label files. It includes a small artificial holdout and a generated 4,288-training,
9,293-candidate size check. Results are software evidence, not research outcomes.
Tests check analytical/finite-difference gradients, nonnegative factors,
deterministic fitting, cold coverage, ties, candidate/evaluation isolation,
corrupted outputs and complete synthetic evaluation.

## Frozen real evaluation

Use the exact original snapshot/audit and preserved v2 results. No API key or new
API query is needed. Output directories must be new:

```sh
julia --startup-file=no --project=. scripts/run_element_pair.jl \
  data/local/mp-ternary-snapshot reports/local/mp-ternary-audit \
  reports/local/mp-system-holdout-v2-2026-08-31/results \
  /absolute/path/to/new-pair-results

python3 scripts/analyze_element_pair.py \
  /absolute/path/to/new-pair-results /absolute/path/to/new-pair-analysis
```

The runner pins the real v2 config hash, verifies its full file inventory and the
original source, and reconstructs all memberships before fitting. Each of the
120 fits receives only training compositions and the fixed settings; no tuning
or test-label selection occurs. The alternatives are refitted independently and
must yield identical factors/traces and shared-candidate scores.

Outputs include 480 metric rows, 120 rankings, pair counts, factors, optimizer
traces, fit diagnostics, captured reference metrics and provenance. The independent
analyzer recomputes every score and the final objective/projected-gradient residual
from factors, reconstructs memberships and metrics, and checks coverage and ties.
The full rerun independently refits every model; matching saved-factor arithmetic
alone is not the refitting check.

## Local evidence and limits

`reports/local/element-pair-evaluation-2026-08-31/` preserves design and
implementation freezes, the source archive, exact Manifest, results, analysis,
reproduction commands and comparison checks. `REPORT.md` links the complete
findings; `REPRODUCE.md` explains restoration. The earlier evidence remains intact.

The tracked [combined findings](recovery-findings.md) retain all four methods and
both favorable and unfavorable comparisons. Real source records, rankings,
factors and environments remain local. A public reader can run the synthetic
workflow; exact real reproduction requires the retained snapshot and baseline
artifacts, which are not distributed in this source repository.

The separate-checkout refit reproduced all 992 deterministic files,
the complete configuration and all six analysis files exactly. Julia tests also
passed in that checkout. The captured Manifest was unchanged. This is same-platform
reproduction using an existing depot, not an empty-depot or cross-platform claim.
