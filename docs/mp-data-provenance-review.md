# MP pilot: data and provenance review

Reviewed 31 August 2026 for the [recovery protocol](mp-recovery-protocol.md).
**Decision: continue the local pilot; redistribution is not cleared.** This is a
research handling record, not a legal opinion or blanket licence grant.

Follow-up on 31 August 2026: the [publication-permissions register](publication-permissions.md)
now records each proposed artifact category, dependency evidence and remaining
owner/provider decisions. The official terms page remained on browser security
verification. A clarification request is drafted locally but has not been sent;
no field or derivative has been cleared by assuming a missing permission grant.

## Provenance interpretation

The installed emmet-core 0.87.2 `emmet/core/provenance.py` and the upstream `main`
file retrieved on this date are byte-identical, SHA-256
`1bdc53348b95c93091559426881d7d39ab174cdae34b77a923414587abe8bb75`.
In `ProvenanceDoc.from_SNLs`, experimental history is aggregated with `any`, and
`theoretical` is its negation; database identifiers are collected separately.
This supports preserving explicit flags rather than deriving a label from an
identifier's presence. This file comparison does not establish the server's
builder version or verify the source literature.
[Source implementation](https://github.com/materialsproject/emmet/blob/main/emmet-core/emmet/core/provenance.py).

Day 1 verified preserved JSONL, normalized TSV, group membership, labels, counts,
and source-ID serialization. The predetermined sample uses five positive-only,
five unlabelled, and five mixed-flag groups, hash-sampled with seed 20260831.
Source records and findings remain in the ignored local review folder. This is a
consistency review, not a manual literature check or certification of synthesis.
No label rule was changed and no ranking performance was inspected.

## Separate software, data, and source rights

| Area | Evidence / limitation | Handling decision |
| --- | --- | --- |
| Eka code | No repository LICENSE or COPYING file was found in the tracked files or top-level search. Dependency licences do not license Eka or its input data. | Do not invent or apply a software licence. Resolve an explicit code licence before describing a package as licensed for public reuse. |
| MP terms | The MP-managed AWS registry points to MP Terms of Use. Direct retrieval of the current terms page failed, including an HTTP 403 response through the web reader. | Record the gap. Do not mark all exported fields or derived outputs cleared. |
| MP attribution | The MP-managed registry links the Jain et al. Materials Project paper. The official legacy API documentation lists the Ong et al. API paper, but is not current API terms. | Preserve MP source, database version, retrieval time, processing changes, and relevant citations. Verify current citation requirements before publication. |
| GNoME | MP release notes explicitly identify a BY-NC licence and access acceptance for GNoME data. The snapshot query excludes GNoME. | Preserve the exclusion; it does not establish uniform rights for all remaining sources. |
| External database IDs | `database_IDs` can name third-party sources. Retaining an MP-provided ID does not grant access to, or redistribution rights over, its source database. | Do not download or republish ICSD/Pauling source records under assumed MP rights. Specific identifier/field and derivative permissions remain unresolved. |
| CC BY 4.0 | Where applicable, the CC deed requires credit, a licence link, and an indication of changes, without implying endorsement; other rights may remain. | These conditions do not establish that every field in this snapshot is covered. Apply only after coverage is confirmed. |

Sources consulted:

- [MP-managed data registry](https://registry.opendata.aws/materials-project/): terms link and project citation. This pilot used the API, not AWS; do not claim an AWS retrieval.
- [MP Terms of Use](https://materialsproject.org/about/terms): current text could not be retrieved; still requires review.
- [MP database release notes](https://docs.materialsproject.org/changes/database-versions): GNoME restrictions, notably the v2024.12.18 entry. Search-accessible content was inspected; direct local retrieval failed.
- [Official legacy API documentation](https://github.com/materialsproject/mapidoc): API citation, explicitly an older API reference.
- [CC BY 4.0 deed](https://creativecommons.org/licenses/by/4.0/): general attribution conditions, not dataset-specific clearance.

Do not substitute an old snapshot licence, a search snippet, a website footer,
or a software licence for the applicable current dataset/source terms. A direct
source-terms review for ICSD and Pauling remains open; no assertion is made that
their direct-service contracts automatically govern this MP export.

## Field handling and publication gate

The export retains `material_id`, `composition`, `formula_pretty`, `theoretical`,
`database_IDs`, and `deprecated`. Only canonical composition is a candidate
feature; training membership comes from the frozen grouping rule. IDs and flags
are for provenance/evaluation, never predictive features. No original crystal
structures or bibliographic abstracts were requested by this export.

For now **none of the exported fields is cleared for redistribution by this
review**. Preserve the frozen originals locally; keep record-level files, samples,
coverage tables, splits, rankings, and derived results in ignored directories.
Code, synthetic fixtures, and methodological documentation can be prepared
separately, subject to the code-licence decision and a final sharing review.
Nothing has been published or sent to source providers.

Before sharing data or a data-derived summary:

1. Retrieve and review the current MP terms and any applicable contribution terms;
   record review date and the exact field/output classes covered.
2. Resolve the handling of external source identifiers and any source restrictions,
   distinguishing MP-provided metadata from original third-party records.
3. Record approved attribution, licence links, source version/date, and a statement
   of canonicalization, grouping, splitting, and other modifications.
4. Resolve Eka's code licence separately; review intended files for credentials,
   raw data, local environments, and unreviewed derivatives.

Until then, the release fallback is a prepared code/synthetic-input package with
no unreviewed data derivatives. These open distribution questions do not require
new MP API access or a change to the scientific label rule.
