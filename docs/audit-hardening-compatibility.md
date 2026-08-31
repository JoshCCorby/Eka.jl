# Audit hardening compatibility check

Reviewed 31 August 2026 after commit `b1d3ef5` strengthened the MP snapshot and
source-release audits. The change requires complete exporter metadata, parses the
preserved JSONL records, independently normalizes them, and reconciles them with
the saved TSV. It also rejects non-regular members in source archives.

## Frozen snapshot result

The hardened audit completed against the frozen 24,020-record snapshot without
an API query. It reported 5,359 positive, 7,147 unlabelled and zero unresolved
composition groups. Its scientific artifacts matched the frozen v1 audit byte
for byte:

| Artifact | SHA-256 | Frozen match |
| --- | --- | --- |
| `compositions.tsv` | `722ecf2e40a99c59b0f024219782a1fe8791f000353cd5e6cf7faa1ef6e5213d` | yes |
| `excluded.tsv` | `99bd23253455f17375178383f501e8ee46af77776f675e17cff11c9fe7ab46cb` | yes |

Every one of the 81 scientific membership files in the frozen v1 split bundle
also matched a newly generated bundle: training compositions, candidates,
held-out compositions, evaluation labels and the unresolved-group file across
all 20 splits. The only `audit.toml` difference was `audit_code_sha256`, changing
from the historical implementation hash
`40e758732869135283d7ef450c8125d193b8696101a459d08c3d179297a2d345`
to the hardened implementation hash
`e7d3c274e0fa0cf12ca6301688e9a5b3f8d526f602793e14d6370bcb2f244c6e`.

The compatibility run then executed all 20 splits, four budgets and the random,
popularity and similarity methods through the hardened loader. All 60 complete
ranking files and `metrics.tsv` matched the frozen v1 results byte for byte. The
metrics hash remained
`2c0607f62f9dcf073c57b1ff754bdb77dbff7876bed1667e3b63fce4a26c4907`.

The frozen real v1 loader continues to require the exact historical audit file
hash and all frozen input hashes. It permits that pinned report to retain its
historical implementation hash while current code must reconstruct every other
schema, provenance, count, grouping and exclusion field. Synthetic and new audit
artifacts continue to require their current implementation identity.

## Decision

No normalization mismatch was found in the frozen snapshot. The hardened audit
does not change composition groups or experimental membership, and no ranking,
metric or model-fitting source changed. The completed random, popularity,
similarity and element-pair results therefore remain the frozen evidence. The v1
compatibility rerun confirms identical simple-method results; it is verification,
not a replacement experiment or an additional replicate.

The full local Julia and Python suites passed after the change, and the exact
source archive passed its content audit. GitHub Actions run
[`33446865634`](https://github.com/JoshCCorby/Eka.jl/actions/runs/33446865634)
passed on Linux, macOS and Windows configurations for `b1d3ef5`.

This check establishes internal compatibility and file consistency. It does not
authenticate the upstream service, re-query Materials Project, expand data-sharing
permission, or turn the provenance proxy into verified synthesis evidence.
