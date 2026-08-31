# Eka: one-week MP recovery pilot roadmap

Prepared 31 August 2026 for Joshua Corbett. Planned working week: **1–7 September 2026**. Dates can move together if the start changes. Allow approximately **29 focused hours plus 4 hours of buffer**; these are planning estimates, not measured runtimes.

**End-of-week objective:** produce a reproducible, composition-level positive–unlabelled (PU) recovery benchmark on the frozen Materials Project snapshot, with trustworthy baselines, explicit leakage checks, and a readable results report. A useful negative or inconclusive result counts as success. Beating a baseline is not a release requirement.

This roadmap schedules work; it does not mean the proposed commands, splits, methods, or results already exist. It does not create scheduled reminders or background tasks.

## Starting point

The local export and audit have completed successfully. Source: `reports/local/mp-ternary-audit/audit.toml`.

| Item | Current state |
| --- | --- |
| MP database version | `2026.04.13` |
| Exported records | 24,020 |
| Unique reduced compositions | 12,506 |
| Positive compositions | 5,359; at least one record has `theoretical=false` |
| Unlabelled compositions | 7,147; all records have `theoretical=true` |
| Unresolved compositions / excluded records | 0 / 0 |
| Compositions with mixed experimental/theoretical flags | 1,343 |
| Records missing external source IDs | 15,852; this is a record count, not a count of unsupported positives |
| Scope | Oxygen plus exactly two other elements; oxide classification not verified |
| Software verification | Most recent run: 944 Julia tests and 10 Python tests passed |
| Existing benchmark | Binary-labelled ranking evaluation; cannot accept unlabelled compounds as failed outcomes |
| Data permissions | Unreviewed; raw data and local reports remain ignored by Git |
| Git state | MP exporter/audit implementation and related documentation have uncommitted changes |

The snapshot is `data/local/mp-ternary-snapshot/`. Preserve its TSV, JSONL, metadata, and hashes. There is no need to repeat the authenticated export for this week's work.

## Decisions to freeze before evaluating rankings

These are proposed defaults to confirm in the written protocol on Day 1, before inspecting real ranking results.

| Decision | Proposed week-one default |
| --- | --- |
| Research question | How well do simple composition rankings recover withheld compositions with MP experimental provenance, within MP-covered chemistry? |
| Chemistry | Keep the audited oxygen-containing ternary pool and name it accurately. If strict ternary oxides are essential, define and audit an explicit chemistry rule first; do not call an oxygen filter an oxide validator. |
| Unit | Canonical reduced composition; group all structures before splitting |
| Labels | Positive / unlabelled / unresolved; never confirmed-negative by absence |
| Split | Hold out `floor(0.20 × positives)`; retain remaining positives for training |
| Candidate pool | Held-out positives plus all eligible unlabelled compositions; exclude training positives and unresolved groups |
| Repetitions | 20 predetermined split seeds, integers 0–19; versioned deterministic selection independent of file order |
| Main budget | `k=100` |
| Secondary budgets | `k=20, 50, 200`; report all, without selecting a winning budget after the run |
| Primary comparison | Training-composition similarity versus training-element popularity, paired on each split |
| Reference | Uniform random ranking, with an exact expected-hit calculation and separately recorded random-ranking seeds |
| Ties | Shared deterministic, score-independent policy. Use a seeded formula hash to break equal scores; keep tie seed separate from split seed and freeze it. |
| Tuning | No hyperparameter search on the evaluation splits. Any later tuning needs a training-only validation partition. |
| Uncertainty | Paired per-split differences and explicitly descriptive split variability; no claim that repeated overlapping holdouts are independent experiments |
| External scores | Secondary and exploratory unless training-data independence can be established |

With the current broad pool, each split would have **4,288 training positives**, **1,071 held-out positives**, and **8,218 candidates**. The observed-positive fraction in that candidate pool is about **13.03%**. A uniform random top 100 has expected hits `100 × 1,071 / 8,218 ≈ 13.03`. These are design calculations, not measured ranking performance or statistical power. Recalculate them if the scope changes.

## Seven-day schedule

| Day | Focus | Time | Concrete deliverable |
| --- | --- | --- | --- |
| Tue 1 Sep | Freeze scope, labels, and protocol | 3 h | Versioned protocol and data/provenance review notes |
| Wed 2 Sep | Implement composition-safe splits | 5 h | Deterministic split generator, manifests, and leakage tests |
| Thu 3 Sep | Add PU metrics and baseline runner | 5 h | Separate PU API/CLI with analytically checked metrics |
| Fri 4 Sep | Add training-only comparator; assess score provenance | 5 h | Similarity comparator and external-score eligibility decision |
| Sat 5 Sep | Freeze implementation and run experiment | 4 h | Complete local results for all declared methods, seeds, and budgets |
| Sun 6 Sep | Analyze paired results and limitations | 4 h | Figures, results tables, and a candid scientific report |
| Mon 7 Sep | Reproduce, document, and package | 3 h | Reviewed, release-ready code and documentation |

### Day 1 — Freeze the scientific contract

- Review composition counts by chemical system and element, including H-containing and halogen-containing systems. Decide whether the first report retains the broad oxygen-containing scope or uses an explicit narrower rule. Record reasons without looking at model performance.
- Inspect a predetermined small sample of positive, unlabelled, and mixed-flag groups, checking the grouped output against the retained source records. Use a fixed sampling seed and record the sample IDs locally. This is a consistency check, not manual verification of every synthesis claim.
- Break down missing source IDs by provenance flag. The aggregate missing-ID count alone does not establish a label problem. Record discrepancies without silently changing the label rule.
- Review current MP terms and relevant source restrictions. Separate code licensing, allowed data fields, required attribution, and unresolved redistribution questions. If unresolved, continue local research and publish no data-derived files until reviewed.
- Write `docs/mp-recovery-protocol.md` with the frozen table above, metric definitions, exclusions, comparison methods, and permitted claims. Record the snapshot hash and date. Describe this as a protocol frozen before evaluation, not formal external preregistration.
- Review and checkpoint the existing exporter/audit changes separately from new benchmark work. Preserve Joshua Corbett as the sole commit author; source citations remain necessary and are not coauthor credits.

**Done when:** the question, chemistry, labels, splits, budgets, tie handling, and score-eligibility rules can be understood without reading implementation code. No real rankings have influenced those choices.

### Day 2 — Build and test the split generator

- Add a dedicated recovery module, for example `src/mp_recovery.jl`, consuming the audited groups and checking the original snapshot and audit provenance. Reuse composition parsing and hashing where appropriate.
- Sort canonical formulas before seeded selection. Select holdouts by a versioned deterministic procedure so input order and global random state cannot change the split.
- Save training positives, held-out positives, and candidate membership for every split under `reports/local/`. Keep evaluation labels separate from the input handed to ranking methods.
- Save manifests containing snapshot hashes, scope/protocol version, split seed, membership hashes, counts, and algorithm version. Never overwrite an existing run directory.
- Test equivalent formula normalization, duplicate rejection, train/candidate disjointness, all polymorphs remaining in one composition group, unresolved-group exclusion, empty/too-small inputs, and reproducibility after input reordering.
- Treat an inability to establish input provenance as a failure, not a warning followed by continued scoring.

**Done when:** all 20 splits can be regenerated identically and automated checks prove that no training composition, including an equivalent formula, appears in its evaluation pool. Random composition holdout does not guarantee unseen chemical systems; state that limitation.

### Day 3 — Implement explicit PU evaluation

- Add a separate public entry point, provisionally `eka benchmark-pu`; document the final interface after implementation. Keep the existing binary benchmark contract unchanged.
- Implement random ranking and the existing element-popularity definition using only each split's training positives. Use the frozen tie policy without falling back to stored model scores.
- Define observed-positive hits `H@k` as the number of held-out positives in the first `k` candidates. Report observed-label fraction `H@k / k`, held-out-positive recall `H@k / number_of_holdouts`, and observed-label enrichment `(H@k / k) / (number_of_holdouts / pool_size)`.
- Do not name observed-label fraction a measured synthesis success rate. Unlabelled top-ranked candidates are not counted as confirmed failures. Do not make specificity, false-positive rate, or ordinary negative-class accuracy the headline.
- Check tiny hand-calculated fixtures: known ordering, no hits, all holdouts recovered, tied scores, invalid budgets, and denominators. Check the random expectation analytically; use simulation only as an additional diagnostic, not a flaky pass/fail test.
- Save full rankings locally, raw per-split metrics, configuration, runtime, and a concise report. Include distinct split and ranking seed fields.

**Done when:** the PU runner produces correct metrics on synthetic fixtures, never needs fabricated negative labels, and leaves existing binary tests passing.

### Day 4 — Add a comparator with defensible training inputs

- Implement an explicitly simple comparator: for each candidate, take the maximum composition-vector cosine similarity to any training-positive composition. No selection of a reference using held-out labels; no MP provenance flags or source IDs as scoring features.
- Reuse Eka's composition similarity calculation, but do not inherit its stored-score tie breaker. Apply the protocol's shared tie rule.
- Test that changing evaluation labels cannot change scores for fixed training and candidate compositions. Check that training-derived popularity counts are recalculated per split and no full-positive-set cache leaks into them.
- Benchmark runtime on a synthetic workload of similar size. The current pool implies about 35 million candidate/training pairs per split; stream or batch comparisons instead of storing an unnecessary full matrix. Record runtime and memory before committing to optional extensions.
- Write a score-provenance note for any proposed Seko inputs: model/version, training sources, training membership or exclusions, cutoff evidence, normalization, coverage, and duplicate-score handling. A newer MP snapshot does not establish independence from the model's training data.
- Time-box that investigation to roughly 90 minutes. If evidence is insufficient, mark external scores exploratory and keep them outside the primary comparison. Do not spend the week retraining tensor factorization.
- If external scoring proceeds, inspect coverage before reading performance. Never silently drop missing scores or compare a score on one pool against a baseline on another. Declare a shared restricted pool, its positive/unlabelled coverage, and a separate analysis before evaluating it.

**Done when:** the primary experiment has random, popularity, and similarity methods with transparent training inputs. External scores have an explicit include/exclude/exploratory decision.

### Day 5 — Run the frozen experiment

- Freeze protocol and implementation versions after synthetic checks pass. Record the Git commit and dependency versions; if a run uses a dirty working tree, preserve its exact patch and hash as well.
- Run all 20 splits at all four budgets, using the same candidate membership for every primary method within each split.
- Check the expected membership counts, finite scores, complete rankings, budget validity, train/pool disjointness, file hashes, and presence of every requested result.
- Rerun one split into a separate directory and compare membership, rankings, and metrics exactly. Timestamps and runtime may differ and should be kept separate from deterministic outputs.
- Keep every declared result, including weak performance and ties. If a correctness defect appears, document it, fix it, version the implementation, and rerun all affected methods rather than keeping favorable earlier runs.
- Preserve an immutable local run directory and a small run manifest. Raw MP data, candidate-level results, and unreviewed derived outputs remain outside Git.

**Done when:** the complete planned run exists, validates, and reproduces. Completing this step does not require any method to win.

### Day 6 — Analyze what the experiment actually shows

- Lead with the predefined comparison at `k=100`: similarity minus popularity hits on each identical split. Show all 20 paired differences, their mean/median, and the number positive, zero, and negative. Report other budgets as secondary.
- Show a fixed-budget recovery plot, a paired-difference plot at 100, and a compact table with exact pool/holdout sizes. Include random expected hits and the observed random runs without treating extra random seeds as new datasets.
- Describe variability across overlapping holdouts as split sensitivity. Do not turn its standard error into a population confidence interval, bootstrap only the top-ranked rows, or interpret overlapping separate intervals as proof of no improvement.
- If formal inferential intervals are required, stop short of claiming significance until the sampling unit and dependence assumptions are justified. A descriptive pilot report is an acceptable week-one deliverable.
- Inspect declared descriptive breakdowns such as chemical system and common elements. Mark any new subgroup discovery as exploratory. Since all candidates contain oxygen, its popularity contribution is constant; report whether remaining element frequencies and large tie groups dominate ranking.
- Discuss MP coverage, historical research effort, the provenance proxy, mixed flags, formula normalization, score coverage, and shared chemical systems between training and test. Random holdout does not measure chronological discovery or transfer to wholly new chemistry.
- Write `reports/local/mp-recovery-<run-id>/report.md` and export figures as standalone SVG/PNG files. Prepare a public summary only after checking applicable redistribution requirements.

**Done when:** a reader can identify the question, exact comparison, observed effect, variability, and limits without assuming unlabelled compounds are failed syntheses.

### Day 7 — Reproduce and prepare the project for sharing

- Run the full Julia and offline Python tests, including all new recovery tests. Exercise the synthetic end-to-end CLI in CI without an API key, live MP access, or private data.
- Verify a fresh checkout can run the documented synthetic example. Reproduce the real result locally using the frozen snapshot; do not require a fresh API query to reproduce the same dataset.
- Finalize protocol, CLI usage, result interpretation, environment instructions, data-access/attribution notes, and a limitations section. Add a README link and one clearly labelled synthetic example.
- Review staged files for API keys, local environment files, production SQLite data, raw snapshots, and unreviewed derivatives. Keep code and data licensing distinct. Preserve Joshua Corbett as sole commit author without coauthor trailers.
- Prepare small coherent commits for ingestion/audit, recovery splits, metrics/comparators, and documentation. Push/share only the reviewed intended artifacts; if data permissions remain unresolved, prepare a code-only package with synthetic fixtures.
- Record the next research decision based on the complete result, not a desired outcome: better comparator, system-held-out evaluation, stricter chemistry, or better positive-source validation.

**Done when:** another person can reproduce the software behavior from public synthetic inputs, and the real local run is reproducible from its preserved snapshot and configuration.

## Boundaries and fallback decisions

| Risk | Response |
| --- | --- |
| External model training provenance cannot be verified | Finish the primary baseline/similarity experiment; label or omit external scores rather than claim a clean Seko evaluation |
| Oxide definition takes longer than expected | Keep the broad oxygen-containing scope with accurate naming, or defer the narrower run; never filter after seeing winners |
| Data terms remain unclear | Continue local work; prepare code, synthetic fixtures, and instructions without publishing unreviewed derivatives |
| Runtime is too high | Profile and batch the simple comparator; postpone optional methods and analyses. Record any protocol change before real evaluation |
| Baselines tie or similarity loses | Report the finding; do not change budgets, seeds, labels, or scope to obtain a win |
| A leakage or normalization bug is found | Correct it and rerun affected experiments; reserve the four-hour buffer for this |
| Available work time is closer to 10–15 hours | Prioritize protocol, deterministic splits, and random/popularity PU evaluation. Deliver a validated baseline pilot and explicitly defer similarity, external scores, and extended analysis |

Out of scope this week: a new machine-learning model, full Seko retraining, WBM/Matbench fallback migration, oxidation-state inference research, synthesis recommendations, DFT validation, a web dashboard, broad refactoring, and unrelated CLI features. Chemical-system-held-out validation is a useful next experiment, not a second mandatory benchmark this week.

## Completion checklist

- [ ] Scope, labels, seeds, metrics, ties, and comparisons recorded before evaluation.
- [ ] Snapshot and run provenance preserved; no credentials in artifacts.
- [ ] Canonical composition groups remain intact across train/test boundaries.
- [ ] Rankers consume only permitted training inputs and candidate features.
- [ ] Unlabelled entries remain distinct from confirmed negatives.
- [ ] All declared methods use identical pools within each comparison.
- [ ] All declared splits and budgets reported, with no winner selection.
- [ ] Deterministic rerun and synthetic end-to-end tests pass.
- [ ] Report separates observed recovery, split variability, and unsupported discovery claims.
- [ ] Distribution review completed, or unreviewed data/derivatives remain local.
- [ ] Documentation and intended commits credit Joshua Corbett as the sole author.

## Evidence and reading for implementation

The counts above come from the project's completed local audit, not the research report's estimates. The research report is background material; its proposed negative encoding, confidence-interval rule, and broad redistribution assurances are not adopted.

MP's [provenance implementation](https://github.com/materialsproject/emmet/blob/main/emmet-core/emmet/core/provenance.py) is the primary reference for interpreting provenance fields. Check the installed version as well as current upstream code before changing label semantics.

All learned preprocessing and model fitting must use training data only; this is the leakage safeguard described in the [scikit-learn common-pitfalls guide](https://scikit-learn.org/stable/common_pitfalls.html#data-leakage). This reference does not imply Eka needs a scikit-learn dependency.

Related project documents: [MP audit guide](mp-pilot.md), [existing binary benchmark contract](benchmarking.md), and [README](../README.md). The Day 1 source-terms review remains a task; this roadmap is not a legal clearance to redistribute the snapshot.
