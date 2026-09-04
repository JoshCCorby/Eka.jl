# Contributing to EkaCompositions.jl

## Scope and expectations

Eka is research software for ranking canonical chemical compositions and evaluating reproducible recovery experiments. Contributions should preserve:

- Read-only query behaviour and strict validation of formulas and scores.
- Deterministic outputs (seeds, ordering rules, hashes, protocol IDs).
- The distinction between unlabelled and negative outcomes.
- Leakage-safe evaluation (ranking before label attachment).
- Synthetic examples as software demonstrations, not scientific evidence.

## How to contribute

### Reporting issues

Use GitHub Issues for:

- Bugs in composition parsing, database access, ranking, or benchmarks.
- Reproducibility problems (non-deterministic outputs, seed sensitivity).
- Documentation gaps or unclear scientific limitations.
- Proposed changes to protocols, label policies, or evaluation design.

Include:

- Eka version or commit hash.
- Julia and Python versions.
- Exact commands and outputs (or CI links).
- A minimal reproduction when possible.

### Pull requests

1. Fork the repository and create a branch from `main`.
2. Make focused changes; avoid large, unrelated refactors.
3. Run the test suites locally:
   ```bash
   julia --project=. -e 'using Pkg; Pkg.test()'
   python3 -m unittest discover -s test -p 'test_*.py'
   python3 scripts/verify_release.py
   ```
   The third is the release gate. It must report `"status": "pass"` with an empty `problems` list. It rejects any file named `Manifest.toml` or `.env` at any depth, any tracked file containing an absolute home-directory path, files over 2 MB, and anything under `data/`, `logs/` or `reports/`. Keep documentation examples on relative or placeholder paths.
4. Update documentation if you change user-facing behaviour, protocols, or scientific interpretation.
5. Open a PR describing:
   - The problem or question addressed.
   - The changes made.
   - How to verify the change (commands, expected results).
   - Any remaining limitations or risks.

CI will run Julia tests on multiple platforms and Python tests across versions. All checks must pass before merging.

## Coding conventions

- Follow existing module structure and naming in `src/`.
- Prefer small, explicit functions and documented invariants.
- Do not relax validation or provenance checks to accommodate bad data.
- Keep CLI output formats stable within a release series; document any change.
- Preserve deterministic behaviour; do not introduce hidden global randomness.
- See [API stability](docs/api-stability.md) for which exported names are stable, which have stable command-line behaviour but unstable Julia signatures, and which are experimental. Adding an exported name without classifying it there fails `test/test_api.jl`.

## Frozen files

Two categories of file cannot be edited or moved in an ordinary pull request.

**Protocol documents.** Four documents in `docs/` are pinned by content hash in `src/mp_recovery.jl`, and the package throws if their bytes change: `mp-recovery-protocol.md`, `mp-label-sensitivity-protocol.md`, `mp-system-holdout-protocol.md` and `mp-element-pair-protocol.md`. Never edit, move, rename or reformat them. A protocol that needs to change is a *new* protocol with a new identifier and a new pin, leaving the old one intact. This is what lets a result reference the exact rules it was produced under.

**Paths recorded in provenance manifests.** Twenty-three paths — eleven under `src/`, six scripts, five documents and `Project.toml` — have their exact bytes hashed into the `implementation_hashes` of every generated result bundle. Moving one silently makes new runs incomparable with earlier ones; the guard in `test/test_mp_element_pair.jl` fails if a recorded path stops resolving. For the same reason, do not run a formatter over `src/`: a whole-file reformat churns recorded hashes for no benefit.

## Dependency updates

Eka uses two automated tools for dependency management:

- **Dependabot** for GitHub Actions workflow versions. It is deliberately not configured for `scripts/requirements-mp.txt`, which pins an optional client on purpose.
- **CompatHelper** for Julia `[compat]` entries.

To keep the commit history on `main` authored by humans and to maintain a clear audit trail:

- **Do not merge bot PRs directly.**
- Use Dependabot and CompatHelper PRs as **notifications** of outdated dependencies.
- When you decide an update is appropriate:
  - Make the version or `[compat]` change yourself in a new commit authored by you.
  - Close the bot PR without merging.
- If you choose to accept a bot PR, **squash-merge** it so that `main` receives a single commit authored by you rather than multiple bot-authored commits.

This policy applies to both GitHub Actions workflow updates and library version bumps.

## Scientific contributions

For new evaluation workflows (e.g. new holdout designs, label policies, or ranking methods):

1. Start with a **new** protocol document in `docs/` describing:
   - Scientific question and falsifiable claim.
   - Target population, pool, and label definition.
   - Data sources, permissions, and provenance.
   - Split/holdout design, budgets, metrics, and seeds.
   - What would count as failure.
2. Implement the protocol in `scripts/` or `src/` under `EkaCompositions.Research` if it is experimental.
3. Provide independent verification (e.g. Python re-analysis) where applicable.
4. Document limitations and scope explicitly; avoid language that implies stability, synthesizability, or discovery beyond the defined experiment.

Results obtained by changing code until the numbers improve are not evidence. Write the protocol first, including what would count as a negative result. A useful negative or inconclusive result counts as success.

## Data and licensing

Do not commit real snapshots, record-level results, rankings, factors, API keys or complete dependency environments. Local research data belongs in the ignored `data/local/` and `reports/local/` directories. Original Eka code is MIT; reused material carries its own [third-party notices](THIRD_PARTY_NOTICES.md), and the MIT licence grants no redistribution rights over Materials Project or Seko datasets. Anything record-level needs its own review under the [publication permissions register](docs/publication-permissions.md).

## Roadmap

Planned engineering work is in the [engineering roadmap](docs/engineering-roadmap.md); scientific sequencing is in the [recovery roadmap](docs/recovery-roadmap.md).

## Code of conduct

Contributions should be respectful and constructive. This project follows the general norms of the Julia and scientific-computing communities: be courteous, assume good faith, and focus on reproducible, well-documented science.
