# MP element-pair factor comparator protocol

**Protocol ID:** `eka-mp-element-pair-v1`

**Frozen:** 31 August 2026, after synthetic feasibility and before any real-data
factor-model fitting, ranking or metric inspection. This prospective extension
leaves the earlier pilot, label-sensitivity and system-holdout protocols intact.

## Question and fixed model

Does a low-rank model of non-oxygen element co-occurrence improve held-out
experimental-provenance recovery over training-element popularity, and how does
that comparison differ across composition and system holdout and label policies?
This is an additional model-family comparator, not a Seko reproduction.

Model ID `eka-element-pair-symnmf-v1` uses the exact representation, objective,
initialization and projected-gradient algorithm in the separately captured
feasibility specification. Fix rank=4, missing_weight=0.01,
regularization=0.01, initialization seed=20260902, max_iterations=2000,
tolerance=1e-4 and ranking tie seed=20260901. No tuning, restart selection or
post-result increase in iterations. The following restates the scientific contract.

Axes are the 117 non-O elements sorted alphabetically. Each unique training
composition increments its unordered pair of non-O elements once. With T training
compositions and pair count C_ab, target Y_ab=log1p(C_ab)/log1p(T).
For a<b minimize:

`0.5 sum_ab w_ab (dot(F_a,F_b)-Y_ab)^2 + 0.5 lambda sum_ak F_ak^2`, `F>=0`.

Observed-pair weight is 1; unobserved-pair weight is 0.01. Diagonals are omitted.
Unobserved entries are low-confidence zero-target associations, not verified
negative compounds. This is a modeling assumption, not an unbiased PU objective.

Observed-element initial factor entry is `(0.5+u)/sqrt(10*rank)`, where u is the
integer represented by the first 13 hexadecimal digits of SHA256 of
`model_id + "\n" + seed + "\n" + element + "\n" + factor_index`, divided by 2^52.
Unseen rows start and remain zero. Use Float64 and the explicit deterministic
loop order in the captured implementation; no BLAS or global RNG dependence.
Projected gradient has Armijo coefficient 1e-4, initial step 1, halving up to
60 trials, and next trial step min(1,twice last accepted step). The residual is
norm(F-max(0,F-gradient)); threshold is tolerance*max(1,initial residual).

Synthetic feasibility found that the size case hit the iteration cap. Therefore
this experiment explicitly evaluates a **fixed-compute optimization state**:
use a valid finite state at the cap, label it `iteration_limit`, and retain the
entire objective/residual trace. Report convergence/cap counts by branch. Do not
claim a global optimum or converged model when the tolerance was not met.
Nonfinite state or failed line search fails the whole experiment; never skip it.

Score each candidate by its two factor rows' dot product. Unknown training
elements receive zero and a coverage flag, without dropping the candidate.
Scores are associations, not synthesis probabilities. All stoichiometries in a
system share a score. Resolve ties with the unchanged v1 tie hash/formula rule.
Report distinct score counts, tied-candidate count and cold-element counts.

## Inputs, membership and isolation

Use the same verified snapshot/audit as v2, with its frozen input hashes and
oxygen-containing ternary scope. GNoME stays excluded. Use both `composition`
and `system` designs, all three full-pipeline policies (`original`,
`exclude_mixed`, `unlabel_mixed`), split seeds 0–19 and budgets 20,50,100,200.
Reconstruct every membership under the frozen v2 rules; require exact equality
with the saved v2 training, candidate, held-out and evaluation-label files.

Verify the v2 output inventory against a pre-evaluation pinned config hash and
recheck each source hash. Treat saved reference scores/metrics as fixed controls;
prior v2 verification and full reproduction are prerequisites. Any changed v2
artifact, even with a rewritten internal checksum, must fail the config pin.
Synthetic runs allow smaller budgets/seeds and do not use the real baseline pin.

Fit each branch/split independently from its training formulas and fixed settings.
No candidate membership, labels, IDs or whole-data fitted state enters fitting.
All preprocessing is training-only; the element vocabulary is predefined. No
hyperparameter search or inner selection is performed. A future tuned model needs
a new protocol specifying training-only inner pools and selection.

Both alternative policies have identical training membership within each design
and seed. Refit separately anyway, and require exact factor/trace equality and
shared-candidate score/order invariance. Candidate additions and evaluation-label
changes cannot affect fitted state. Never change previous baseline algorithms,
rankings, eligible candidates or budgets.

## Evaluation and diagnostics

Attach held-out labels only after scoring. Report the unchanged PU metrics for
every learned ranking: H@k, H@k/k, H@k/h, enrichment and k*h/N random expectation.
The new model contributes 2*3*20*4=480 metric rows and 120 full rankings/fits.
Keep the 1,440 reference metric rows available in captured baseline evidence.

Primary effect is learned-model Hits@100 minus popularity Hits@100 within each
identical branch/split. Report all 20 differences per branch, their mean, median,
range and positive/zero/negative counts. Model-minus-similarity is secondary;
also report random realization and expectation and all secondary budgets.
No favorable branch, policy, initialization or iteration checkpoint may be selected
post hoc. Report training/candidate/positive counts and prevalence beside effects.

For each fit preserve training hash, parameters, active elements, pair counts,
factors, objective/residual trace and termination. For rankings report coverage
flags and observed-training-pair flags. Report every branch's convergence/cap
counts, iteration range, cold candidates, distinct scores and tied candidates.
No confidence intervals or significance claims: outer splits overlap.

Compare both designs under each label policy without a causal chemical-separation
claim; populations differ. Low-rank associations ignore stoichiometry and may
encode historical research frequency. Unlabelled does not mean failed synthesis.
A favorable result only supports this fixed-compute representation on this
benchmark. An unfavorable result is retained and does not trigger tuning.

## Reproduction and reporting decision

Before real fitting, record this protocol hash, exact implementation/environment
and the baseline config hash. Run meaningful synthetic objective/gradient,
coverage, label-isolation and complete workflow checks. Save all outputs only in
new directories. Independently recalculate scores from saved factors, reconstruct
memberships and metric denominators, check ranking and common-candidate invariance,
and compare a complete rerun from the captured implementation/environment.
Separate runtime from deterministic outputs. Preserve all earlier sealed evidence.

After results, package favorable, null and unfavorable comparisons alike. Do not
extend model development merely to obtain a win. Any further model or convergence
study requires its own question and prospective protocol. Retain detailed data
locally while preparing an attributed summary under the separate terms review.
