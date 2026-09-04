# External score provenance and eligibility decision

Reviewed 31 August 2026 for the [recovery protocol](mp-recovery-protocol.md)'s
Day 4 external-score gate. Joshua Corbett is the author of this review.

**Decision: the external Seko recommender scores are excluded from the primary
comparison and are not evaluated in this pilot at all.** The primary experiment
remains random, training-element popularity, and maximum training-composition
similarity. This is an eligibility decision about evidence, not a judgement of
the upstream model's scientific quality.

The investigation was time-boxed as planned and closed inside the box. No
ranking, hit count, recovery metric, or performance number was computed for the
external scores, and none was inspected before this decision.

## What was inspected

| Item | Finding |
| --- | --- |
| Model | Matrix/tensor-factorization recommender of Seko and collaborators, [sekocha/recommender](https://github.com/sekocha/recommender); method described in Seko et al., *Phys. Rev. Materials* **2**, 013805 (2018) |
| Released artifact | `recommender-2024-07-01.sqlite`, 211,681,280 bytes, SHA-256 `9ee6f6a81f80cab74d967b70d4b0ad5d61c55ecf70e6b689c8a2c59e489a58fb` |
| Artifact identity | Unchanged from the [production validation](production-validation.md) record of 2026-08-30; opened read-only and not modified |
| Stated training sources | Database entries from ICSD, ICDD, and Springer Materials, per the upstream repository |
| Stated purpose | Scoring *currently unknown* chemically relevant compositions against those known entries |
| Documented training membership | None published: no per-composition training list, inclusion rule, or exclusion rule |
| Documented cutoff | None distinct from the 2024-07-01 release date; no source-database version or snapshot date is given |
| Normalization | Raw `score` column, 0.01–1.16248 over the in-scope ternaries; uncalibrated, not a probability, with an apparent 0.01 reporting floor rather than a natural minimum |
| Duplicate scores | 0 duplicate canonical compositions among the in-scope ternary rows; no aggregation rule is needed |

## Coverage, inspected before any performance number

`data3` holds 1,474,012 ternary rows, of which 247,764 are distinct-element
oxygen-containing ternaries. Against the audited pool of 12,506 canonical
composition groups:

| Audited label | Groups | With an external score | Coverage |
| --- | ---: | ---: | ---: |
| Positive | 5,359 | 331 | 6.18% |
| Unlabelled | 7,147 | 2,258 | 31.59% |
| All | 12,506 | 2,589 | 20.70% |

Only 1.04% of the in-scope scored compositions appear in the audited MP pool at
all, so the score set and the recovery pool overlap weakly in both directions.

Reproduce the table with the read-only inspection script; both inputs stay local:

```bash
julia --project=. scripts/inspect_external_scores.jl --scores /path/to/recommender-2024-07-01.sqlite --audit reports/local/mp-ternary-audit/compositions.tsv
```

## Why this fails the eligibility gate

The protocol requires training-data independence to be *established*, not merely
unrefuted, and a newer MP snapshot does not establish it. Three findings block
eligibility, and the third is decisive on its own.

1. **The stated training sources overlap the label definition.** A positive here
   is an MP group with at least one `theoretical=false` record, an experimental-
   provenance proxy drawn largely from the same experimental databases the model
   reports training on. Held-out positives are therefore likely to be training
   data for the model, which is exactly the leakage the split design exists to
   prevent.
2. **Membership and cutoff are undocumented.** Without a training list or a
   verifiable cutoff there is no way to partition the pool into scored
   compositions the model could and could not have seen, so no defensible
   restricted pool can be declared.
3. **Coverage is associated with the outcome label.** Unlabelled compositions are
   scored about five times as often as positives, 31.59% against 6.18%. This is
   the pattern the model's stated purpose implies: a released list of *currently
   unknown* compositions is close to the complement of its known-compound
   training set. Selection into the scored pool is therefore censoring tied to
   the label being predicted, and the 331 scored positives are a small, atypical
   residue rather than a random sample of positives.

Consequence: a restricted-pool evaluation on the 2,589 covered compositions
would have a positive share near 2.8%, against 13.03% in the frozen candidate
pool, and its ranking result would substantially reflect the censoring rule
rather than recovery skill. Reporting it even as an exploratory figure would
invite exactly the misreading the protocol forbids, so it is omitted rather than
labelled. The protocol permits either omission or an exploratory label; omission
is the honest option when the confounder is this directly tied to the outcome.

This inspection establishes the differential coverage as fact. It does not by
itself prove the exclusion rule that produced it, and no claim is made about the
upstream model's accuracy on its own task. The gate turns on absent evidence of
independence, which is settled either way.

## What would reopen the question

All of the following, in a separately versioned protocol written before any
external-score performance is read:

1. A published or supplied training-membership list, or a verifiable cutoff with
   the source-database versions and dates behind it.
2. A restricted pool declared in advance, with its positive/unlabelled coverage,
   and the random, popularity, and similarity baselines recomputed on that same
   pool so no method is compared across different pools.
3. An account of why coverage differs by label, sufficient to show the remaining
   scored positives are not a biased residue.
4. Terms permitting the intended use and any derived publication; the
   [data and provenance review](mp-data-provenance-review.md) restrictions on the
   MP snapshot apply unchanged to any joined output.

Retraining or reimplementing the recommender is out of scope for this pilot and
is not required to close this decision.

## Handling

The score database remains outside Git, ignored, and read-only; this pilot did
not copy, modify, or redistribute it. Only the aggregate counts above are
recorded in tracked documentation. Per-composition coverage output stays in the
ignored local review folder. The recommender research and database are separate
work by Atsuto Seko and collaborators; see the README's citation.
