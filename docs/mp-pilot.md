# Materials Project recovery pilot: data audit

The pilot asks whether a ranking recovers held-out compositions with experimental
provenance within a declared pool. It does not label unexplored compositions as
failed experiments. This milestone prepares and audits a snapshot; it does **not**
itself generate train/test splits, run PU recovery metrics, fit a model, or establish
scientific performance. The separate [Day 2 split generator](mp-recovery-splits.md)
now creates verified, composition-safe membership without ranking.

## Scope and decisions

The first audit queries non-deprecated MP materials containing O and exactly two
other distinct elements, with `include_gnome=False`. This is an **oxygen-containing
ternary** pool, not a validated oxide classification. It may include hydroxides,
oxyhalides, salts, and compounds with unusual oxygen states. Review the chemical
systems in the audit before freezing a narrower oxide rule. Do not choose that
rule after inspecting which model wins.

Use MP's existing composition pool for the first feasibility check. This avoids
introducing a candidate enumeration scheme at the same time, but limits eventual
conclusions to MP-covered chemistry. There is no energy/stability threshold and no
filter on theoretical status: both experimentally referenced and other records
must be available for grouping.

The query uses MP's official client. The exporter records the actual database
version before and after querying and rejects an export spanning a release
change. It cannot request arbitrary historical releases or reconstruct discovery
years. A snapshot and its hashes are how we freeze this particular export.

## Obtain a local snapshot

Requires Julia as usual and Python 3.11+ for the optional exporter/tests. Install
the MP client in an isolated environment; it is not a Julia package dependency:

```bash
cd /Users/joshuacorbett/Coding/Eka
python3 -m venv .venv-mp
. .venv-mp/bin/activate
python -m pip install -r scripts/requirements-mp.txt
mkdir -p data/local reports/local
python scripts/export_mp_pilot.py --prompt-key --output data/local/mp-ternary-snapshot
```

Get an API key from your Materials Project account. `--prompt-key` reads it
without echoing or saving it, and requires a real terminal. Alternatively configure
`MP_API_KEY` locally; do not paste it into chat, scripts, commits, or shell history.
The key is never included in snapshot metadata or error messages. The exporter
does not silently fall back to including GNoME if a client rejects the exclusion
option; use a client supporting `include_gnome`.

If export fails, it prints the failing stage (client initialization, version check,
query, or snapshot validation). Errors raised by the exporter include a specific
validation reason and record number where relevant. Other exceptions show only
their type and code locations, never the external exception text, request headers,
URLs, or local variable values. Share that diagnostic block to investigate; do not
share the key or a raw traceback from the client. An error type such as `ValueError`
alone does not establish that your key is invalid.

The output directory must be new and its parent must exist. Returned IDs must be
unique. All result pages are requested. Selected source records are retained in
`records.jsonl`; these are decoded API dictionaries, not original HTTP bytes.
`records.tsv` contains normalized inputs for Julia and `snapshot.toml` records
parameters, counts, versions, retrieval time, and SHA-256 hashes. Retain all three.

Ordinary failures clean up only the newly created output directory. Abrupt process
termination may leave a partial directory; hashes and required-file checks prevent
silently auditing it as a complete snapshot.

## Audit the snapshot

```bash
julia --project=. bin/eka audit-mp \
  --snapshot data/local/mp-ternary-snapshot \
  --output reports/local/mp-ternary-audit
```

The audit writes:

| File | Purpose |
| --- | --- |
| `audit.md` | Readable counts, definitions, and next decisions |
| `audit.toml` | Counts, exclusions by reason, and implementation/input hashes |
| `compositions.tsv` | Grouped compositions, labels, chemical systems, counts, source material IDs |
| `excluded.tsv` | Every excluded record and its reason |
| `snapshot.toml` | Copy of original export metadata; keep the original snapshot alongside it |

Exit 0 means the audit completed, not that the dataset is scientifically sufficient.
An empty usable subset is reported, not hidden. The estimated 20% holdout size is
`floor(number_of_positive_compositions / 5)`; it is neither a split nor a power
calculation. The `has_minimum_pilot_data` flag only means at least one positive
could be held out and one unlabelled composition is available. It is deliberately
not a scientific pass/fail threshold.

The library equivalent is `audit_mp_snapshot(snapshot_directory, new_output_directory)`.
No original files are modified. Existing reports are never overwritten.

## Composition and provenance rules

The exporter builds simple formulas from MP's `composition` element-count mapping,
not `formula_pretty`. This avoids display parentheses and preserves actual integer
counts. Only exactly integral, finite, positive counts within the supported integer
range are accepted; fractional occupancies are reported rather than rounded or
rationalized. Julia then validates symbols, reduces ratios, and groups equivalent
compositions. These restrictions can exclude legitimate chemistry and must be
reported as coverage limitations.

After grouping all valid records for a formula:

| Record evidence | Composition label |
| --- | --- |
| At least one explicit `theoretical=false` | `positive` |
| Every record explicitly has `theoretical=true` | `unlabelled` |
| No positive record and at least one missing flag | `unresolved` |

The positive label is an **experimental-provenance proxy**, not a manual literature
verification or proof of synthesis under a specific condition. Polymorphs can have
different flags, so a mixed true/false group is reported and labelled positive.
Source IDs are retained, including a count of records without them. Missing flags
are not converted to true. Unresolved groups must be excluded from the initial
recovery pool unless their evidence is subsequently resolved.

The audit verifies saved file hashes and schema, not upstream authenticity or a
semantic round trip between arbitrary user-edited JSON and TSV. Use the exporter
to create the TSV; do not manually alter it after export.

The grouped file is intentionally **not** input to `eka benchmark`: that existing
command has a binary-outcome contract. There is no `outcome=0` for unlabelled here.
An explicit PU recovery mode is the next implementation step.

## Decisions after the real audit

1. Verify applicable source/data terms, exclusion coverage, and provenance quality.
   GNoME exclusion is a query condition, not a certification that all remaining
   records have identical redistribution rights. Snapshots start `unreviewed` and
   stay out of Git under `data/local/`; reports under `reports/local/` are ignored too.
2. Freeze the chemistry definition, source snapshot, and candidate-generation rule.
3. Group compositions first; hold out a predetermined fraction of positives across
   predetermined seeds. Keep unresolved groups out. Never infer first-discovery
   dates from API creation/update timestamps.
4. Fit popularity and any trainable comparator on each training subset only. No
   training positives or equivalent polymorph compositions may appear in its test
   pool. Existing precomputed Seko scores remain exploratory until their training
   provenance supports the split.
5. Report observed-positive hits@k, held-out-positive recall@k, and observed-label
   enrichment with precise denominators. These do not estimate the true success
   rate of unlabelled chemistry. Compare methods on the same splits. Choose an
   uncertainty method appropriate to the split/sampling design; overlapping
   intervals do not establish that a method has no useful effect.

No win against a baseline is required for the pilot to be informative. Too little
data, unresolved provenance, or an inconclusive difference are valid findings.

## Offline verification

```bash
python3 -m unittest discover -s test -p 'test_mp_export.py' -v
julia --project=. -e 'using Pkg; Pkg.test()'
```

Exporter tests cover exact count normalization, missing provenance, query filters,
release changes, hashes, duplicate IDs, authentication prerequisites, and cleanup.
Julia tests cover equivalent formulas, mixed/missing flags, scope exclusions,
integrity failures, reproducible audits, and CLI behaviour. No tests need MP access.
Live export compatibility and real data sufficiency must still be established with
an authenticated run; mocked API tests cannot prove either.

## Sources for the protocol

- [Official MP summary client](https://github.com/materialsproject/api/blob/main/mp_api/client/routes/materials/summary.py): query fields and GNoME exclusion.
- [MP provenance implementation](https://github.com/materialsproject/emmet/blob/main/emmet-core/emmet/core/provenance.py): flags, source IDs, and timestamp semantics.
- [MP release notes](https://docs.materialsproject.org/changes/database-versions): version identification and GNoME-specific restrictions.
- [MP API access](https://docs.materialsproject.org/downloading-data/using-the-api): client and account setup.
- [Confidence-interval comparison](https://doi.org/10.1198/000313001317097960): limitations of judging significance from separate interval overlap.
