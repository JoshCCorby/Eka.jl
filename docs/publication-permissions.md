# Publication permissions register

Reviewed **31 August 2026**. This is an evidence and release-handling register,
not a legal opinion. **No release is approved by this review.** Pending clearance
does not mean an artifact is legally prohibited from publication.

## Code decision and ownership limits

Joshua Corbett selected **MIT** and confirmed that no applicable institutional
IP exceptions or assignment obligations apply to this project on 31 August
2026. On that owner declaration, the root [MIT licence](../LICENSE) is now
applied to Eka's original code, documentation and original test material.
This records the owner's confirmation, not an institutional clearance letter
or an independent legal determination. No repository visibility change is
requested. Source licensing does not clear third-party data rights.

The optional Seko SQLite database and its research are separately attributed in
README; the upstream Python script and full database are not bundled. Eight
composition/score pairs in the tiny SQLite fixture match the upstream README,
and some are repeated in examples, tests and precompilation. Earlier descriptions
of all these rows as invented were incorrect. The upstream BSD 3-Clause notice
is retained in [third-party notices](../THIRD_PARTY_NOTICES.md), with exact scope
and source revision. Original Eka code remains MIT. This is not a blanket grant
over the full database or the sources underlying it.

The recovery pilot and label-sensitivity experiments use Materials Project API
data, not Seko scores; the latter remain excluded from the primary experiment.
Frozen local evidence retains its historical text and hashes; this register
records the subsequent software-licensing decision.

## Materials Project terms evidence

The owner supplied the MP Terms of Use on 31 August 2026. The text explicitly
permits API analysis and presenting processed results with attribution, and
licenses downloaded Content under **CC BY 4.0**. The supplied text, checksum,
source caveat and application to all six retained fields are recorded in the
[terms evidence review](mp-terms-evidence.md).

This supersedes the earlier missing-text blocker. A separate provider permission
request is not required by that text for uses within its grant. The current
page/version and any specific exceptions remain to be checked for a final data
release; do not claim independent provider confirmation or apply MIT to MP data.
GNoME remains excluded, and external database identifiers do not license the
underlying third-party records. Original source records/structures are not bundled.

## Artifact-by-artifact status

| Category | Basis established so far | Attribution / notices to preserve | Restrictions and unresolved questions | Current release status |
| --- | --- | --- | --- | --- |
| Eka original code and methodological documentation | Owner confirms authority; MIT applied in root LICENSE | Joshua Corbett; MIT copyright and permission notice | Third-party material retains its own terms; this is not data clearance | Original software licensed under MIT |
| Dependencies | Installed source licence files inspected for the recorded versions; core Julia packages below have MIT notices | Preserve each package's copyright and licence notices when distributing covered code | Wrapper licences do not cover wrapped binaries; transitive/native/Python components require artifact-specific review if bundled | Conditional component evidence only; no blanket bundle clearance |
| Test fixtures and examples | Original synthetic MP/benchmark fixtures; tiny SQLite fixture includes eight Seko README pairs and four original rows | MIT for original material; retained upstream BSD notice for reused pairs | Do not label reused pairs invented or infer full-database rights; see third-party notices | Software-example notices supplied; live source datasets remain separate |
| Aggregate results and plots | Computed locally; supplied MP terms expressly allow processed results with attribution | MP citation, version/date, source, protocol, transformations and limitations | Apply attribution and transformation notices; review any specific exception and final contents | Preparation supported by supplied terms; final release review pending |
| Composition records | MP API composition/formula fields; source and transformation hashes retained | MP source/version/date, composition normalization and grouping changes | Supplied CC BY Content grant is the working basis; current-version applicability and specific exceptions remain a final review item | Preparation supported for covered content; records remain local |
| Provenance fields | MP flags, IDs and source references retained and grouped | MP attribution; third-party attribution where established | General Content grant is evidence, not field-specific provider confirmation; do not infer underlying database rights | Review source-specific notices; no original ICSD/Pauling records distributed |
| Other derived artifacts | Splits, candidate-level rankings, policy labels, audit tables and detailed diagnostics transform MP records | Source, protocol, hashes, representation and processing history | Retain CC BY attribution for covered content and identify transformations; review source-specific exceptions | Preparation supported for covered content; no automatic publication |
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

1. Use the supplied MP terms and CC BY 4.0 as the working basis for covered
   content. Before a data release, check current-version applicability, specific
   exceptions and required notices. The older blanket clarification request is
   no longer a prerequisite; it remains unsent.
2. Preserve the applied MIT licence and scoped third-party notices in source
   distributions. The owner-confirmation and code-licence decision are complete;
   further incorporated material requires its own provenance review.
3. Review actual proposed release contents and any bundled dependency/native
   notices. Clear only supported categories; keep unresolved artifacts excluded.

The environment restore and original-code licensing decisions are complete.
MP terms evidence is now recorded. Final artifact review and any specific
data/source exceptions remain separate from MIT software licensing.
