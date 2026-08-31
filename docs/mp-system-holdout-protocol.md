# MP chemical-system holdout protocol

**Protocol ID:** `eka-mp-system-holdout-v2`

**Frozen:** 31 August 2026, after the original pilot and label-sensitivity
results, before inspecting system-holdout rankings. Prospective follow-on design;
not a preregistration preceding the original pilot. The v1 and sensitivity
protocols, inputs and preserved outputs remain unchanged.

## Question and scope

How does similarity-minus-popularity recovery change when candidate element
combinations have no training positives? The comparison is between two complete
sampling protocols, not a causal estimate of chemical separation. Chemical
systems can still be close analogues: BaTiO3 and SrTiO3 have different systems.
Similarity's advantage may shrink, persist, disappear or reverse; no outcome is
preferred. Unlabelled compositions are not known failed syntheses.

Use the same verified MP snapshot/audit and oxygen-containing ternary scope as
v1, including its source hashes, canonical formulas, unresolved exclusions and
GNoME exclusion. No new API query, external scores, energy filters, learned
model, temporal claim or manual relabelling. Carry `original`, `exclude_mixed`
and `unlabel_mixed` from the frozen label-sensitivity protocol into both designs.
Use full-pipeline labels, never evaluation-only relabelling with old training.

## Exact system and membership rules

A system is the ASCII-lexicographically sorted set of distinct element symbols
in an Eka canonical composition, joined with `-`. Stoichiometry does not affect
system identity. Reordered and proportionally equivalent formulas have the same
system; canonical duplicate composition groups are errors. Only three-element
systems containing O are eligible.

Construct a single common system universe S from the original positive and
unlabelled groups, before policy filtering. Original unresolved groups never
contribute to S or to any training/candidate population. This shared universe
and all system assignments are identical across policies, including systems
that become empty after excluding mixed groups.

For each split seed s=0,...,19, sort S by the tuple:

`(hex(SHA256("eka-pu-system-split-v2\n" + decimal(s) + "\n" + system)), system)`.

Select the first floor(|S|/5) systems for candidates; the rest are training-side
systems. Selection is uniform by system under the hash ordering, not balanced
by composition count, positive count or outcome. Large systems are neither split
nor downweighted. No rejection sampling, seed replacement, class balancing or
post-result subset selection is allowed.

Apply each label policy before constructing memberships:

- `original`: original positives and unlabelled groups.
- `exclude_mixed`: remove groups with both explicit experimental and theoretical
  records; retain remaining positives and original unlabelled groups.
- `unlabel_mixed`: those mixed groups become unlabelled, never training positives.

For system holdout, training contains only policy positives outside selected
systems. Held-out positives are all policy positives in selected systems.
Candidates contain those holdouts plus all policy unlabelled groups in selected
systems. Unlabelled groups outside selected systems are omitted entirely, not
used for training or candidate evaluation. Excluded/unresolved groups are absent.
A selected system can have only unlabelled candidates, only positive candidates,
or no remaining rows under a policy; report these cases rather than reselection.
Training and candidate system sets must be disjoint. Both alternative policies
share exactly their training and held-out positives; their candidate difference
is the mixed groups in selected systems.

Composition-holdout controls use the frozen v1 formula-hash selection separately
under each policy: floor(P_policy/5) held-out positives, remaining positives in
training, all policy unlabelled groups in candidates. These controls must match
the saved full-pipeline sensitivity memberships, rankings and metrics exactly.
They do not share a candidate population with system holdout.

Before any real v2 scoring, check every branch/seed has at least one training
positive, one held-out positive, one unlabelled candidate, at least one selected
and one nonselected system, and candidate count >=200. All configured budgets
must be feasible. If any branch fails, stop the entire experiment and report the
preflight failure; amend/version a new design before scoring, never silently
omit branches or change selection. Synthetic tests may specify smaller budgets
and seed sets; all other rules are identical and explicitly marked synthetic.

## Scoring and evaluation

Use unchanged v1 `random`, training-only `popularity`, and maximum training
composition `similarity`. Ranking seed is 10000+s; tie seed is 20260901; preserve
v1 hash domains, Float64 operations, formula tie fallbacks and metric definitions.
Rankers receive training/candidate compositions only, with labels attached after
ranking. No cache from a different training set. Exclusion/unlabelling branches
must have equal scores and relative orders on their shared candidates.

Budgets: 20,50,100,200. For actual candidate count N and held-out-positive count h,
report H@k, H@k/k, H@k/h, enrichment=(H@k/k)/(h/N), uniform-random expected hits
k*h/N, and the declared random realization. Primary within-branch effect is
D_s=H_similarity@100-H_popularity@100. Report every D_s, mean, median, range and
positive/zero/negative counts, plus all secondary budgets and per-method means.

For each policy report the system-minus-composition change in mean D and the
seed-aligned D differences, without treating aligned seed numbers as matched
samples. Do not interpret raw hit changes alone as the effect of separation.
There are two designs × three policies × twenty seeds × three methods × four
budgets = 1,440 metric rows. Every branch is required.

## Population and similarity diagnostics

For every design/policy/seed report training-positive count, candidate count,
held-out-positive count, unlabelled candidate count, prevalence, excluded groups,
and unused unlabelled groups. Report common-universe system count, selected
system count (system design only), observed training/candidate/positive system
counts, their overlap, selected empty systems and mixed training/candidate counts.

Report positive concentration separately in training and holdouts: the fraction
in the largest system and in the five largest systems (or all if fewer than
five). Report these counts/fractions for both designs; unequal system sizes and
candidate prevalence are part of the protocol difference.

Use maximum cosine similarity to training positives in the existing elemental
count-vector representation (equivalently normalized atomic fractions). This is
exactly the unchanged similarity scorer, not a learned chemical distance.
For all candidates, held-out positives and unlabelled candidates separately,
save every maximum and report n, mean, min, p10, median, p90 and max. Quantiles
use the sorted nearest-rank rule at index max(1,ceil(q*n)); mean uses formula-order
Float64 accumulation. Report the fraction >=0.9 and >=0.99; these thresholds are
descriptive choices, not proof of near-duplicate chemistry. Label-specific
summaries are evaluator diagnostics only and cannot change scores/membership.

No matched-size control is included. Therefore no causal claim separating
system disjointness from training size, pool size, prevalence or composition
changes is permitted. Overlapping splits describe split sensitivity, not
independent replications. No confidence intervals, significance tests, tuning
or post-result threshold changes. No inference of synthesizability or universal
out-of-distribution generalization from this elemental representation.

## Validation, freeze and reproduction

Register this protocol by ID and exact SHA-256 without changing earlier pins.
Preserve its bytes/hash before real scoring and record preflight populations
separately. Capture complete implementation, Project/Manifest, Julia version,
input hashes, baseline identity and the exact source archive before evaluation.
Validate source by the existing reaudit/hash checks. Validate the saved baseline
file inventory and independently reconstruct controls; compare every control
membership, ranking field and metric with saved full-pipeline sensitivity.

Tests must cover grouping invariance, unequal system sizes, policy alignment,
excluded/mixed/unused groups, unlabelled-only systems, infeasibility, deterministic
order, composition/system separation, ranking label isolation, common-candidate
score invariance, protocol tampering and no-overwrite behavior. Independently
check saved membership/metrics and population/diagnostic calculations; corruption
must fail even if a file's manifest checksum is rewritten.

Write only to new directories. Record every ranking and membership, config,
source/implementation hashes and deterministic output inventory. Keep wall-clock
timings separate. Recompute all branches from the captured environment in a
separate checkout and compare deterministic outputs exactly. Do not edit prior
sealed evidence. Data remain local during this experiment; the separate terms
review governs any later release. Report any implementation correction before
rerunning; changes to this design require a new protocol identity.
