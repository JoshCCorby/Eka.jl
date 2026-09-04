# Chemical-system holdout workflow

The prospective [v2 protocol](mp-system-holdout-protocol.md) compares random
composition holdout with whole-system holdout on the same MP snapshot, under
all three full-pipeline label policies. It is a separately loaded research
workflow; the original `benchmark-pu` CLI and ranking algorithms are unchanged.

A system is a sorted set of element symbols, independent of stoichiometry.
System holdout assigns a hash-selected fifth of the common system universe to
candidates. All training positives lie outside those systems. Unlabelled groups
outside the selected systems are omitted. This changes pool sizes and prevalence
as well as system overlap; no causal claim isolates chemical separation.

## Running against the frozen inputs

Use the saved full-pipeline sensitivity results, not evaluation-only metrics.
All output directories must be new. No API request or credential is needed.
From the repository root:

```sh
julia --startup-file=no --project=. scripts/run_system_holdout.jl \
  data/local/mp-ternary-snapshot reports/local/mp-ternary-audit \
  reports/local/mp-label-sensitivity-v1-2026-08-31/results \
  /absolute/path/to/new-preflight --preflight

julia --startup-file=no --project=. scripts/run_system_holdout.jl \
  data/local/mp-ternary-snapshot reports/local/mp-ternary-audit \
  reports/local/mp-label-sensitivity-v1-2026-08-31/results \
  /absolute/path/to/new-results

python3 scripts/analyze_system_holdout.py \
  /absolute/path/to/new-results /absolute/path/to/new-analysis
```

The preflight checks all memberships and budget feasibility before any new
ranking. The full run verifies the source by reaudit and frozen hashes, captures
baseline files, reconstructs every composition control, and compares its
membership, scores, order and metrics with the saved full-pipeline sensitivity.
It also checks shared-candidate score/order invariance under the alternative
label policies. Rankers receive only training/candidate compositions.

Outputs contain 1,440 metric rows, 360 rankings, 120 population rows and 360
similarity summaries, with per-candidate maximum similarities. All seeds,
methods, budgets and labels are retained; runtime is separate from deterministic
artifacts. `config.toml` inventories captured source, implementation, baseline
and result bytes. The independent Python analyzer reconstructs membership,
random/popularity scores, ordering, metrics, positive-system concentration and
similarity summary statistics. A separate complete Julia rerun checks full
similarity-score reproduction.

## Offline verification

```sh
julia --startup-file=no --project=. test/runtests.jl
python3 -m unittest discover -s test -p 'test_system_holdout_analysis.py' -v
```

The Python tests create a synthetic snapshot with unequal system sizes, mixed
labels and an unlabelled-only system, then execute the entire workflow. They
reject corruption even when a result-file checksum is rewritten. Synthetic
results are software tests, not scientific evidence. The generator is
`examples/mp_recovery/make_system_snapshot.jl`; custom seeds/budgets are allowed
only in explicitly synthetic runs.

The tracked protocol is immutable after its freeze; fixes to code must preserve
its scientific contract and require revalidation/rerunning affected outputs.
A design change needs a new protocol identity. Keep the original pilot and
sensitivity evidence untouched. The separate [terms review](mp-terms-evidence.md)
governs preparation of attributed results and any later data release.

## Completed evidence

The frozen real run and complete separate-checkout reproduction are preserved
under `reports/local/mp-system-holdout-v2-2026-08-31/`. Its `REPORT.md` links every
primary split, all secondary budgets, method means and population/similarity
diagnostics. `verify_evidence.py` verifies the local inventory and all 1,472
deterministic outputs, the complete config and seven analysis files against the
rerun. Reproduction used the same platform and existing package depot; no
cross-platform or empty-depot claim is made.

All 4,530 Julia checks and 26 Python checks passed before real scoring. The
composition controls reproduce the earlier full-pipeline sensitivity results;
the original sealed pilot and sensitivity inventories remain unchanged.
At the completion of this system-holdout study, the learned comparator remained
a specification/feasibility decision. The subsequent [element-pair evaluation](mp-element-pair.md)
completed that gate and a separate frozen comparison; it does not alter this
study or its original results.
