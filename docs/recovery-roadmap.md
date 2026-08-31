# Recovery project: ordered task checklist

Prepared 31 August 2026 from the proposed post-pilot roadmap and its review.

**Order:** finish the frozen pilot → test label sensitivity and resolve sharing → evaluate chemical-system holdout → decide whether to add a learned comparator → package the findings.

This document adopts the supplied revised roadmap as the working plan. It does
not amend the frozen v1 protocol. Checkboxes below record verified progress as
of 31 August 2026; unmarked work remains pending. Dates and effort estimates are
provisional; advance when each completion gate is met.

## Progress recorded 31 August 2026

Steps 1, 2, 4, 5 and 6 are complete locally: the original pilot and both label-sensitivity
analyses validate and reproduce. Their distinct protocols were frozen before
respective evaluation; v1's identity and artifacts remain unchanged. See
[pilot reproduction](mp-pilot-reproduction.md) and
[label-sensitivity workflow](mp-label-sensitivity.md).

The local evidence directories are
`reports/local/mp-recovery-pilot-v1-2026-08-31/` and
`reports/local/mp-label-sensitivity-v1-2026-08-31/`. Scientific results, rankings,
source records and unreviewed derivatives remain outside Git. The sensitivity
report records the subsequent decision to carry all three label policies into
the proposed system-holdout design; v2 was subsequently frozen, implemented and evaluated separately.

Step 3 has a verified environment restore and an
[artifact-by-artifact permissions register](publication-permissions.md).
The owner supplied MP terms permitting attributed processed results and licensing
Content under CC BY 4.0; the [evidence review](mp-terms-evidence.md) records the
copy's checksum, current-version caveat and retained fields. Original code is
MIT with scoped third-party notices. Final data-release review remains separate;
there is no blanket provider-permission blocker for covered uses.

The [system-holdout protocol](mp-system-holdout-protocol.md) was frozen before
scoring, with all three policies and an explicit noncausal comparison. All 1,440
metrics and 1,472 deterministic files reproduced exactly in a separate checkout;
see the [workflow/evidence guide](mp-system-holdout.md). Next is Step 7: decide on
a precise learned-comparator question/specification before any feasibility run.
No model training is authorized by the result alone. A separate literature audit was
considered and deferred; no ad hoc label correction was applied.

## 1. Finish the existing pilot without changing its design

Preserve the frozen v1 protocol. Do not fold the later experiments into the first run.

- [x] Record the implementation commit, protocol hash, input snapshot identifier/hash, and exact dependency environment.
- [x] Execute all 20 planned splits, all four budgets, and all three methods: random, popularity, and similarity.
- [x] Save the complete outputs in an immutable run directory (operational freeze: SHA-256 inventory and write protection; not WORM storage).
- [x] Validate split membership, rankings, metrics, and the expected set of outputs.
- [x] Reproduce one split in a separate directory and compare membership, rankings, and metrics exactly, as required by the existing plan.
- [x] Reproduce the required workflow from a clean checkout using the recorded environment.
- [x] Report every split's `D_s = H_sim@100 − H_pop@100`, its mean and median, and the positive/zero/negative counts.
- [x] Describe variation across splits as split sensitivity. Preserve v1's rule against confidence intervals and significance claims.
- [x] Write a short pilot report explaining the question, comparison, observed effect, and limitations.

**Interpretation:** the pilot measures recovery of withheld provenance-labelled compositions under random composition holdout. A similarity advantage can be valid for that task. It does not establish synthesis success or broad discovery ability. Unlabelled candidates are not known failed syntheses.

**Done when:** the planned run is complete, validates, reproduces, and has a report that separates measured results from interpretation.

## 2. Correct the roadmap's claims and record the next decisions

Do this after the pilot report, before inspecting any new experimental rankings.

- [x] Replace “expect the margin to collapse” with three hypotheses: similarity's advantage shrinks, persists, or reverses under system holdout.
- [x] Remove claims that the pilot advantage is necessarily an artifact or that a particular result will be the most publishable.
- [x] Define system holdout as testing transfer to unseen element combinations, not necessarily to chemically distant materials.
- [x] Record the concrete limitation: BaTiO3 and SrTiO3 belong to different systems, so one can remain in training while the other is held out.
- [x] Remove the automatic rule that a similarity–popularity tie moves model development ahead of evaluation design.
- [x] If the pilot produces a tie, inspect baseline strength, score ties, representation, label composition, and implementation correctness before choosing the next experiment. Keep any exploratory diagnostics separate from frozen results.
- [x] Define the next analyses and their interpretation rules before running them; document subsequent changes as new versions.

**Done when:** the roadmap allows all plausible outcomes and states exactly what each experiment can and cannot establish.

## 3. Resolve reproducibility and sharing requirements

Run this work alongside Step 4 where possible. Unresolved publication terms need not block permitted local analysis.

- [x] Choose and document how exact environments are restored: commit the appropriate environment lockfile or deliberately preserve a complete environment with each run.
- [x] Verify the chosen approach from a clean checkout and document the restore command/workflow.
- [x] Record owner confirmation and apply MIT to original code, with scoped notices for reused Seko examples and dependencies; third-party data permissions remain separate.
- [x] Record owner-supplied MP terms and their provenance limits; independently retrieved current-page applicability remains a final data-release check.
- [x] Record the supplied text's checksum, intended source, review date, unavailable version date, six retained fields and general-grant scope limits.
- [x] Create a publication-permissions table covering your code, dependencies, synthetic fixtures, aggregate results, composition records, provenance fields, and other derived artifacts.
- [x] For each category, record the basis for sharing, attribution requirements, restrictions, and unresolved questions.
- [x] Do not mark any category as definitely publishable or prohibited without establishing the applicable basis.

**Done when:** an exact environment can be restored, the code-licensing decision is recorded, and every proposed publication artifact has a documented status. Unresolved items remain excluded from release.

## 4. Test sensitivity to the positive-label rule

Do this before committing to a new model. The original rule is “at least one MP record has `theoretical=false`,” an experimental-provenance proxy rather than a direct synthesis claim.

### 4.1 Freeze the sensitivity design

- [x] Confirm the number and distribution of composition groups with mixed flags; the original roadmap reports 1,343, which needs verification against the frozen snapshot.
- [x] Define three label policies: the original rule, mixed-flag groups excluded, and mixed-flag groups treated as unlabelled.
- [x] Distinguish the two analyses below and predefine their metrics, eligible populations, and denominators.
- [x] Preserve the original pilot outputs. Give each new policy and analysis its own identifier and reproducible configuration.
- [x] Before multiple frozen protocols coexist, generalise protocol pinning to a version-to-hash mapping, or an equivalent explicit versioned mechanism, without changing v1's identity.

### 4.2 Run an evaluation-only analysis

- [x] Hold the original fitted state and rankings fixed while changing the evaluation label rule.
- [x] Specify whether excluded groups are filtered and ranks recomputed or handled through a separately defined eligible evaluation set; do not change the meaning of the budget silently.
- [x] Report how the measured effect changes and identify that original training labels were retained.
- [x] Describe this as sensitivity of evaluation to relabelling, not as a full run under the alternative training-label policy.

### 4.3 Run the full alternative-label analyses

- [x] Rebuild valid training and evaluation membership under each policy.
- [x] Ensure groups now classified as unlabelled are not retained as training positives.
- [x] Remove excluded groups from the relevant populations and recompute pool sizes and metric denominators.
- [x] Recompute all affected training-derived scores and rerun the methods. Reuse seeds or group assignments only where valid; do not assume the old splits remain valid unchanged.
- [x] Report training counts, candidate counts, eligible positive counts, and the sign and magnitude of the method differences under each policy.
- [x] If conclusions are label-sensitive, consider a small literature audit with its sampling rule and assessment criteria frozen before inspection.

**Done when:** the report quantifies label sensitivity and clearly distinguishes changing evaluation labels from changing the full training/evaluation pipeline.

## 5. Design and freeze chemical-system holdout v2

- [x] Specify a chemical system as a canonical unordered set of elements and document how it is constructed from a composition.
- [x] Define exactly how whole systems are assigned to training and candidate populations, including unlabelled records, eligibility rules, and edge cases.
- [x] Document how seeded system selection works and how it handles unequal system sizes.
- [x] Define the question narrowly: how does recovery change when candidate element combinations have no training positives?
- [x] Predefine how v1 and v2 will be compared on the same snapshot and with clearly specified label policies.
- [x] Require reporting of training-positive count, candidate count, held-out-positive count/prevalence, number of systems, and concentration of positives in large systems.
- [x] Include the random baseline and within-protocol method differences; do not interpret raw hits@100 changes alone as the effect of chemical separation.
- [x] Add a candidate-to-training similarity diagnostic under both protocols, using a documented representation and distance/similarity rule.
- [x] If making a causal claim about chemical separation, predefine a matched-size control to reduce confounding by training and pool sizes. Otherwise limit the conclusion to the observed protocol difference.
- [x] Freeze the v2 protocol, metrics, diagnostics, and any controls before looking at v2 rankings.

**Done when:** v2 defines a reproducible experiment with explicit limits, comparison rules, and no assumed direction of the result.

## 6. Implement, validate, and run v2

- [x] Implement the versioned system-grouped split algorithm without altering v1 behavior.
- [x] Add meaningful checks for system separation, composition disjointness, deterministic membership, and isolation from evaluation labels.
- [x] Split `src/mp_pu.jl` only if the new implementation needs clearer boundaries between verification, ranking, metrics, and reporting; file length alone is not a requirement to refactor.
- [x] Run random, popularity, and similarity under v2 on the frozen snapshot.
- [x] Run the predefined diagnostics and any matched-size controls.
- [x] Reproduce the required outputs from the captured environment.
- [x] Report v1 and v2 side by side, including population differences and similarity distributions.
- [x] Explain whether the advantage shrinks, persists, or reverses, without assuming any change proves the removal of chemical analogues.
- [x] If label sensitivity was material, carry the relevant alternative policies into v2 or explicitly restrict the scope of the conclusion.

**Done when:** the protocol difference is quantified, reproducible, and interpreted with its population and representation differences visible.

## 7. Decide whether a learned comparator is worth building

Phase 03 is optional. Make this decision from the remaining research question, available time, and the results of Steps 4–6.

- [ ] Write the specific question a learned comparator would answer beyond the existing methods.
- [ ] Specify one initial matrix/tensor representation, its axes, objective, and regularisation.
- [ ] State how unobserved entries are handled without silently treating them as verified negatives.
- [ ] Specify how the model scores every eligible candidate, including systems or entities without a fitted latent factor.
- [ ] Define hyperparameter selection using training information only, with any internal validation separated from final evaluation labels.
- [ ] Build a small end-to-end feasibility demonstration with synthetic or training-only data.
- [ ] Confirm coverage, runtime, reproducibility, and that the chosen representation supports the intended holdout task.
- [ ] Make a written go/no-go decision and update the effort estimate. Do not commit to the original 30-hour estimate before this gate.

**Done when:** a viable model specification and demonstration justify the work, or a documented decision defers it.

## 8. If justified, fit and evaluate the learned comparator

- [ ] Explicitly amend the documented scope that currently excludes Tucker/CP/NMF/SVD training.
- [ ] Fit independently within each outer split, using only permitted training information.
- [ ] Isolate preprocessing, feature fitting, model selection, and caches as well as model fitting.
- [ ] Verify that changing evaluation labels cannot change the fitted model or its scores when permitted training inputs are fixed.
- [ ] Test the predefined behavior for unseen systems/entities and record scoring coverage; do not silently drop unscorable candidates.
- [ ] Freeze the learned-method configuration before final evaluation.
- [ ] Compare against random, popularity, and similarity under both holdout designs, preserving the same eligible candidate populations within each comparison.
- [ ] Include relevant label-sensitivity analysis where needed to support the conclusions.
- [ ] Describe the method as an implementation in the same model family, not a reproduction of or direct comparison with Seko's published model.

**Done when:** the learned method runs reproducibly, passes isolation checks, and answers the stated additional question.

## 9. Package the evidence and reassess the next commitment

- [ ] Assemble protocols, environment records, run identifiers, validation instructions, and results into a coherent report/package.
- [ ] Separate frozen analyses, exploratory diagnostics, measured observations, and hypotheses.
- [ ] State the limits of the provenance label, random composition holdout, and system holdout.
- [ ] Include unfavourable, null, and contradictory results under the same reporting rules.
- [ ] Release only artifacts cleared in Step 3; retain unresolved categories locally.
- [ ] Replace provisional estimates with observed effort and runtime before planning further work.

**Done when:** a reader can understand and reproduce the permitted evidence without inferring synthesis success or unsupported discovery claims.

## Rules that apply throughout

- If leakage or a normalisation defect is found, version the correction, preserve an audit trail, and rerun every affected method. Do not retain a favourable invalid result as the headline.
- Do not tune methods or redesign protocols to obtain an expected collapse or advantage. Treat changes after inspection as exploratory or freeze a new experiment.
- Do not infer first-publication dates from MP creation timestamps. Defer temporal evaluation until a defensible source exists.
- Keep the chemistry scope at oxygen-containing ternaries unless an explicit new protocol changes it; do not imply these are all validated oxides.
- Defer dashboards, unrelated CLI work, broader chemistry, and full reproduction of the external published model.
- If time becomes scarce, prioritise the pilot, label sensitivity, the environment record, and the licensing/sharing decisions. Defer system holdout and model development explicitly.

## Supporting reference

The distinction between a nominal chemistry holdout and extrapolation in representation space is discussed in [Probing out-of-distribution generalization in machine learning for materials](https://www.nature.com/articles/s43246-024-00731-w). It motivates the similarity diagnostic; it does not predict this project's result.
