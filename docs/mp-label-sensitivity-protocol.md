# MP positive-label sensitivity protocol

**Protocol ID:** `eka-mp-label-sensitivity-v1`

**Frozen:** 31 August 2026, after the v1 pilot report and before any alternative
label-policy ranking or metric inspection. This is a prospective follow-on
specification, not a pre-pilot preregistration. The original
[v1 protocol](mp-recovery-protocol.md) and its preserved outputs do not change.

## Question and fixed choices

How sensitive is similarity-minus-popularity recovery to the treatment of
composition groups with both explicit `theoretical=false` and
`theoretical=true` records? This examines an experimental-provenance proxy, not
whether particular compositions can be synthesized.

Use the identical source snapshot, audit, chemistry, canonicalization, and
exclusions pinned by v1. No re-query, energy filter, external scores, learned
model, system holdout or literature-based relabelling is permitted here.
Original v1 results are a required input, identified by the captured config and
deterministic-file hashes. Validate them against the original snapshot and
recompute them for compatibility before using their saved rankings.

Preserve methods `random`, `popularity`, `similarity`; budgets 20, 50, 100, 200;
split seeds 0–19; ranking seeds 10000–10019; tie seed 20260901; exact Float64
scores and v1 hash/tie rules. The original positive count is P, unlabelled count
U, and mixed-flag positive count M. A mixed group has strictly positive
experimental-record and theoretical-record counts. Unknown flags alone do not
make a group mixed. No mixed group may contradict its original positive label.

Before ranking, independently count mixed groups and their distribution across
chemical systems, element membership, H/halogen membership and record counts.
Store these counts locally. They are input diagnostics, not outcome-based scope
selection. Neither mixed nor nonmixed status supplies a predictive feature.

## Policy identifiers

| Policy | Positive groups | Unlabelled groups | Excluded groups |
| --- | --- | --- | --- |
| `original` | Original P | Original U | Original unresolved groups |
| `exclude_mixed` | P minus M | Original U | Original unresolved plus all M |
| `unlabel_mixed` | P minus M | Original U plus all M | Original unresolved |

Keep these IDs separate from analysis mode. An output is identified by protocol,
mode (`evaluation_only` or `full_pipeline`), policy, split seed and method.

## Evaluation-only analysis

Use the original v1 training memberships, fitted scores and complete saved
rankings. Do not add any originally training composition to the evaluation
pool, refit a method, or change any retained score or relative ordering.
Original mixed training positives remain in the fitted state under **all**
evaluation-only policies. Report their count explicitly.

Let H_s be the original held-out set, C_s the original candidate set, and
m_s = |H_s intersect M|. All candidate mixed groups must be original holdouts.

| Policy | Eligible candidates | Evaluation positives | N_s | h_s |
| --- | --- | --- | --- | --- |
| `original` | C_s | H_s | U + floor(P/5) | floor(P/5) |
| `exclude_mixed` | C_s minus M | H_s minus M | U + floor(P/5) − m_s | floor(P/5) − m_s |
| `unlabel_mixed` | C_s unchanged | H_s minus M | U + floor(P/5) | floor(P/5) − m_s |

For exclusion, filter each original full ranking, preserve every retained score
and relative order, and assign contiguous eligible ranks starting at one. A
budget k means **k eligible candidates**, not k original positions. Preserve the
original rank of every retained row and report original rank depth at each
budget. This can require examining more than k original positions; do not
present it as the same original selection. For unlabelling there is no filtering,
so every rank/score stays fixed and original depth equals k.

Report this as evaluation sensitivity with original training labels retained.
It is not an end-to-end experiment under the new training-label policy.

## Full-pipeline analysis

Rebuild grouped labels for each policy **before** split construction. For each
policy with P_p positives and U_p unlabelled groups, use the existing v1
formula-hash order to hold out h_p = floor(P_p/5), train on P_p − h_p positives,
and rank those holdouts plus all U_p unlabelled groups. Reuse the declared seeds
and hash domains to align selection where valid; never reuse old membership
unchanged merely because seeds match.

Both alternatives share exactly the same eligible positives and therefore the
same training/held-out membership. Their candidate pools differ by M: all mixed
groups are excluded under `exclude_mixed`, and all are unlabelled candidates
under `unlabel_mixed`. No mixed group is a training positive under either.
Original unresolved groups remain excluded. Recompute all methods from each
branch's training/candidate inputs; no fitted full-positive cache is allowed.

`full_pipeline/original` must reproduce every original membership, score, rank
and metric. For the two alternatives, shared-candidate scores and relative rank
order must agree because training, hash seeds and scoring definitions agree;
additional unlabelled candidates may change absolute ranks and metrics.

## Metrics, denominators and reporting

For every mode, policy, split, method and budget, report training count (including
mixed training count), candidate count, mixed candidate count, held-out-positive
count, observed-positive prevalence and excluded-group count. Preserve full
membership and labelled rankings locally, with labels attached only after scoring.
Report the policy-wide positive/unlabelled counts separately from the actual
training membership: evaluation-only training still follows the original policy.

Use the v1 metric definitions with each branch's actual eligible N and h:
H@k; H@k/k; H@k/h; (H@k/k)/(h/N); exact uniform-random expected hits k*h/N.
Require h >= 1, training >= 1, U >= 1 and every budget <= N. Fail the whole run
before any alternative ranking if a declared branch is infeasible; do not
silently omit a split or truncate a budget. Unlabelled never means negative.

Primary comparison: D_s = H_similarity@100 − H_popularity@100 within each
identical branch and split. Report every D_s, mean, median, range, and
positive/zero/negative counts for all six branches. Report changes from original
D_s, while making visible that populations differ. All secondary budgets and
all random realizations and expectations must be retained. Report per-method
mean hits, recall and enrichment alongside population sizes; raw hit changes
alone are not evidence of a causal training-label effect.

There are 6 branches × 20 splits × 3 methods × 4 budgets = 1,440 metric rows.
All are required, even when original controls duplicate the pilot. Descriptive
variation is split sensitivity, not independent experiments. No significance
tests, confidence intervals, new tuning, subgroup winner selection, or causal
claim isolating relabelling from changed populations is permitted.

## Interpretation and subsequent decisions

Allow effects to shrink, persist, reverse, or become zero. A small change in
sign around zero is reported as directional sensitivity, not proof of a robust
scientific reversal. Report continuous magnitudes and the split distribution;
do not impose a post-result threshold for a desired conclusion.

If either alternative changes the sign of the mean primary full-pipeline D
relative to original, carry both alternative policies into any later system
holdout design (or explicitly restrict its claims and document that decision).
If only evaluation-only results reverse, retain them as evaluation diagnostics
and discuss why the end-to-end conclusion differs. Even without reversal, report
all magnitude changes; none demonstrates synthesis success or label validity.
A literature audit may be proposed only as a separately frozen sampling and
assessment plan, never used retroactively to replace these labels.

Model development remains deferred. System holdout, if later designed, tests
unseen element combinations, not necessarily chemically distant examples:
BaTiO3 and SrTiO3 are separate systems. Similarity's advantage may shrink,
persist or reverse; no direction is presumed desirable or more publishable.

## Software, freeze and reproduction

Maintain an explicit protocol-ID-to-document-and-hash registry. Keep v1's ID and
hash unchanged; unknown IDs or altered protocol bytes fail. This protocol has
its own pin. Preserve the exact implementation, dirty patch and untracked source
bytes, Project/Manifest and Julia version before real sensitivity evaluation.
Capture snapshot, audit, original pilot config/rankings and protocol hashes.
The protocol checksum lives in code/run records, not in its own hashed text.

Synthetic verification must cover policy membership, mixed training exclusion,
valid seed reuse, filtering/depth/denominator semantics, label isolation,
same-input score invariance, original-v1 compatibility, deterministic reruns,
tampered baselines and no-overwrite behavior. Verify all original pilot outputs
before consuming them. Run every branch, then reproduce all deterministic
scientific outputs from the captured environment in a separate directory.

Keep original pilot outputs untouched and use exclusively new output directories.
Separate timings from deterministic artifacts. Results and all unreviewed data
derivatives remain local; no licence, permission or publication is implied.
