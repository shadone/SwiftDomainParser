# Changelog

This is a personal fork of [Dashlane/SwiftDomainParser](https://github.com/Dashlane/SwiftDomainParser),
maintained for use by [Passie](https://github.com/shadone/passie). Upstream
hasn't been actively maintained, so this fork modernizes the package for
Swift 6 / iOS 18 + macOS 15, fixes a latent correctness bug, and keeps the
bundled Public Suffix List current.

Commits are listed newest-first. Upstream-derived ancestors stop at
[`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16)
("data: refresh public_suffix_list.dat from publicsuffix.org").

## 2.0.0 — PublicSuffixList rewrite (breaking)

First release of the fork's PublicSuffixList API. Complete API overhaul; not
source-compatible with Dashlane upstream's 1.x API.

### Breaking changes

- **SPM module/library/target renamed `DomainParser` → `PublicSuffixListKit`.**
  Update your import to `import PublicSuffixListKit` and the dependency product
  name to `"PublicSuffixListKit"`. The module is named `PublicSuffixListKit`
  (not `PublicSuffixList`) to avoid colliding with the primary `PublicSuffixList`
  type. Sources moved to `Sources/PublicSuffixListKit/`, tests to
  `Tests/PublicSuffixListKitTests/`.
- **`DomainParser` renamed to `PublicSuffixList`.** The old synchronous `init()`
  is gone; use the async factory methods `bundled()`, `shared()`, or
  `loading(from:)`.
- **`ParsedHost` renamed to `HostInfo`.** Fields `publicSuffix` and
  `registrableDomain` are retained; `subdomain` is new; `source` (`MatchSource`)
  is new.
- **`DomainParserProtocol` renamed to `PublicSuffixMatching`.** The required
  method is now `lookup(_:scope:) -> HostInfo?`; the old `parse(host:)` and
  `parse(url:)` are replaced by protocol extensions (`lookup(_:URL,scope:)`,
  `registrableDomain(of:scope:)`, `publicSuffix(of:scope:)`,
  `isPublicSuffix(_:scope:)`, `haveSameRegistrableDomain(_:_:scope:)`).
- **`DomainParserError` renamed to `PublicSuffixListError`.**
- **`BasicDomainParser` removed.** Its logic is fully absorbed into
  `PublicSuffixList`; full wildcard/exception correctness is the only behavior.
- **`FakeDomainParser` removed.** Test code should provide a lightweight
  `PublicSuffixMatching` conformance or use a real `PublicSuffixList` instance.

### New API

- `PublicSuffixList.bundled() async throws -> PublicSuffixList` — load the
  bundled PSL, caller owns the lifetime.
- `PublicSuffixList.shared() async throws -> PublicSuffixList` — process-wide
  cached instance; safe to call from any isolation domain.
- `PublicSuffixList.loading(from: Data) async throws -> PublicSuffixList` — load
  from caller-supplied PSL data.
- `HostInfo.source: MatchSource` — indicates whether the match came from an
  ICANN rule (`.icann`), a PRIVATE rule (`.privateRule`), or the implicit
  default rule for unlisted TLDs (`.defaultRule`).
- `MatchScope` — `.all` (ICANN + PRIVATE, the default) or `.icannOnly`.
  Every `lookup` / convenience method accepts an optional `scope` parameter.
- `PublicSuffixMatching.haveSameRegistrableDomain(_:_:scope:)` — returns `true`
  only when both hosts resolve to the same non-nil registrable domain; the
  primary credential-matching primitive.
- `PublicSuffixList.metadata: ListMetadata` — provenance of the loaded list:
  `sourceDate`, `sourceRevision`, `icannRuleCount`, `privateRuleCount`.

### New behavior

- **Async loading factories** (`bundled()`, `shared()`, `loading(from:)`).
  There is no synchronous `init`; construction is always `async throws`.
- **Implicit default rule for unlisted TLDs.** A host whose TLD has no PSL
  entry now resolves against an implicit `*` rule (the PSL spec's "Algorithm
  step 2" fallback), returning a `HostInfo` with `source == .defaultRule`
  instead of `nil`. The previous behavior was to return `nil` in this case.
- **Trailing dot preserved in output.** A FQDN like `example.com.` round-trips
  with its trailing dot intact in `publicSuffix` and `registrableDomain`.
- **IP literals rejected.** IPv4 and IPv6 literals passed to `lookup` return
  `nil` immediately.
- **PSL issue #694 stance documented.** A host that is too short to form a
  registrable domain under a wildcard rule (e.g. the host equals the wildcard's
  base label) falls back to the base rule rather than returning nil or erroring.
  This behavior is documented in source as a deliberate choice pending PSL spec
  clarification.
- **Linux and Windows supported.** The package now builds and tests on Linux
  and Windows in addition to iOS/macOS.
- **Swift tools version bumped to 6.2.**

## Fork divergence

### Tooling and layout

- [`08f3817`](../../commit/08f3817) — moved sources to `Sources/DomainParser/`
  and tests to `Tests/DomainParserTests/` (idiomatic SwiftPM). Removed the
  legacy Carthage-era `DomainParser.xcodeproj`, both `Info.plist` files, the
  module umbrella header, and the `Bundle.current` SPM/Carthage shim. Bumped
  platforms to `.iOS(.v18)` / `.macOS(.v15)`.
- [`cf14a4c`](../../commit/cf14a4c) — rewrote `script/UpdatePSL.swift` with
  `async`/`await` and `#filePath`-relative path resolution. Runs from any cwd:
  `swift script/UpdatePSL.swift`.
- [`3e636c5`](../../commit/3e636c5) — ported behavioural tests to Swift
  Testing. `testPSL` became a `@Test(arguments:)` parameterized suite over 60
  PSL cases; XCTest retained only for `measure {}` perf tests.

### Bug fixes

- [`39763f7`](../../commit/39763f7) — **fix**: lowercase the host once at the
  top of `DomainParser.parse(host:)`. The exception/wildcard branch previously
  compared mixed-case input against lowercase PSL rules and silently fell
  through. Regression test included.

### API

- [`22bd644`](../../commit/22bd644) — made `DomainParserError` public; added
  `.missingPublicSuffixListResource` and replaced the `Bundle.module.url(...)`
  force-unwrap with a throw.
- [`49e35c3`](../../commit/49e35c3) — added `parse(url: URL) -> ParsedHost?`
  convenience on `DomainParserProtocol`.
- [`db004fe`](../../commit/db004fe) — gated `FakeDomainParser` behind
  `#if DEBUG` so it no longer ships in release binaries.
- [`0a8ebbe`](../../commit/0a8ebbe) — deprecated
  `DomainParser(quickParsing:)`. Use `BasicDomainParser` directly for the
  basic-only path; `DomainParser()` for full PSL parsing.
- [`3994a96`](../../commit/3994a96) — prefixed the test-only internal seams
  (`parsedRules` → `_parsedRules`, `init(rulesData:...)` →
  `init(_rulesData:...)`) to signal "do not depend on me."

### Performance

- [`430a72a`](../../commit/430a72a) — dropped a redundant
  `host.lowercased()` from `BasicDomainParser.parse` since
  `DomainParser.parse` now lowercases at the top. `BasicDomainParser` is now
  documented as requiring lowercase input.

### Code health

- [`63759ed`](../../commit/63759ed) — dropped `Rule: Comparable/Equatable`
  whose `==` violated value-equality semantics (two distinct rules with the
  same `rankingScore` compared equal). Sort sites pass an explicit comparator.
- [`d721480`](../../commit/d721480) — removed the `typealias C = Constant`
  single-letter alias, the `#if swift(>=4.2)` dead branch in `Rule.isMatching`,
  the redundant manual `ParsedHost: Equatable`, and two unused `Constant`
  fields. Added `ParsedHost: Hashable`.
- [`af490a8`](../../commit/af490a8) — converted `RulesParser` from a class
  with mutable `var` state used once to a caseless enum namespace returning
  `ParsedRules` by value.
- [`1376fb5`](../../commit/1376fb5) — renamed `Constant` → `PSLSyntax`.
- [`9d328a4`](../../commit/9d328a4) — explicit `Sendable` conformance on
  `Rule`, `RuleLabel`, and `ParsedRules`.

## Known limitations

- **No full UTS-46 IDNA**: Punycode decode/encode-aware PSL lookup is
  implemented (added in 2.0), but full IDNA processing - NFC
  normalization, Bidi rule, joiner-context checks - is not. Mostly
  irrelevant in practice because hostnames coming from URL parsing
  are already validated.

## Upstream parity

This fork is not currently rebased onto Dashlane's upstream — upstream's last
commit at the time of forking was [`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16)
(Swift 6 concurrency support + PSL refresh). If upstream resumes, integration
is possible by cherry-picking — the layout move (commit `08f3817`) is the
main rename to be aware of.
