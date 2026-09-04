# Engineering roadmap: documentation, API contract and package quality

Prepared 4 September 2026. This covers software packaging and documentation
quality. It does not propose new science; scientific sequencing lives in the
[recovery roadmap](recovery-roadmap.md), and no item here amends a frozen
protocol.

Task 1 is complete. Tasks 2–6 are pending.

## Constraints

These bound every task below. Violating any breaks the package or the
comparability of existing evidence.

**C1. Four protocol documents are content-hash-pinned.** `recovery_protocol()`
(`src/mp_recovery.jl`) reads the document from `docs/` and throws unless its
SHA-256 matches a frozen literal: `mp-recovery-protocol.md`,
`mp-label-sensitivity-protocol.md`, `mp-system-holdout-protocol.md` and
`mp-element-pair-protocol.md`. They are never moved, renamed, reformatted or
edited. A change means a new protocol identifier and a new pin.

**C2. Five `docs/` paths are literal provenance-manifest keys.**
`src/mp_element_pair.jl` records `docs/mp-element-pair-protocol.md` and
`docs/mp-learned-feasibility.md`; `src/mp_system_holdout.jl` records
`docs/mp-recovery-protocol.md`, `docs/mp-label-sensitivity-protocol.md` and
`docs/mp-system-holdout-protocol.md`. Moving one changes manifest keys and
breaks key-for-key comparison with the baselines under `reports/local/`.
`mp-external-score-provenance.md` and `mp-pu-evaluation.md` appear only in prose
and are not constrained.

**C3. Provenance hashing is broad, and is the reason not to reformat `src/`.**
`src/mp_element_pair.jl` and `src/mp_system_holdout.jl` read and hash roughly ten
`src/*.jl` files, four scripts, two documents and `Project.toml` into
`implementation_hashes`. Any byte change to any of them changes recorded hashes.
The `.gitattributes` `text eol=lf` entries are checkout normalisation, not a
formatting guard. `src/ranking.jl` is in no list, which is why Task 1 was cheap.

**C4. Source paths under `src/` are stable by contract**, enforced by the
provenance-path test in `test/test_mp_element_pair.jl`.

**C5. The v1 command-line surface is frozen** — six subcommands plus the default
bare-query mode.

**C6. No real snapshots, record-level results or credentials enter the
repository**, enforced by `scripts/verify_release.py`.

**C7. Further release-gate rules.** `verify_release.py` rejects `Manifest.toml`
and `.env` by name at any depth, rejects any tracked file containing an absolute
home-directory path, and caps files at 2 MB. Documentation examples therefore use
relative or placeholder paths only.

## Task 1 — Public API contract (complete)

Delivered in `docs/api-stability.md` and `test/test_api.jl`: three tiers (stable,
stable command-line behaviour, experimental), database-schema and
report-format compatibility, and docstrings for the last three undocumented
exports. The provenance-path guard was extended to the `mp_system_holdout` and
`mp_label_sensitivity` lists.

## Task 2 — Package-quality automation, excluding formatting

**Aqua.jl.** Method ambiguities and unbound type parameters are already clean,
and there is no type piracy. Two prerequisites: `Random` and `Test` in
`[extras]` have no `[compat]` entries and Aqua's dependency-compat check
inspects extras, so those and `Aqua` itself need entries. Aqua's undocumented
names check relies on a Julia 1.11+ facility, so it is inert on the 1.10 job;
Task 1 having documented every export removes that asymmetry as a concern.
Adding Aqua to `Project.toml` changes recorded implementation hashes under C3.

**Coverage.** `julia-actions/julia-runtest` already collects coverage; only
processing and upload need adding, on the Ubuntu current-Julia job. A badge
follows the first real measurement, not the configuration.

**Python 3.12 and 3.13.** The four analysis test files run in the Julia `test`
job, not the exporter job, so both jobs need the version matrix or neither gains
coverage. Analysis scripts are standard-library only; the pinned `mp-api` client
is optional and not installed in continuous integration.

**Dependency automation.** Dependabot for GitHub Actions, weekly. CompatHelper
for Julia bounds. `Manifest.toml` is ignored, so there is no lockfile churn. No
pip ecosystem entry: `scripts/requirements-mp.txt` is a deliberately pinned
optional client.

## Task 3 — CONTRIBUTING.md

Setup, the three test commands, the release-gate order, and the repository's
distinctive rules: protocol documents are frozen (C1); provenance paths are
stable (C2–C4); a software fix keeps the protocol identifier while a new
scientific question needs a prospective protocol written before any run; the API
tiers from Task 1; no real data (C6); do not reformat `src/` (C3); no absolute
home paths in examples (C7).

## Task 4 — Documenter site

Canonical documents stay in `docs/`; the build never writes back to them. A new
`docs/src/` holds authored pages, and `docs/make.jl` copies documents in at build
time.

Copy **all** of `docs/`, not a subset: the protocol documents link to
`mp-data-provenance-review.md`, `production-validation.md`,
`mp-label-sensitivity.md` and `mp-pilot-reproduction.md`, and Documenter treats
unresolvable local links as errors. The landing page is authored separately
rather than pasted from the README, whose relative links do not survive the move.
The `checkdocs` setting needs an explicit decision, since the default errors on
docstrings absent from the manual.

Ignore `docs/build/`, and never commit `docs/Manifest.toml` (C7).

Executable examples are worth adding but should not be oversold. Documenter runs
Julia blocks only, so the quick-start command-line output cannot be checked this
way, and two of the three Julia blocks assert or print rather than returning a
comparable value. Both reference the fixture by a relative path that must be
rewritten for the documentation build's working directory. The realistic gain is
that documented examples still execute, not that documented output still matches.

## Task 5 — Formatting (deferred to a version boundary)

No blanket reformat. Either check formatting on changed files only, or take a
single whole-repository pass at 0.2.0 with the hash churn under C3 recorded in
the changelog.

## Task 6 — Release checklist

`docs/release-readiness.md` records a review dated before the current tree. Write
an ordered pre-tag checklist covering the three gates against the exact release
commit, then run it and update that document with real findings rather than a new
date. This runs after Tasks 2 and 4, which change `Project.toml` and add badges.

## Order

1 → 2 → 3 → 4 → 6, with 5 deferred. Each task is a separate commit.
