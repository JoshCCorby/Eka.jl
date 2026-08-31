# MP composition recovery protocol

**Protocol ID:** `eka-mp-recovery-v1`

**Frozen:** 31 August 2026, before recovery ranking evaluation.

**Status:** scientific contract for implementation; not an implemented PU runner,
not measured performance, and not formal external preregistration.

## Question and scope

How well do simple composition rankings recover withheld compositions with MP
experimental provenance, within MP-covered chemistry?

Retain the audited **oxygen-containing ternary** pool: O plus exactly two other
elements, non-deprecated records, and the export query's `include_gnome=false`.
Keep H-containing and halogen-containing systems. Do not call this an oxide
validator. Element membership does not establish oxygen oxidation state or exclude
hydroxides, oxyhalides, salts, or unusual stoichiometries. The Day 1 coverage review
supports retaining the existing pool without an additional unvalidated filter.
There is no stability, energy, source-ID-presence, or stored-score cutoff.

This is a composition recovery experiment, not a synthesis recommendation. It
measures neither first discovery nor transfer to wholly unseen chemical systems.
The snapshot is fixed; do not re-query MP to reproduce it.

## Data identity and verification

Source: `data/local/mp-ternary-snapshot/`, MP database **2026.04.13**,
retrieved **2026-08-31T12:16:39.322001+00:00**, mp-api **0.46.5**.
Grouped input: `reports/local/mp-ternary-audit/compositions.tsv`.

| File | SHA-256 |
| --- | --- |
| Snapshot `snapshot.toml` | `5c82fb38f90105a03779daab0cb32f2ba134cb1ce50cf94e845b38e92719ad58` |
| Snapshot `records.tsv` | `98a6ce78d592e5e7e4cef98d675badcf991cc2caecef9a6b0ec10c1e08731a08` |
| Snapshot `records.jsonl` | `5ba17f307d61c9635a93f75fe86afc9e81af430036f3ef1fc0fe199a75f3829b` |
| Audit `audit.toml` | `c63f465ab9104508b5a08f4a3263d267842b06d94954d0479e3662da7268eefa` |
| Audit `compositions.tsv` | `722ecf2e40a99c59b0f024219782a1fe8791f000353cd5e6cf7faa1ef6e5213d` |

Before splitting, verify these identities, snapshot schema/query metadata, copied
metadata equality, audit counts, and the exporter/audit/composition implementation
hashes recorded in the source metadata. Fail if provenance cannot be established.
Changed implementation requires a documented compatibility check or new audited
input and protocol version; never silently accept stale provenance.

Hashes establish identity and integrity, not upstream authenticity or permission
to distribute data. Day 1 additionally checked JSONL-to-TSV and grouped-record
consistency offline. Full evidence, sample IDs, and coverage tables remain in
`reports/local/mp-recovery-day1-2026-08-31/`.

## Unit, labels, and exclusions

The unit is a canonical reduced composition. Sum repeated element symbols, reduce
integer amounts by their greatest common divisor, sort symbols alphabetically,
and include explicit ones, as in Eka's `Composition`. Group **all** polymorphs and
equivalent formulas before any split. Structure count must not weight sampling,
popularity, or metrics.

| Evidence within a composition group | Label |
| --- | --- |
| At least one explicit `theoretical=false` record | Positive |
| Every record explicitly `theoretical=true` | Unlabelled |
| No positive record and at least one missing flag | Unresolved |

Mixed true/false groups are positive. An external source ID does not override a
flag. Missing IDs do not change labels, and missing flags do not become true.
A positive is an experimental-provenance proxy, not a literature-verified synthesis
claim. This interpretation follows the [MP provenance implementation](https://github.com/materialsproject/emmet/blob/main/emmet-core/emmet/core/provenance.py);
Day 1 compared installed emmet-core 0.87.2 with the retrieved upstream file.
Neither establishes the exact server-side builder version for this snapshot.

Exclude unresolved groups from both training and evaluation. Preserve explicit
record exclusions for invalid symbols, unsupported formulas, nonpositive,
nonintegral or out-of-range counts, and records outside the declared scope. Do
not round occupancies. Reject duplicate canonical input groups; do not silently
choose one. If exclusions or source identity change, version the protocol before
ranking. Unlabelled never means confirmed negative.

## Frozen experiment choices

| Decision | Frozen value |
| --- | --- |
| Holdout | `h = floor(P / 5)`, where P is the eligible positive group count |
| Training | All other positive groups, `T = P - h` |
| Candidate pool | All h held-out positives plus every eligible unlabelled group; `N = h + U` |
| Split seeds | Exactly the 20 integers 0–19 |
| Main budget | `k = 100` |
| Secondary budgets | `k = 20, 50, 200`; always report all four |
| Primary comparison | Maximum training-composition cosine similarity minus training-element popularity, paired within each split |
| Reference | One pseudorandom ranking per split plus exact uniform-random expectations |
| Random-ranking seed | `10000 + split_seed` (10000–10019), recorded separately |
| Shared tie seed | `20260901`, fixed for every method and split |
| Tuning | None on evaluation splits; no hyperparameter search in this pilot |
| External scores | Not primary; exploratory only unless independence is established in a separately versioned protocol |
| Repetitions | Repeated holdouts of one snapshot, not independent experimental datasets |

Reject empty/too-small inputs if h < 1, T < 1, U < 1, or any requested k exceeds N.
Budgets must be distinct positive integers; do not truncate an oversized budget.

### Exact split, tie, and random procedures

All strings below use UTF-8, literal LF newlines, no trailing newline, canonical
formula `f`, and decimal nonnegative integer seeds without leading zeros. SHA-256
keys are lowercase hexadecimal strings ordered lexicographically ascending.
Never use the language's process-dependent `hash()` or global RNG state.

1. Sort unique eligible positive formulas lexicographically. For split seed `s`,
   compute `SHA256("eka-pu-split-v1\n" + s + "\n" + f)`. Sort by `(hash, f)`
   ascending and hold out the first h. Remaining positives are training inputs.
2. Candidate membership is the union of holdouts and all eligible unlabelled
   formulas, stored in canonical formula order. Exclude training positives and
   unresolved formulas, including equivalent representations.
3. Shared tie key is `SHA256("eka-pu-tie-v1\n20260901\n" + f)`.
   Popularity and similarity sort by descending finite score, then ascending tie
   key, then formula as a final hash-collision fallback. Use exact numeric equality
   for ties; no score rounding or tolerance grouping. Never use stored model scores.
4. Random ranking uses ascending
   `SHA256("eka-pu-random-v1\n" + ranking_seed + "\n" + f)`, then shared tie
   key, then formula. This is a versioned hash-based pseudorandom ordering. Its
   analytical reference is ideal uniform sampling without replacement; a fixed
   hash run need not equal the expected number of hits.

Seeds serve different purposes and have different hash domains. Do not select
seeds after seeing outcomes. Store evaluation labels separately from what rankers
receive: training formulas and candidate formulas only.

## Methods and permitted inputs

**Training-element popularity.** For each element e let n(e) be the number of
training-positive compositions containing it, counting each composition once.
For candidate c with element set E(c), score
`sum(n(e) for e in E(c)) / (length(E(c)) * T)`. This preserves the existing binary
benchmark's popularity definition but fits it anew on each split. An unseen
element contributes zero. All candidates here have three elements and oxygen;
oxygen's contribution is the constant 1/3. Report tie sizes and whether the other
element frequencies dominate. Do not reuse a cache fitted to all positives.

**Maximum composition similarity.** Represent each composition as its vector of
reduced element counts, zero outside its elements. Score c by
`max(dot(c,t) / (norm(c)*norm(t)) for t in training)`. Reuse Eka's pairwise cosine
calculation (Float64, clamped to [0,1]) without inheriting its stored-score tie
breaker. Choose no reference using held-out labels. No atom weighting, learned
embeddings, oxidation features, fitting, or search over similarity variants.
Batch or stream the maximum; a full candidate-by-training matrix is unnecessary.

**Random.** Uses only candidate formulas and its declared ranking seed. No source
IDs, MP flags, stored scores, evaluation labels, structure counts, chemical-system
label frequencies, or source dates are scoring features for any primary method.
Changing evaluation labels with fixed training/candidate formulas must not alter
scores or ranks. Source identifiers may be used for audit provenance only.

**External score gate.** Day 4 may inspect model/version, training sources and
membership/exclusions, cutoff evidence, normalization, coverage, and duplicate
score handling for Seko or another proposed score. A newer snapshot does not prove
training independence. Without adequate evidence omit the score or label it
exploratory outside the primary comparison. Inspect coverage before performance;
never impute missing scores or silently drop rows. A restricted-pool analysis must
first declare its pool, label coverage, and matching baselines for that same pool.
Any primary promotion needs a new protocol before its real evaluation.

## Metrics and analysis

For each method, split, and budget, let `H@k` be the number of held-out positive
compositions among the first k ranked candidates. With h holdouts and N candidates:

| Metric | Definition |
| --- | --- |
| Observed-positive hits | `H@k` |
| Observed-label fraction | `H@k / k` |
| Held-out-positive recall | `H@k / h` |
| Observed-label enrichment | `(H@k / k) / (h / N)` |
| Uniform-random expected hits | `k * h / N` |
| Uniform-random expected observed-label fraction | `h / N` |
| Uniform-random expected recall | `k / N` |
| Uniform-random expected enrichment | `1` |

These formulas require `h > 0`, `N >= k > 0`. Check them against hand-calculated
synthetic fixtures, including tied scores and invalid denominators. A top-ranked
unlabelled entry is not a confirmed failed synthesis. Do not report ordinary
negative-class accuracy, specificity, or false-positive rate as a discovery result.

Lead with `D_s = H_similarity@100 - H_popularity@100` for every one of the 20
identical splits. Show all D_s, mean, median, and positive/zero/negative counts.
Report all other budgets as secondary and keep weak/zero effects. Show the random
realizations alongside their exact expectations; extra random seeds are not extra
datasets. Report complete pool/holdout sizes and complete rankings locally.

Describe variation across overlapping holdouts as **split sensitivity**. Do not
claim a population confidence interval from their standard error, bootstrap just
the selected top rows, or infer equality from overlapping separate intervals.
No formal significance claim is planned. A negative or inconclusive outcome is
valid; beating a baseline is not a completion requirement.

Predetermined descriptive breakdowns: chemical system; element membership (with
O identified as universal); H-containing and any-halogen-containing groups
(F, Cl, Br, I, At, Ts); mixed-flag positive groups; score-tie sizes. Report
subgroup denominators, treat overlapping element groups as overlapping, and do
not select a subgroup winner. New subgroup analyses are exploratory. MP coverage,
historical research effort, provenance quality, normalization restrictions, and
shared train/test chemical systems constrain interpretation.

## Run records, amendments, and release boundary

Before real evaluation, freeze the tested implementation commit and dependencies.
If dirty, retain the exact changed/untracked file bytes, patch, and their hashes.
Each new, non-overwritten run directory must bind protocol ID and file hash,
snapshot/audit identities, algorithm versions, split/ranking/tie seeds, membership
hashes and counts, code/dependency versions, full rankings, and per-split metrics.
Keep timestamps and runtime separate from deterministic outputs. Reproduce one
split in a fresh directory and compare membership, ranks, and metrics exactly.

Only synthetic evaluation is allowed during implementation validation. Do not
inspect real ranking performance before the implementation freeze. If a defect
requires a change, record it, bump the affected version, and rerun every affected
method/split; do not retain favorable earlier results.

Raw records, samples, membership, rankings, detailed coverage tables, and unreviewed
data derivatives stay under ignored `data/local/` or `reports/local/`. The
[data/provenance review](mp-data-provenance-review.md) records unresolved terms;
this protocol grants no redistribution permission. No data publication, push,
new export, or background schedule is part of this Day 1 milestone. The existing
binary `eka benchmark` contract remains unchanged; `benchmark-pu` is still a
proposed future interface, not an available command.

Version history: v1 (31 August 2026) retains the roadmap defaults and specifies
hash domains, seed values, tie equality, method equations, and descriptive
breakdowns before recovery evaluation.
