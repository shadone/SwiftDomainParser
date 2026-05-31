# Synchronous PSL loading via a precompiled binary blob

Date: 2026-05-31
Status: Design approved, pending spec review

Make loading the bundled Public Suffix List **synchronous** and as cheap as
practical, by shipping the rules as a precompiled binary blob decoded once
behind a `static let`. Removes the `async`/`await`/`throws` surface that the
current API forces on every consumer.

This **supersedes one decision** in
[`2026-05-29-psl-api-redesign-design.md`](2026-05-29-psl-api-redesign-design.md):
that spec resolved Loading as an "explicit `@concurrent async throws`
factory." We reverse that here. Everything else in that spec stands.

## Motivation

The async load is the only asynchronous thing in the library, and it is the
only bundled resource still parsed from text at runtime (the IDNA mapping is
already a precompiled `.bin` loaded synchronously via a lazy `static let`). The
asyncness is friction on two axes:

1. **Call-site ergonomics.** `lookup` is a pure, instant value query, but
   obtaining a `PublicSuffixList` requires `try await`. In the Passie consumer
   that asyncness propagates all the way up: `DomainCanonicalizer.bundled()` is
   `async`, `PassieSession.loadDomainsIfNeeded()` exists only to pump it,
   `session.domains` is an `Optional` *solely* to model the "sub-second
   pre-load window," and several sync gates (menubar Enter, the WebAuthn rpId
   check) carry fallback paths that exist only for that window.

2. **Latency, supposedly.** The original async factory was justified as
   guarding a "~20 ms parse + disk I/O." A benchmark (below) shows the real
   cost of building the in-memory index is **~2 ms**, paid once. There was
   never a latency problem large enough to justify pushing async through every
   caller.

## Benchmark: what actually costs what

Measured on Apple Silicon, `-O`, warm cache, 10,210 rules. Five strategies for
getting from "nothing" to "queryable," all producing identical lookups:

| Variant | Compile | Binary Δ | First-use | Lookup | |
|---|---|---|---|---|---|
| **A** `.bin` resource → `RuleIndex` | 1.4 s | +2 KB (+185 KB resource) | 2.1 ms | 1701 ns | **chosen** |
| **B** `StaticString` base64 in binary → `RuleIndex` | 1.5 s | +250 KB | 2.4 ms | 1723 ns | runtime-identical to A |
| **C** rich `[String:[Rule]]` literal | **180 s** | **+2.43 MB** | 0.34 ms | 1598 ns | single-literal form **OOM-killed @ 249 s** |
| **D** flat `[String]` arrays | 42 s | +282 KB | 6.8 ms | 1739 ns | worse than A on every axis |
| **E** bytes-direct, no `RuleIndex` | 1.8 s | +4 KB (+209 KB resource) | 0.25 ms | 73,184 ns | naive lookup 40× slower |

Conclusions:

- **First-use cost is ~2 ms for the sane forms.** The async machinery guarded
  a cost that does not need guarding. A synchronous lazy `static let` is the
  right call.
- **`.bin` vs pregenerated `.swift` is a runtime wash.** A and B are
  indistinguishable at runtime; the disk-I/O delta is inside the noise. The
  differences are entirely compile-time and binary size, and they favor `.bin`.
- **"Static Swift data" is not free in Swift — you pay at compile time.** At
  `-O` the optimizer does bake literals into static data (C's first-use is
  actually fastest), but the bill lands as a 180 s type-check on one file, a
  2.43 MB binary, and — for the natural single-literal form — a compiler the
  optimizer cannot finish (OOM). Disqualifying for a library rebuilt in CI.
- **Zero-build (E) confirms the build was never the problem.** Eliminating the
  index saves ~1.9 ms of startup at the cost of fiddly, allocation-prone
  byte-scanning lookups. Not worth ~2 ms nobody can perceive.

The reproducible harness lives in [`../../experiments/psl-bench/`](../../experiments/psl-bench/).

## Resolved decisions

| Decision | Choice |
|---|---|
| Load model | Synchronous, lazy, process-cached `static let shared` |
| On-disk format | Precompiled little-endian binary blob `public_suffix_list.bin` |
| First-use strategy | Decode the blob once into the existing `RuleIndex` (no lookup-path change) |
| Codegen | In-package `executableTarget` reusing the real `RulesParser` (no second tokenizer → no drift) |
| Internal-type visibility | Widen parse/format types `internal` → `package` (visible to the tool, invisible to external consumers) |
| Failure of bundled blob | `preconditionFailure` — it is a build-time artifact we generate; corruption is a package defect, not a runtime condition |
| `bundled()` / `shared()` async / `SharedListCache` | **Removed** |
| `loading(from: Data)` | **Kept**, now synchronous `throws` (custom text lists still parse text) |
| Shipped `.dat` | Dropped from the app bundle; kept in-repo as the generator input + staleness-test input (located via `#filePath`) |
| Version | **3.0.0** (breaking) |

## Design

### 1. Public API

```swift
public struct PublicSuffixList: Sendable {
    public let metadata: ListMetadata

    /// Bundled list, process-cached, decoded from the binary blob on first
    /// access. Synchronous: `static let` gives lazy, thread-safe, once-only
    /// init — that is the decode-on-first-use.
    public static let shared: PublicSuffixList

    /// Custom / non-bundled text list (.dat format). Still parses text, so it
    /// throws.
    public static func loading(from data: Data) throws(PublicSuffixListError) -> PublicSuffixList

    public func lookup(_ host: String, scope: MatchScope = .all) -> HostInfo?
}
```

- `shared` is **non-throwing**. The blob is generated and checked in by us; a
  missing/corrupt blob can only mean the package itself is broken, so `shared`
  `preconditionFailure`s with a clear message. This is what makes the call site
  `PublicSuffixList.shared.lookup(...)` — no `try`, no `await`.
- The async `bundled()`, async `shared()`, and the `SharedListCache` actor are
  removed. `bundled()` is not replaced: its only distinction was "uncached,"
  which nobody needs.
- `loading(from:)` stays for custom lists and tests, now synchronous and
  throwing (it still parses `.dat` text via `RulesParser`).

### 2. Binary format — `PSLBinaryFormat` (new internal file)

Mirrors `IDNAMapping`'s style: explicit little-endian, hand-rolled byte reader,
magic header. Portable across the library's Linux/Windows targets.

```
"PSL1"                              4-byte magic
formatVersion                      u8
sourceDate     u8 len + UTF-8      (len 0 = absent)
sourceRevision u8 len + UTF-8
icannRuleCount                     u32
privateRuleCount                   u32
ruleCount                          u32
× ruleCount:
   flags      u8     bit0 isException, bit1 section == private
   labelCount u8
   × labelCount:
      kind u8 (0 literal, 1 wildcard); if literal: u8 len + UTF-8
```

- `package static func encode(_ parsed: ParsedList) -> Data` — used by the
  generator target.
- `static func decode(_ data: Data) -> ParsedList?` — library-internal;
  `shared` traps on `nil`.
- Decode rebuilds the flat `[Rule]` and feeds the existing `RuleIndex(rules:)`.
  `lookup`, `RuleIndex`, and `Rule` are untouched. Measured: ~2 ms.
- v1 stores labels inline. Noted future lever if the blob/allocs ever matter: a
  string-interning table (PSL's label vocabulary is far smaller than 10 K). Not
  needed now.

### 3. Codegen — in-package executable target (`psl-compile`)

A new `executableTarget` named `psl-compile` depends on `PublicSuffixListKit`
and **reuses the library's real `RulesParser`**, so the bytes are produced by
the exact code that interprets `.dat` everywhere else — drift is impossible by
construction (this is why Option B was chosen over a standalone script).

To let the tool call into the parser without exposing anything to external
consumers, the parse/format types widen `internal` → **`package`**:
`RulesParser`, `Rule`, `RuleLabel`, `Section`, `RuleIndex`, `ParsedList`, and
`PSLBinaryFormat.encode`. `package` is visible across targets in *this* package
only; Passie (a separate package) still cannot see them. The public API stays
`public`.

Flow:

```
swift run psl-compile
  → read public_suffix_list.dat   (#filePath-relative to the repo)
  → RulesParser.parse             (the real parser)
  → PSLBinaryFormat.encode
  → write public_suffix_list.bin
```

`UpdatePSL.swift` (the refresh script) shells out to `swift run psl-compile` at
the end, so a PSL refresh stays a single command:

```
swift script/UpdatePSL.swift     # downloads + normalizes .dat, then regenerates .bin
```

The executable is not part of the `.library` product, so consumers never build
it.

### 4. Resources

Ship **only `public_suffix_list.bin`** in the library bundle. `.dat` stays in
the repo as the generator input and the staleness-test input (located via
`#filePath`), excluded from the bundle via the target's `exclude:`. Drops
~142 KB of now-dead text from the app.

### 5. Error handling

- `shared`: `preconditionFailure` on missing/corrupt bundled blob (package
  defect). No throwing.
- `loading(from:)`: throws `PublicSuffixListError` on bad UTF-8 / parse
  failure, as today.
- `PublicSuffixListError` cases that only described bundled-resource failures
  (`.missingBundledResource`, `.bundleLoadFailed`) become unreachable from the
  public surface; prune or repurpose them during implementation.

### 6. Tests

- Migrate existing suites off `await`: `PublicSuffixList.shared`,
  `try loading(from:)`.
- `SharedListTests` collapses (a value type — two accesses are trivially
  equal); keep a thin metadata-sanity check, delete the actor-identity
  assertion and the `SharedListCache` it tested.
- New `PSLBinaryFormatTests`:
  - **round-trip** — a small synthetic `ParsedList` through `encode` →
    `decode`, asserting structural equality.
  - **staleness / equivalence guard** — parse the in-repo `.dat` with
    `RulesParser`, decode the shipped `.bin`, assert identical `RuleIndex`
    buckets + metadata. Makes "edited `.dat`, forgot to regenerate `.bin`" a
    hard CI failure. (Belt-and-suspenders even though Option B can't drift: it
    also catches a stale checked-in `.bin`.)
- Opt-in perf test timing first `PublicSuffixList.shared` access, to keep the
  ~2 ms first-use honest over time.

### 7. Downstream (Passie) — coordinated follow-on, out of scope for this spec

The library ships as **3.0.0** (breaking). Separately, Passie:

- bumps the pin in `Modules/Package.swift`;
- makes `DomainCanonicalizer.bundled()` synchronous (or folds the list into
  `init`);
- can then retire `PassieSession.loadDomainsIfNeeded`, make `session.domains`
  non-optional, and drop the pre-load-window fallbacks in the menubar Enter
  handler and the WebAuthn rpId gate;
- updates the PSL section of `Passie/CLAUDE.md`, which currently documents the
  async load and the nil-window design.

Land library 3.0 first, then the Passie migration as its own change.

## Out of scope / explicitly rejected

- **Generated Swift (`.swift`) data** — rejected on the benchmark: 30–180 s
  compile, 0.3–2.4 MB binary, single-literal form does not compile, for zero
  runtime benefit over `.bin`.
- **Zero-build / bytes-direct lookup** — rejected: saves ~2 ms of imperceptible
  startup for fragile, allocation-sensitive lookup code.
- **String interning in the blob** — deferred; not needed at current sizes.
