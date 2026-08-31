# Publication permissions register

Reviewed **31 August 2026**. This is an evidence and release-handling register,
not a legal opinion. **No release is approved by this review.** Pending clearance
does not mean an artifact is legally prohibited from publication.

## Code decision and ownership limits

Keep the current work local/private for now; do not add a licence or change
repository visibility. No perpetual private-only decision or licence selection
is made on the owner's behalf. Project metadata and README identify Joshua
Corbett as author; repository history was inspected, but metadata cannot establish
absence of employment, institutional, funder, contributor or third-party rights.
No tracked LICENSE/COPYING file supplies an Eka reuse grant. Ownership confirmation
and the owner's software-licence choice remain open before code release.

The Seko research/database is separately attributed in README. That attribution
is not a right to distribute its data or to claim authorship of the original
model. No external Seko data or trained model is included in the recovery release
proposal; its score provenance remains excluded from the primary experiment.

## Materials Project terms evidence

Applicable intended source: [MP Terms of Use](https://materialsproject.org/about/terms).
The web reader could not retrieve the page. The official browser route redirected
to `next-gen.materialsproject.org` and remained on security verification; no
security challenge was bypassed and no terms were accepted. **Full terms text,
effective version/date, and the terms applicable to the API export remain
unverified.** Obtain an accessible official copy or provider clarification before
making a field-level clearance claim.

The [MP-managed AWS registry](https://registry.opendata.aws/materials-project/)
links MP terms and a provider contact. Official [AWS Open Data documentation](https://docs.materialsproject.org/downloading-data/aws-opendata)
has search-indexed text stating that both API and Open Data access are subject to
MP terms. This is evidence for which terms to review, not their substantive
permission grant. Direct documentation retrieval also failed; the indexed text
does not substitute for a current terms copy. This project's snapshot was
retrieved through the API, not AWS.

The official [FAQ](https://docs.materialsproject.org/frequently-asked-questions)
supports citing MP and the database version. Preserve the canonical MP citation,
database version, retrieval date, source route and processing changes; additional
source/property-specific requirements must be checked against applicable terms.
Previously reviewed [database release notes](https://docs.materialsproject.org/changes/database-versions)
identify GNoME-specific restrictions. GNoME was excluded by the snapshot query;
that exclusion does not establish uniform rights over every remaining field.

The retained fields under review are exactly `material_id`, `composition`,
`formula_pretty`, `theoretical`, `database_IDs`, and `deprecated`. Canonical
compositions, chemical-system labels, grouped flags, membership and metrics are
local transformations. No original third-party structures or bibliographic
abstracts were requested by this exporter. MP-provided database identifiers must
not be confused with a licence to obtain or distribute their underlying records.

## Artifact-by-artifact status

| Category | Basis established so far | Attribution / notices to preserve | Restrictions and unresolved questions | Current release status |
| --- | --- | --- | --- | --- |
| Eka code and methodological documentation | Local authorship metadata and source history; no repository licence grant | Joshua Corbett; relevant cited research | Confirm authority, obligations and any incorporated third-party code; select licence explicitly | Prepared locally; owner decision pending |
| Dependencies | Installed source licence files inspected for the recorded versions; core Julia packages below have MIT notices | Preserve each package's copyright and licence notices when distributing covered code | Wrapper licences do not cover wrapped binaries; transitive/native/Python components require artifact-specific review if bundled | Conditional component evidence only; no blanket bundle clearance |
| Synthetic fixtures and examples | Fixture builders explicitly create invented compositions/scores and synthetic source IDs; no live MP records required | Same authorship/licence decision as their source code; label synthetic outputs clearly | Confirm no copied third-party fixture data and apply the selected code/fixture terms | Separate code-only preparation possible; release decision pending |
| Aggregate results and plots | Computed locally from the frozen MP snapshot; no applicable derivative-data grant yet established | MP citation, version/date, source, protocol, transformations and limitations | Do applicable MP/source terms permit these aggregates and figures? What licence or notices apply? | Not cleared; retained locally, not declared prohibited |
| Composition records | MP API composition/formula fields; source and transformation hashes retained | MP source/version/date, composition normalization and grouping changes | Exact scope of MP grant for raw and canonical composition lists unknown | Not cleared; raw and grouped lists remain local |
| Provenance fields | MP flags, IDs and source references retained and grouped | MP attribution; third-party attribution where established | Coverage of `theoretical`, `database_IDs`, material identifiers and source restrictions unknown; do not infer underlying database rights | Not cleared; no original ICSD/Pauling records distributed |
| Other derived artifacts | Splits, candidate-level rankings, policy labels, audit tables and detailed diagnostics transform MP records | Source, protocol, hashes, representation and processing history | These may expose compositions/provenance; applicable derivative or database conditions unresolved | Not cleared; excluded from release |
| Environment and run records | Project/Manifest, source hashes and local reproduction instructions are captured | Package notices if actual sources/binaries are bundled | Review paths, source archives, logs, licences and data-bearing files separately; a lockfile is not a dependency licence | Can prepare sanitized records; final content review pending |

## Dependency evidence captured

Installed licence notices were read for ArgParse 1.2.0, DBInterface 2.7.0,
SQLite.jl 1.8.2, PrecompileTools 1.3.4, SHA 0.7.0 and TOML 1.0.3. These provide
MIT-style source-code grants with notice requirements. SQLite_jll 3.53.2+0
explicitly distinguishes its MIT wrapper code from the bundled binary's terms.
Do not extend any of those grants to Eka, MP records or a complete runtime bundle.

A local inventory of 30 Julia package source locations and discovered licence
files, plus copies/hashes of the reviewed notices, is preserved under
`reports/local/mp-label-sensitivity-v1-2026-08-31/`. It is not a completed
transitive/native/Python redistribution audit. The proposed source package should
not vendor those environments by accident.

## Open actions

1. Obtain the applicable MP terms text and version, plus clarification of the
   six retained fields and each proposed derivative class. A concrete unsent
   request is prepared locally; no message has been sent to MP or other providers.
2. Confirm code ownership/obligations and choose a software licence, or explicitly
   elect to keep the project private. Until then, retain the temporary local-only
   handling decision above.
3. Review actual proposed release contents and any bundled dependency/native
   notices. Clear only supported categories; keep unresolved artifacts excluded.

This register records every proposed category without granting publication
permission. The environment restore work is complete; Step 3's legal/source and
owner-decision gates remain open and do not silently become completed checkboxes.
