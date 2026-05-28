# Changelog

This is a personal fork of [Dashlane/SwiftDomainParser](https://github.com/Dashlane/SwiftDomainParser),
maintained for use by [Passie](https://github.com/shadone/passie). Upstream
hasn't been actively maintained, so this fork modernizes the package for
Swift 6 / iOS 18 + macOS 15, fixes a latent correctness bug, and keeps the
bundled Public Suffix List current.

Commits are listed newest-first. Upstream-derived ancestors stop at
[`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16)
("data: refresh public_suffix_list.dat from publicsuffix.org").

## 2.0.0

First release of the fork. Treats the codebase as Swift 6-first and is **not
source-compatible with Dashlane upstream's 1.x API.**

### Breaking changes

- **`ParsedHost.domain` → `ParsedHost.registrableDomain`.** The new name
  matches the PSL spec / WHATWG URL standard. The matching `init` label
  changes too.
- **`DomainParser.init(quickParsing:)` removed.** Use
  `BasicDomainParser()` for the basic-only path; use `DomainParser()` for
  full PSL parsing.
- **`DomainParserError` is now `public` with a new `.bundleLoadFailed`
  case** (Foundation errors from `Data(contentsOf:)` wrap into it).
- **All library `throws` are typed `throws(DomainParserError)`.** `try!`
  / `try?` callers are unaffected; explicit `do/catch` callers can drop
  the fallthrough clause and rely on exhaustiveness checking.
- **Deployment targets raised to iOS 18 / macOS 15** and Swift tools
  version pinned to 6.0.
- **No more Xcode project / Carthage support.** SPM only. Sources live at
  `Sources/DomainParser/`, tests at `Tests/DomainParserTests/`.

### New API

- `init() throws(DomainParserError)` on `BasicDomainParser` — the
  type is publicly constructible and exposes a `Set<String>`-backed
  lookup with no wildcard/exception parsing overhead.
- `parse(url: URL) -> ParsedHost?` default extension on
  `DomainParserProtocol`.
- `FakeDomainParser` (DEBUG builds only) for SwiftUI previews and tests.
- `ParsedHost` conforms to `Hashable` (was: only `Equatable`).

### Fixed

- Hosts with uppercase letters that should match an exception or wildcard
  rule (e.g. `WWW.CK`) no longer fall through to the basic-rules path. The
  parser now lowercases once at the entry point.
- `RulesParser` tolerates raw upstream PSL input (blank lines, `//`
  comments, inline trailing whitespace per the spec) instead of treating
  comment lines as basic rules.

### Tooling

- Swift Testing parameterized suite covers the 60-case PSL conformance
  test; XCTest retained only for `measure {}` perf tests.
- GitHub Actions: `test.yml` (PR + push, macOS) and `psl-refresh.yml`
  (weekly cron, Linux container).
- `script/UpdatePSL.swift` rewritten with `async`/`await` and
  `#filePath`-relative target path; sanity-checks the downloaded body
  for the official ICANN section marker.

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

- **No Punycode / IDNA**: hosts must be in lowercase Unicode form or
  pre-encoded ACE (`xn--...`). PSL's official Punycode test vectors are
  intentionally not covered. Most callers reading hostnames from system URL
  components already get ACE form, so this is rarely an issue in practice.

## Upstream parity

This fork is not currently rebased onto Dashlane's upstream — upstream's last
commit at the time of forking was [`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16)
(Swift 6 concurrency support + PSL refresh). If upstream resumes, integration
is possible by cherry-picking — the layout move (commit `08f3817`) is the
main rename to be aware of.
