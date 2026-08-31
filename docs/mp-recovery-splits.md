# Composition-safe MP recovery splits

Day 2 implements **membership only**, through `eka split-mp` and the Julia library.
No scoring, recovery metrics, or model evaluation occurs. The existing binary
`eka benchmark` stays unchanged; the [Day 3 PU evaluator](mp-pu-evaluation.md) now consumes these verified bundles.
Joshua Corbett is the author of this implementation and documentation.

The [frozen protocol](mp-recovery-protocol.md) specifies the scientific choices.
This implementation adds no new chemistry filter or ranking-informed decision.
Random composition holdout does **not** ensure unseen chemical systems. Mixed
polymorphs stay grouped; unlabelled compounds remain distinct from negatives.

## Reproduce the preserved real splits

From the repository root, with the original local snapshot and audit:

```sh
julia --project=. bin/eka split-mp \
  --snapshot data/local/mp-ternary-snapshot \
  --audit reports/local/mp-ternary-audit \
  --output reports/local/mp-recovery-splits-v1
```

The output directory must be new and its parent must already exist. All 20 seeds
(0–19) and planned budgets (20, 50, 100, 200) are mandatory for real data. The
budgets are validated against pool size; **no metrics or rankings are calculated**.
Do not re-export MP data to reproduce this experiment. Keep outputs under ignored
`reports/local/`; the [distribution review](mp-data-provenance-review.md) remains
unresolved.

## Offline synthetic example

Python 3.11+ standard library is sufficient to create the fixture; no `mp-api`,
API key, network query, or private data is needed. Julia dependencies must already
be installed. Run from the repository root:

```sh
mkdir -p reports/local
python3 examples/mp_recovery/make_snapshot.py reports/local/recovery-example-snapshot
julia --project=. bin/eka audit-mp \
  --snapshot reports/local/recovery-example-snapshot \
  --output reports/local/recovery-example-audit
julia --project=. bin/eka split-mp \
  --snapshot reports/local/recovery-example-snapshot \
  --audit reports/local/recovery-example-audit \
  --output reports/local/recovery-example-splits \
  --synthetic --budget 1 4
```

This arbitrary software fixture has ten positive, two unlabelled and one
unresolved composition groups, including a mixed-flag polymorph group. Each split
has eight training positives, two held-out positives and four candidates. These
numbers are **synthetic**, not an experimental finding. The unresolved group's
two structures appear in neither training nor candidate membership.

Synthetic mode must be explicit and the snapshot must declare `is_synthetic=true`.
A real snapshot cannot be passed unchanged to `--synthetic`. Synthetic bundles
use `eka-mp-recovery-synthetic-v1`, not the real protocol ID. Only synthetic mode
permits alternative `--seeds` and `--budget` values; duplicates, negatives,
non-integers and oversized budgets are errors. Rerun commands with new directory
names rather than overwriting a previous artifact.

## Julia interfaces

```julia
using Eka

# File API: verifies provenance before saving all frozen real splits.
report = split_mp_recovery(
    "data/local/mp-ternary-snapshot", "reports/local/mp-ternary-audit",
    "reports/local/mp-recovery-splits-library-v1")

# Pure synthetic membership helper: no file/provenance verification is possible here.
groups = vcat([("Li$(i)Na1O1", "positive") for i in 1:10],
              [("MgAl2O4", "unlabelled"), ("BaTiO3", "unresolved")])
result = mp_recovery_splits(groups; seeds=[0, 1], budgets=[1, 3])
split = first(result.splits)
training, candidates = split.inputs.training, split.inputs.candidates
# Only the evaluator may receive these; never pass them into rankers.
heldout, labels = split.evaluation.heldout, split.evaluation.labels
```

The pure helper accepts `(composition, label)` tuples or two-field named tuples;
compositions may be strings or `Composition` values. It canonicalizes first and
rejects duplicates across **all** labels, including proportional formulas. The
caller supplies already-grouped records; it never relabels or combines duplicates
silently. Labels are exactly `positive`, `unlabelled`, or `unresolved`.

For P positives and U unlabelled groups, h = floor(P/5); training is P − h and
candidates are h + U. Require P ≥ 5, U ≥ 1, and every planned budget ≤ h + U.
Unresolved groups are tracked but excluded. Each output list uses canonical
formula order. `evaluation.labels` aligns with the candidate list and uses no
binary negative encoding.

## Determinism and provenance checks

Positive selection uses ascending
`(SHA256("eka-pu-split-v1\n" + decimal_seed + "\n" + canonical_formula), formula)`.
The first h become holdouts. UTF-8, LF delimiters, no trailing newline in the hash
payload, and explicit ones in formulas match the frozen protocol. Global RNG
state, row order and structure multiplicity cannot affect membership.

The file API checks all of the following before reserving an output directory:

- Exact frozen protocol document and real snapshot/audit hashes. Merely updating
  a tampered file's accompanying hash cannot substitute a different real dataset.
- Snapshot query/schema, original TSV/JSONL hashes, exporter implementation hash,
  and equality of original and audit-copied snapshot metadata.
- Rebuilt audit labels, composition groups, material IDs, source-ID serialization,
  exclusions, counts, and audit/composition implementation hashes. Reconstruction
  uses captured input bytes in a temporary directory; original files are untouched.
- Canonical duplicate rejection, valid scope/labels, sufficient pool size, and the
  fixed real seed/budget configuration.

Synthetic grouped-file row reordering and equivalent formula spelling are accepted
only when the canonical rows still match the rebuilt audit. Their input byte
hashes change but membership does not. Real files remain pinned to their exact
frozen bytes. The audit's recorded Julia/package version strings may differ from
the current runtime; all other audit metadata must match reconstruction. The new
runtime versions are recorded separately in the bundle manifest.

Integrity is not upstream authentication. For real v1, the pinned JSONL/TSV were
also semantically checked during Day 1. The Julia audit itself does not implement
an arbitrary JSON parser or establish authenticity of synthetic JSON contents.
A caller declaring new inputs synthetic cannot obtain a real protocol result.
Changes to real source data or producer code require a reviewed compatibility
check/new audited input and protocol version; there is no force/skip-provenance
flag. Keep the shipped protocol document intact, including its bytes. Git attributes
preserve LF endings for the protocol and frozen producer files even on Windows
checkouts; automatic line-ending conversion must not invalidate their identities.

## Artifact layout and hashes

```text
output/
  manifest.toml
  README.md
  provenance/
    protocol.md
    snapshot/snapshot.toml
    audit/{snapshot.toml,audit.toml,compositions.tsv,excluded.tsv}
    implementation/{src/...,scripts/export_mp_pilot.py,Project.toml}
    unresolved.tsv
  split-00/                     # also split-01 through split-19
    manifest.toml
    inputs/training.tsv
    inputs/candidates.tsv
    evaluation/heldout.tsv
    evaluation/labels.tsv
```

Rankers consume **only** `inputs/training.tsv` and `inputs/candidates.tsv`, each a
single `composition` column. Source IDs, provenance flags, source record counts,
and held-out labels are absent. Folder separation is an interface boundary, not
an operating-system access-control sandbox: callers must not give rankers other
files. Day 3's evaluator should enforce that boundary when invoking methods.

Each split manifest records protocol ID/hash, scope, algorithm version, split
seed, separate reserved ranking seed (10000 + split seed), tie seed 20260901,
budgets, counts, original input hashes, implementation hashes, and four membership
file hashes. These ranking/tie settings are recorded for later use, not executed.
The root manifest binds all split manifests by hash and records unresolved and
excluded counts. Membership files use UTF-8 with LF, a header, and a final LF;
hashes cover the exact file bytes, including that header.

The bundle preserves exact relevant implementation bytes even when the working
tree is dirty, without requiring Git at runtime. Keep the original snapshot TSV
and JSONL alongside it; they are hashed but not duplicated in every bundle.
No input/output absolute paths or timestamps are embedded, so reruns under the
same code and Julia/package versions are byte-identical. Different runtime
versions can change manifest metadata without changing deterministic membership.
Day 5 must additionally freeze the experiment commit and resolved dependencies.

The writer exclusively creates a new directory and refuses existing paths,
including dangling symlinks. If writing fails after reservation, it removes only
its own new directory. Never reuse an output directory to append or replace splits.

## Verification

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
```

Synthetic tests cover fixed independently computed holdouts, equivalent formulas,
row reordering, global RNG independence, duplicate rejection, mixed polymorphs,
train/pool disjointness, unresolved/excluded records, tiny/invalid pools,
provenance corruption, output non-overwrite, manifest hashes, and exact CLI/library
reruns. Existing binary benchmark tests remain part of the same suite.
