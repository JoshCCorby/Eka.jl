# Label-sensitivity workflow and reproduction

The [label-sensitivity protocol](mp-label-sensitivity-protocol.md) was frozen on
31 August 2026 after the original pilot report and before alternative-policy
results. The full local experiment and exact reproduction are complete. Scientific
outputs remain ignored by Git under
`reports/local/mp-label-sensitivity-v1-2026-08-31/`; start with its `REPORT.md`.

The original v1 protocol, scoring definitions and preserved run remain unchanged.
An explicit ID-to-file-and-hash registry now supports both frozen protocols.
The v1 checksum is still
`f64c1fb803da3cc57aff658341b299824e3d662cc48039586a8bc10410bab21f`;
the sensitivity checksum is
`f577444465292b6f1099e2650eec22106aebfb2ce3b970b86a5a037bc578a09f`.

## Entry points

The dedicated research runner loads `src/mp_label_sensitivity.jl` explicitly,
so no new mode or policy is silently added to v1's `benchmark-pu` CLI. It verifies
the snapshot, audit and captured original pilot bundle before running anything
new. Every original ranking, metric and raw report is recomputed and compared
byte for byte as a compatibility check. Evaluation-only branches then consume
the preserved original rankings, retaining their scores and relative order.

```sh
julia --startup-file=no --project=. scripts/run_label_sensitivity.jl \
  data/local/mp-ternary-snapshot \
  reports/local/mp-ternary-audit \
  reports/local/mp-recovery-pilot-v1-2026-08-31/results \
  reports/local/new-label-sensitivity-results
python3 scripts/analyze_label_sensitivity.py \
  reports/local/new-label-sensitivity-results \
  reports/local/new-label-sensitivity-analysis
```

Output directories must not exist. Explicit `--synthetic` is the only optional
runner argument; the input snapshot and original pilot must both be synthetic.
Seeds and budgets come from the verified original bundle, with all real v1
seeds/budgets mandatory. There are no real-data overrides for selecting a subset.

Synthetic end-to-end tests use budgets 1 and 2, because the full excluded-policy
fixture has fewer candidates than the original fixture. The old synthetic v1
example's budget 4 deliberately cannot be silently truncated to fit that branch.
An infeasible declared branch rejects the whole experiment before new rankings.

## Output contract

Six branches combine `evaluation_only` / `full_pipeline` with `original`,
`exclude_mixed`, and `unlabel_mixed`. All real branches have 20 splits, three
methods and four budgets: 1,440 metric rows in total, with 360 complete rankings
and 480 membership files. The original controls deliberately duplicate v1.

- `evaluation_only` keeps original mixed training positives. Exclusion removes
  mixed candidates and compacts ranks; every row retains its original rank and
  metrics record original depth at k. Unlabelling changes evaluation labels only.
- `full_pipeline` reconstructs labels and splits, removes mixed training
  positives under both alternatives, and recomputes scores. Alternatives share
  training/holdouts but have different candidate populations. Common-candidate
  scores and relative ordering agree, as required by the ranking definitions.
- `metrics.tsv` records populations, mixed membership, excluded groups, policy
  counts, every metric denominator, seeds and eligible-budget semantics.
- `config.toml` hashes all deterministic outputs, copied source inputs, baseline
  files, implementation and dependencies. `runtime.tsv` is separate.
- `analysis/` contains independent validation, all paired differences and changes
  from original, all budgets/methods, population tables, and the descriptive report.

The independent Python analyzer reconstructs policy memberships and checks ranks,
fixed-score/order/depth preservation, common-candidate invariance, random keys,
popularity scores, complete metric grids and exact denominators. Full similarity
recomputation is established by the separate Julia rerun, not by pretending the
Python analyzer implements another independent cosine engine.

## Freeze and restore

The experiment used a dirty working tree based on commit
`568ed605c131edfa40695afc53781015c9739f6c`. It did **not** claim that commit alone
contains the sensitivity implementation. The local `implementation-freeze.json`
records every captured tracked/untracked source hash, exact source archive,
binary Git patch, Julia/Python versions, and Project/Manifest hashes. The earlier
`design-freeze.json` records the prospective protocol and original pilot identity.

To restore, create a fresh checkout at the base commit, overlay the captured
`environment/source-tree.tar`, copy its `environment/Manifest.toml`, then use
Julia 1.12.6 and `Pkg.instantiate()` without updating or resolving dependencies.
Verify every captured source hash and ensure the manifest bytes remain unchanged.
The local `REPRODUCE.md` and `reproduction-commands.json` give the exact workflow.
The archive contains project sources, not the original MP snapshot or pilot:
those retained local inputs are still required, with their recorded hashes.

The separate restore used the same macOS arm64 platform and installed dependency
depot. It is not an empty-depot/network-free installation or a cross-platform
bitwise guarantee. All 925 deterministic output files, the config, 1,440 metric
rows and seven analysis files matched exactly. Original v1's sealed evidence
inventory was verified unchanged too. Runtime is intentionally excluded.

## Verification and remaining work

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test(; allow_reresolve=false)'
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
python3 -m unittest discover -s test -p 'test_pu_analysis.py' -v
python3 -m unittest discover -s test -p 'test_label_sensitivity_analysis.py' -v
```

All 4,061 Julia checks, 10 exporter tests, five pilot-analysis tests and four
sensitivity-analysis tests passed before the real run. The restored checkout
also passed the full Julia suite and sensitivity-analysis tests. Tests include
hand-calculated filtering/depth metrics, policy membership, training isolation,
deterministic reruns, original controls, tampering with rewritten checksums,
infeasible budgets and overwrite refusal. CI includes the synthetic workflows;
remote CI execution has not been claimed for these uncommitted changes.

No learned comparator or system holdout has been run. Interpretation and the
next policy-carry-forward decision are in the local report, separate from the
frozen design. [Publication permissions](publication-permissions.md) remain open;
the provider clarification request is drafted but unsent, and no licence was
selected or release performed.
