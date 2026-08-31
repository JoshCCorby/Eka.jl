# Session summary — 31 August 2026

This session progressed Eka from the frozen Materials Project recovery pilot
through label sensitivity and chemical-system holdout, resolved the original
software licence, and corrected source attribution. The completed implementation
changes were committed and pushed to `main` in `67f8ad0` and `260d14c`.

## Recovery pilot and label sensitivity

- Completed the original pilot: 20 splits, three methods (`random`, `popularity`,
  `similarity`) and four budgets (20, 50, 100, 200), producing 240 metric rows.
- Added an independent pilot analyzer and documented exact environment restoration.
- Froze and implemented three label policies: retain the original labels, exclude
  mixed experimental/theoretical groups, or treat those groups as unlabelled.
- Ran both evaluation-only sensitivity, which retains the original training and
  scores, and full-pipeline sensitivity, which rebuilds labels, membership and
  training-derived scores. All six branches produced 1,440 metric rows.
- Verified 1,343 mixed-flag composition groups and retained all three policies for
  the subsequent system-holdout study.
- Added versioned protocol pins, corruption checks, reproduction instructions,
  CI coverage and the revised [recovery roadmap](recovery-roadmap.md).

The original protocol and sealed evidence were preserved. See the
[pilot reproduction guide](mp-pilot-reproduction.md) and
[label-sensitivity workflow](mp-label-sensitivity.md).

## MIT licensing, attribution and MP terms

- Added the root [MIT licence](../LICENSE) for Joshua Corbett's original code,
  documentation and original test material, following the owner's confirmation
  that no applicable institutional assignment exceptions apply. This records
  the owner's declaration, not an institutional clearance letter.
- Rewrote README attribution to distinguish Eka's implementation, the optional
  Seko precomputed SQLite database, and the Materials Project API data used by
  the recovery experiments. Seko scores do not participate in these experiments.
- Identified eight SQLite test composition/score pairs that match Seko's published
  examples. Corrected the claim that all fixture rows were invented, preserved
  their BSD notice in [third-party notices](../THIRD_PARTY_NOTICES.md), and left
  fixture values unchanged.
- Corrected the stale README statement that no real-data recovery run existed.
- Recorded the owner-supplied MP terms and their checksum. The supplied text
  permits attributed processed results and licenses covered Content under
  CC BY 4.0, removing the earlier blanket missing-terms blocker.
- Kept software and data rights separate: MIT does not relicense MP or Seko data.
  Current-version applicability and specific source exceptions remain final
  release-review items; the supplied copy is not an independently retrieved
  current official page. No provider message was sent.

See the [terms evidence review](mp-terms-evidence.md) and
[publication-permissions register](publication-permissions.md).

## Chemical-system holdout v2

Froze a prospective [system-holdout protocol](mp-system-holdout-protocol.md)
before inspecting its rankings, then implemented a separate research module,
runner, independent analyzer, synthetic example and tests.

A chemical system is the sorted set of elements in a composition. Each split
selects a hash-ordered fifth of the common system universe for candidates.
Training positives lie outside those systems; unlabelled groups outside the
selected systems are omitted. All three label policies use the same system
assignments. Every branch passed feasibility checks before scoring.

The experiment compares composition and system holdout across three policies,
20 splits, three methods and four budgets: 1,440 metric rows, 360 full rankings,
120 population rows and 360 similarity summaries. It records system overlap,
prevalence, unused unlabelled groups, positive concentration and per-candidate
maximum training similarity. Every system split has zero training/candidate
system overlap. Composition controls exactly match the earlier full-pipeline
sensitivity memberships, scores, rankings and metrics.

### Primary results

Mean similarity Hits@100 minus popularity Hits@100 across the 20 splits:

| Label policy | Composition holdout | System holdout |
| --- | ---: | ---: |
| Original | +0.50 | −14.45 |
| Exclude mixed | +3.05 | −19.70 |
| Treat mixed as unlabelled | +2.80 | −15.20 |

Popularity wins in 19 of 20 system splits under every policy. Similarity also
falls below the uniform-random expected Hits@100 in all three system branches.
The earlier evaluation-only sensitivity differences were +0.50, +4.15 and +3.55;
those are separate relabelling diagnostics, not the composition controls above.

These are descriptive protocol differences, not a causal estimate of chemical
separation. System candidate pools are smaller and have higher positive prevalence;
training sizes also vary. Mean maximum elemental cosine remains about 0.956 under
system holdout, so distinct systems do not imply chemically distant candidates.
No significance, synthesis-success or universal generalization claim is made.
Unlabelled compositions are not known failed syntheses.

See the [system-holdout workflow and evidence guide](mp-system-holdout.md).

## Verification and evidence

- Final preflight suite: **4,530 Julia checks and 26 Python tests passed**.
  The Julia suite also passed in the separate reproduction checkout.
- Independent checks reconstruct memberships, random/popularity scores, ranking
  order, metric denominators, population counts and similarity summaries.
  Corrupted outputs are rejected even when their checksums are rewritten.
- Full v2 rerun: **1,472 deterministic files, the complete configuration and all
  seven analysis files reproduced exactly**, including full similarity scoring.
- Earlier evidence was reverified unchanged: 849 pilot evidence hashes and 142
  scientific comparisons; 3,160 sensitivity evidence hashes and 925 deterministic
  sensitivity outputs, plus its configuration and seven analysis files.
- The v2 local evidence inventory covers 3,068 files. Source archives, protocol
  pins, manifests, reproduction commands and checksums are preserved with it.
- Reproduction used a separate checkout, Julia 1.12.6, the captured Manifest and
  an existing package depot on the same macOS arm64 platform. Cross-platform and
  empty-depot reproducibility are not claimed. Remote CI success is not claimed
  from the local checks.

Detailed evidence remains in ignored directories under `reports/local/`:
`mp-recovery-pilot-v1-2026-08-31`, `mp-label-sensitivity-v1-2026-08-31`, and
`mp-system-holdout-v2-2026-08-31`. The v2 `REPORT.md` contains the full interpretation;
`verify_evidence.py` checks its frozen inventory and exact reproduction.
This summary includes aggregate observations only; record-level datasets,
rankings, environments and detailed evidence are not added to Git.

## Data attribution

Results use the Materials Project API snapshot of database version **2026.04.13**,
retrieved **31 August 2026 at 12:16:39 UTC**. Eka normalized and grouped compositions,
applied provenance-label policies, constructed holdouts and computed rankings
and metrics. GNoME was excluded. Preserve applicable MP and source notices for
covered content under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Materials Project reference: A. Jain et al., “Commentary: The Materials Project:
A materials genome approach to accelerating materials innovation,” *APL Materials*
1, 011002 (2013), [doi:10.1063/1.4812323](https://doi.org/10.1063/1.4812323).
No MP endorsement of this analysis is implied.

## Next decision

Roadmap steps 1, 2, 4, 5 and 6 are complete locally. Code licensing and the supplied
terms evidence are documented; final data-release review remains separate.

Next is step 7: define the specific question, representation, missing-entry
handling, unseen-system scoring and training-only model selection for any learned
comparator, then assess feasibility. No learned model was trained or automatically
approved because of the system-holdout result. A literature audit remains deferred.

## Subsequent roadmap continuation

After the work summarized above, the Windows protocol-line-ending CI issue was
fixed in `433dfbb`; all five jobs passed. The roadmap then advanced through the
learned-model feasibility, evaluation and packaging steps. A fixed-compute
nonnegative element-pair model was specified and tested, then evaluated under a
new frozen protocol across both designs and all three label policies.

The learned run adds 480 metric rows and 120 fitted models. Mean model-minus-
popularity Hits@100 is −0.20/−1.95/−1.15 for composition holdout and
+7.95/+1.35/+2.15 for system holdout (original/exclude-mixed/unlabel-mixed).
101 fits reached the predefined iteration cap; no convergence optimum is claimed.
All 992 deterministic files, the full configuration and six analysis files
reproduced exactly in a separate checkout. Local tests passed 4,568 Julia checks
and 32 Python tests. Earlier frozen evidence remains unchanged.

See [combined findings](recovery-findings.md) and the
[learned-model evidence guide](mp-element-pair.md). The earlier “next decision”
section is historical; the planned series is now complete locally, with any
further modeling requiring a separate question and design.
