# Local performance check

Measured on 2026-08-30, using Julia 1.12.6 on the local macOS machine with SQLite.jl 1.8.2, DBInterface.jl 2.7.0, and ArgParse.jl 1.2.0. The input is the included **12-row synthetic fixture**, with elements `Al Si O`, arity 4, and threshold 0.01 (five results).

These are exploratory measurements, not a statistically controlled benchmark. The first table records the initial fixture-based implementation. Production measurements after the schema-adapter work appear below.

| Measurement | Before representative precompilation | After representative precompilation |
| --- | ---: | ---: |
| First query timed inside a new process | 142.387 ms | 6.169 ms |
| Warm query minimum, 20 samples | 0.245 ms | 0.238 ms |
| Warm query middle sample, 20 samples | 0.265 ms | 0.274 ms |
| Fresh CLI process, wall time | 1.67 s | 0.23 s, 0.23 s |
| First timed query allocations | 13,394,512 bytes | 86,336 bytes |
| Warm query allocations | 51,616 bytes | 51,616 bytes |

The warm differences are too small to interpret as improvements or regressions. The material improvement here is startup/first-use latency, not the query algorithm. The package's own precompilation step took approximately two seconds after the workload was added; dependency installation and initial dependency precompilation are additional costs.

## Method

```bash
julia --startup-file=no --project=. scripts/benchmark_query.jl
/usr/bin/time -p julia --startup-file=no --project=. bin/eka -e Al Si O -n 4 -d test/fixtures/tiny_test.db
```

The internal `@timed` measurements include connection opening, header/schema checks, parameterized SQL execution, formula parsing, element/arity filtering, sorting, and connection cleanup. They exclude Julia process startup, loading `Eka`, and compilation that occurs before the timed expression. The separate shell measurement includes the whole CLI process but was taken after package precompilation completed.

Warm measurements reuse a Julia process, not a database connection; every call opens and closes its own connection. They may benefit from the OS filesystem cache. The first process measurement is not a cold-disk measurement.

`src/precompile.jl` runs a small representative workload during package precompilation using a private temporary database. It does not read user datasets or write into the repository. Cached code reduces first-use latency across Julia processes; it does not eliminate startup or OS-specific variation.

The parser returns concrete `Composition` values, scored rows become `Tuple{Composition,Float64}`, and filtering operates after the dynamically typed SQLite boundary. Tests include inference checks for construction, canonical-string access, row parsing, and filter matching. This is not a claim that every instruction in the SQLite/CLI path is free from dynamic dispatch.

## Production measurement after schema adaptation

Using the upstream database identified in `production-validation.md`, on the same local Julia 1.12.6 setup, with elements Al/Si/O, nary 4, and inclusive threshold 0.01:

- 1,108 returned records.
- First internally timed query: 123.712 ms, 12,733,760 allocated bytes.
- Minimum of 20 warm queries: 103.637 ms.
- Middle warm sample: 106.367 ms, 11,096,672 allocated bytes.
- Full streaming audit of 4,736,551 rows: approximately 39 seconds in one run; unsupported records are reported separately, not repaired.

These observations came from an exploratory session that also ran validation work, not a controlled isolated benchmark. No statistical speedup claim is made from these samples. Unlike the standard fixture, the legacy adapter can push exact element filters into SQL and avoid parsing unrelated records. The source database has no indexes; scans remain necessary and the source was not modified to add any.

## Next measurement

Compare representative high and low thresholds and different arities in an isolated benchmark session, recording checksum, machine details, Julia/package versions, and repeated full-process timings. Standard-table queries still apply element/arity filters in Julia, while legacy queries use explicit element columns. Profile before adding a separately built indexed store or caching. Isotope-aware queries also require an explicit representation decision, not a performance workaround that silently discards unsupported records.
