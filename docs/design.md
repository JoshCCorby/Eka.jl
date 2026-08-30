# Scope and engineering decisions

This project explores the software engineering around composition recommendation: reliable querying, explicit ranking methods, and reproducible data handling. It does not reproduce the original research model, validate its scientific conclusions, or claim superiority over newer recommendation methods. The research and database are credited in the README.

## Keep three operations distinct

1. **Querying:** retrieve existing composition scores with explicit filters and deterministic output.
2. **Reordering:** compare compositions to a chosen reference using a clearly defined, untrained cosine metric. Stored model scores remain intact and separately labelled.
3. **Ingestion:** rebuild the software's query store from records that already carry scores. Normalization and validation cannot manufacture scientific predictions from an unscored materials dataset.

Tucker/CP/NMF/SVD training is deliberately outside the project scope. The engineering focus is schema adaptation, multiple dispatch, scientific data validation, safe imports, and measured performance.

## Real-data lessons

- The source is partitioned by arity, not a single composition table. A named schema adapter makes that difference explicit and keeps SQL filtering close to the data.
- Four/five-species source tables cover ionic compositions only. The CLI reports that limitation rather than implying complete chemical-space coverage.
- Scores can exceed 1. No probability interpretation is assigned to them.
- The original script uses a strict threshold. The MVP's inclusive default is retained, with an explicit strict option and boundary tests.
- The source contains isotope labels such as `D`/`T` and other nonstandard tokens such as `Bx`/`Cz`. Those are outside the element-only type's contract. Full audits report unsupported records; queries and imports remain strict. Source conventions must be established before adding an adapter. Converting labels to standard elements, silently skipping them, or adding isotope semantics would be a separate design decision.

## Import integrity

The default duplicate policy is an error because proportional formulas may collapse to one composition with different stored scores. An explicit keep policy preserves separate records. The importer retains original formulas and row order instead of losing the trail back to source data.

Publication occurs only after transaction commit and a full audit. A same-filesystem hard link is used as a no-clobber publish operation: it cannot replace an existing destination, including one created concurrently. The temporary link is cleaned up afterwards. Filesystems without hard-link support fail safely; no overwrite fallback is attempted. This provides atomic visibility, not a claim of power-loss durability across all operating systems/filesystems.

Only SHA from Julia's standard library was added for checksums. The existing PrecompileTools dependency remains justified by the recorded startup-latency improvement; Printf formats the stable CLI output. Cosine similarity is implemented directly and needs neither an ML framework nor a linear-algebra dependency.

## Extension point

New `AbstractRankingMethod` subtypes implement `ranking_value(method, composition, stored_score)`. Ranking evaluates each candidate once and handles deterministic tie-breaking centrally. Database adapters and source-score filters do not need to know which strategy is selected. A future learned method must document its own training data and evaluation rather than inheriting meaning from the existing scores.
