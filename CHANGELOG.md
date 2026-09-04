# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `docs/api-stability.md`: the 0.1.x public API contract. Exported names are
  classified stable, stable-command-line, or experimental; database-schema and
  generated-report-format guarantees are stated, including that `schema_version`
  is written as an integer by most producers but as a string by
  `import_compositions`, a wart deferred to 0.2.0 rather than corrected now.
- `test/test_api.jl` makes that contract executable: adding an exported name
  without classifying it fails the suite.
- Docstrings for `ranking_value`, `rank_by_score` and `rank_by_similarity`, the
  last three exported names without them. All 27 exports are now documented.
- The provenance-path guard now covers the `mp_system_holdout` and
  `mp_label_sensitivity` code lists, which hold three of the five `docs/` paths
  used as manifest keys and were previously unguarded.

### Changed

- Research modules (`mp_label_sensitivity.jl`, `mp_system_holdout.jl`,
  `element_pair_model.jl`, `mp_element_pair.jl`) are now loaded by the package as
  an internal `EkaCompositions.Research` namespace instead of being included
  manually by each script and test. Source paths are unchanged, so provenance
  manifest keys stay comparable with earlier runs; recorded
  `implementation_hashes` values change, as they do for any source edit. Nothing
  is exported and no research subcommand is added to the CLI, so the frozen v1
  query, ranking and `benchmark-pu` surfaces are unaffected.
- Removed the nested `include` calls that previously caused a single session to
  define more than one copy of `MPLabelSensitivity` and `MPSystemHoldout`.

### Added

- Tests for the maintenance and measurement scripts that previously had none:
  `benchmark_query.jl`, `benchmark_pu_similarity.jl`, `verify_production.jl` and
  `run_pair_feasibility.jl`. The system-holdout analysis test now drives
  `scripts/run_system_holdout.jl` itself rather than calling the module inline,
  so every research entry point is executed by the suite.
- Tests for `mp_element_pair.jl`, which had no coverage: protocol and baseline
  pin shape, output-overwrite guards, sibling module identity, and a check that
  every path recorded in a provenance manifest resolves on disk.

## [0.1.0] - 2026-09-04

### Added

- The `EkaCompositions` Julia package and `eka` command-line entry point.
- Canonical, validated chemical compositions with ratio reduction, deterministic
  equality and hashing, and explicit rejection of unsupported formula syntax.
- Read-only queries for standard and supported legacy SQLite score databases,
  with element, arity, and score filters plus deterministic score or
  reference-composition-similarity ranking.
- A command-line interface for querying, importing, and auditing score databases.
- Transactional TSV import of existing composition scores with duplicate policy,
  source provenance, checksums, and no-overwrite publication.
- Reproducible fixed-budget ranking benchmarks with random and training-element
  popularity baselines, full rankings, recovery metrics, and input snapshots.
- Materials Project snapshot export and audit tooling that preserves selected
  source records, groups equivalent compositions, and distinguishes positive,
  unlabelled, and unresolved provenance groups.
- Deterministic positive-unlabelled recovery splits and evaluation using random,
  training-only element-popularity, and maximum-composition-similarity methods.
- Separately versioned research workflows for positive-label sensitivity,
  chemical-system holdout, and a fixed-compute element-pair factor comparator.
- Julia-native offline synthetic snapshot generation and external-score coverage
  inspection. Python remains optional for live Materials Project export and is
  used for independent saved-output validation.
- Reproducibility documentation, synthetic examples, citation metadata,
  third-party notices, and an automated source-release content audit.

### Changed

- The offline fixture-to-evaluation example now runs entirely in Julia.

### Fixed

- Snapshot audits reconcile preserved JSONL records with normalized TSV inputs
  and verify exporter or producer metadata before recovery evaluation.
- Source-release audits reject symbolic links, hard links, special archive
  members, unreviewed data files, and machine-specific paths.

### Security

- SQLite databases are opened in read-only mode, and import and report workflows
  refuse to overwrite existing destinations.
- Materials Project exporter diagnostics withhold external exception text and
  request details that could expose API credentials.
- Release auditing checks source archives for common credential and private-key
  patterns before publication.

[Unreleased]: https://github.com/JoshCCorby/EkaCompositions.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JoshCCorby/EkaCompositions.jl/releases/tag/v0.1.0
