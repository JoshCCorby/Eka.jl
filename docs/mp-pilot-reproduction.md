# Frozen pilot run and reproduction

The first complete v1 pilot was run locally on 31 August 2026. It used clean
implementation commit `568ed605c131edfa40695afc53781015c9739f6c`, Julia 1.12.6,
and the unchanged [frozen protocol](mp-recovery-protocol.md). All 20 splits,
three methods and four budgets completed. Scientific results and unreviewed
derivatives remain outside Git; this document records the workflow, not a public
release of measured results.

Local evidence directory:
`reports/local/mp-recovery-pilot-v1-2026-08-31/`.
Start with its `REPORT.md`, `freeze.json`, `reproduction-checks.json`, and
`analysis/report.md`. `results/` contains the original evaluator outputs;
`clean-real-results/` contains the separate clean-checkout rerun. The original
snapshot and audit remain in their original local directories and are required.

## Environment decision

Preserve the complete resolved `Manifest.toml` and `Project.toml` with each run,
together with the exact Julia version, platform and source archive. Do not commit
a moving library-wide manifest merely to describe an old experiment. Do not
restore an experiment by resolving `Project.toml` alone or running `Pkg.update()`.
The run's environment directory and freeze record bind the actual lockfile bytes.

The local manifest retains an unused historical `Recommender` package entry at
path `.`. Preserve it unchanged for this run: the clean-checkout restore and tests
established that `Eka` resolves and runs correctly with those exact bytes. This is
an environment record, not an instruction to reintroduce the old package name.

## Restore a fresh checkout

Install Julia **1.12.6** on the recorded platform for exact Float64 comparisons.
Python 3.11+ suffices for standard-library verification; the run records 3.14.6.
No MP API key, exporter dependency environment or new API query is required.
From the repository root, choose a new destination for each execution:

```sh
git clone --no-hardlinks . /tmp/eka-pilot-reproduce
git -C /tmp/eka-pilot-reproduce checkout --detach 568ed605c131edfa40695afc53781015c9739f6c
cp reports/local/mp-recovery-pilot-v1-2026-08-31/environment/Manifest.toml /tmp/eka-pilot-reproduce/Manifest.toml
cd /tmp/eka-pilot-reproduce
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test(; allow_reresolve=false)'
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
```

Check the restored manifest's SHA-256 against `freeze.json` before and after
instantiation. Instantiation may download pinned packages and binary artifacts;
it must not change the lockfile. The observed restore reused the installed Julia
depot; this verifies a clean source checkout, not a network-free or empty-depot
installation. Source and lockfile hashes do not guarantee that upstream packages
will remain available forever. Cross-platform bitwise reproduction was not tested.

Run the [synthetic end-to-end example](mp-pu-evaluation.md) in that checkout first.
Then regenerate all real splits from the preserved original snapshot and audit:

```sh
julia --startup-file=no --project=. bin/eka split-mp \
  --snapshot /absolute/path/to/mp-ternary-snapshot \
  --audit /absolute/path/to/mp-ternary-audit \
  --output /absolute/path/to/new-splits
julia --startup-file=no --project=. bin/eka benchmark-pu \
  --snapshot /absolute/path/to/mp-ternary-snapshot \
  --audit /absolute/path/to/mp-ternary-audit \
  --splits /absolute/path/to/new-splits \
  --output /absolute/path/to/new-results
```

The exact commands actually exercised are preserved as argument arrays in
`reproduction-commands.json`; `reproduction.log` records their completion.

## Checks completed

- Julia: 1,729 tests passed both before the freeze/run and in the clean checkout.
- Offline exporter: 10 tests passed in both environments.
- Clean-checkout synthetic workflow: 20 splits, three methods, two budgets.
- Clean-checkout real workflow: all 80 membership files, 60 full ranking files,
  240 metric rows, and the raw report matched the primary run byte for byte.
- Runtime is intentionally excluded. The sole evaluator configuration difference
  is the split-bundle manifest hash: regenerated bundles capture the newer
  producer implementation. Scientific membership and evaluation implementation
  hashes are identical, as are all deterministic scientific outputs.

`scripts/analyze_pu_pilot.py` was added after the experiment freeze and reads
saved results only. It independently reconstructs seeded membership and labels,
checks ranking permutations, score/tie ordering, random keys, popularity scores,
and all metric denominators and values. Similarity is fully recomputed by the
clean Julia rerun; the Python check only checks its bounds and ordering. The
analysis never changes inputs, scores or labels, and refuses an existing output
directory. Run it from the current source tree, not the earlier frozen commit:

```sh
python3 scripts/analyze_pu_pilot.py /absolute/path/to/results /absolute/path/to/new-analysis
python3 -m unittest discover -s test -p 'test_pu_analysis.py' -v
```

Five additional synthetic checks cover complete recovery, overwrite refusal,
incorrect metrics/scores with rewritten checksums, duplicate ranking entries and
altered membership. Original input provenance remains the frozen Julia loader's
responsibility; this analysis is not a standalone authenticity verifier.

The local analysis records every paired difference, all budgets, all predefined
subgroups and denominators, and exact tie sizes. No confidence intervals,
significance tests, alternative-label experiments, or system holdouts are added.
Plotting is optional and separate from validation: the local `plot_pilot.py` and
captured Python plotting versions produced standalone PNG/SVG figures.

The completed local evidence is protected against ordinary writes and inventoried
by SHA-256. This is an integrity check and operational freeze, not a WORM storage
guarantee: the owner can change file permissions. Preserve the original artifacts
and use new directories for subsequent analyses. Sharing permissions remain
unresolved, including for aggregate results; nothing was published or pushed.
