# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
