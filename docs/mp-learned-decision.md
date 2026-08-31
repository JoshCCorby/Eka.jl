# Learned-comparator feasibility decision

Decision recorded 31 August 2026, before real element-pair fitting/ranking.
**Go for one frozen evaluation of the fixed-compute element-pair model.**
This is not a decision that the model is scientifically useful or converged.

The [specification](mp-learned-feasibility.md) defines the question, axes,
objective, low-confidence missing-pair assumption, coverage fallback and
training-only boundaries. The [evaluation protocol](mp-element-pair-protocol.md)
freezes the model settings, 2,000-iteration cap and reporting obligations. No
hyperparameter tuning or real recovery inspection informed these settings.

Synthetic numerical checks passed, including finite-difference gradients and an
analytical stationary point. Full workflow checks cover factor-derived scores,
objective/residual consistency, membership, ranking, coverage, metrics and
rejection of rehashed corruption. Scoring does not refit or mutate the model.

On this machine, the small synthetic case reached its projected-gradient
criterion in 502 iterations. The artificial size check used 4,288 training and
9,293 candidate compositions and reached the 2,000-iteration cap. Its warm fit
took about 0.15 seconds, allocated about 86 MiB cumulatively, and ranking took
about 0.02 seconds. Allocation is not peak memory. All 9,293 candidates received
finite scores, including 4,513 with the explicit unseen-element zero fallback.
These generated cases are engineering checks, not estimates of real recovery.

The capped larger fit has not established convergence. The prospective evaluation
therefore reports each fit's stop reason, full objective trace, residual, coverage
and ties. It evaluates the fixed-compute state without claiming an optimum or
increasing iterations after seeing results. A failed line search/nonfinite state
will fail the experiment rather than silently dropping a branch.

The synthetic cost suggests roughly 20 seconds of fitting and scoring for 120
such cases, excluding input validation, file output, analysis, compilation and
reproduction. Real convergence and end-to-end runtime must be measured separately.
This replaces an unsupported 30-hour model-development commitment with one bounded
benchmark; it is not an estimate for a tuned model or production deployment.

The prototype is deliberately limited: stoichiometries within a system tie;
missing pairs are weak zero targets rather than verified negatives; cold elements
receive zero; factors may encode research frequency. A favorable benchmark result
would not remove these limitations. A negative result will be retained and will
not automatically trigger model tuning or a larger implementation.

Synthetic evidence is preserved locally under
`reports/local/element-pair-feasibility-2026-08-31/`. Numerical and workflow tests
are tracked; real scientific evidence is recorded separately.
