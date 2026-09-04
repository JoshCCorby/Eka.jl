# Contributing to Eka

Thanks for your interest. This project is a research tool as much as a software
package, so a few of its rules are unusual. The short version: software fixes are
ordinary pull requests; anything that changes what an experiment *means* needs a
protocol first.

## Setup

Requires Julia 1.10 or newer and Python 3.11 or newer. From a checkout:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

No network access is needed after installation. No database is bundled, and
nothing here downloads one.

## Tests

Run all three before opening a pull request. Continuous integration runs the same
three across Julia 1.10 and current stable on Linux, macOS and Windows, and
across Python 3.11 to 3.14.

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

```bash
python3 -m unittest discover -s test -p 'test_*.py'
```

```bash
python3 scripts/verify_release.py
```

The third is the release gate. It must report `"status": "pass"` with an empty
`problems` list. It rejects, among other things, any file named `Manifest.toml`
or `.env` at any depth, any tracked file containing an absolute home-directory
path, files over 2 MB, and anything under `data/`, `logs/` or `reports/`.

## What changes freely, and what does not

### Frozen: protocol documents

Four documents in `docs/` are pinned by content hash in
`src/mp_recovery.jl`, and the package throws if their bytes change:

- `mp-recovery-protocol.md`
- `mp-label-sensitivity-protocol.md`
- `mp-system-holdout-protocol.md`
- `mp-element-pair-protocol.md`

Never edit, move, rename or reformat them. A protocol that needs to change is a
**new protocol**: add a new identifier and a new pin, and leave the old one
intact. This is what lets a result reference the exact rules it was produced
under.

### Frozen: file paths recorded in provenance manifests

Several source and documentation paths are written as literal keys into the
`implementation_hashes` of every generated result bundle. Moving such a file
silently makes new runs incomparable with earlier ones. `test/test_api.jl` and
the provenance guard in `test/test_mp_element_pair.jl` fail if a recorded path
stops resolving, so a rename shows up as a test failure rather than as quietly
wrong metadata.

If you genuinely need to move one, treat it as a protocol change.

### Frozen: the v1 command-line surface

Six subcommands — `import`, `validate`, `benchmark`, `audit-mp`, `split-mp`,
`benchmark-pu` — plus the default query mode. Their observable behaviour is
stable for 0.1.x. New research belongs in `EkaCompositions.Research`, which is
internal, unexported and deliberately not wired into the CLI.

### Changes freely: everything else

See [API stability](docs/api-stability.md) for which exported names are stable,
which have stable command-line behaviour but unstable Julia signatures, and which
are experimental. Adding an exported name without classifying it there fails
`test/test_api.jl`.

## A software fix or a new experiment?

This is the distinction that matters most here.

A **software fix** corrects behaviour that was already meant to work: a bug, a
missing validation, a performance problem, documentation, tests, packaging. It
keeps the protocol identifier. Open a pull request.

A **new experiment** asks a question the existing protocols do not answer: a new
label policy, a different split design, another model, a changed metric or
budget. Results computed by changing code until the numbers improve are not
evidence. Write the protocol document first, stating the question, the design and
what would count as a negative result, then implement and run it. A useful
negative or inconclusive result counts as success.

If you are unsure which you have, open an issue and describe the question rather
than the patch.

## Data and licensing

Do not commit real snapshots, record-level results, rankings, factors, API keys
or complete dependency environments. Local research data belongs in the ignored
`data/local/` and `reports/local/` directories. Original Eka code is MIT; reused
material carries its own [third-party notices](THIRD_PARTY_NOTICES.md), and the
MIT licence grants no redistribution rights over Materials Project or Seko
datasets. Anything record-level needs its own review under the
[publication permissions register](docs/publication-permissions.md).

## Style

Match the surrounding code. Do not run a formatter over `src/`: the research
modules use a deliberately compressed style, and twenty-three paths across the
provenance lists (eleven under `src/`, six scripts, five documents and
`Project.toml`) have their exact bytes hashed into result manifests, so a
whole-file reformat churns recorded hashes for no benefit. Keep documentation
examples on relative or placeholder paths, never absolute ones, or the release
gate rejects them.

## Commits and pull requests

Explain why, not just what — the reasoning is usually the part that is hard to
recover later. Say which of the three test commands you ran and what they
reported. If you changed anything hashed into a manifest, say so, because it
changes recorded values for subsequent runs.

## Roadmap

Planned engineering work is in the
[engineering roadmap](docs/engineering-roadmap.md); scientific sequencing is in
the [recovery roadmap](docs/recovery-roadmap.md).
