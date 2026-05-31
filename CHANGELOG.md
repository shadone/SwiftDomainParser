# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is a personal fork of
[Dashlane/SwiftDomainParser](https://github.com/Dashlane/SwiftDomainParser),
maintained for use by [Passie](https://github.com/shadone/passie). The fork is
not currently rebased onto upstream; the last synced upstream commit was
[`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16)
(Swift 6 concurrency support + PSL refresh).

## [3.0.0] - 2026-05-31

Loading the bundled list is now **synchronous**. The async factory was the only
asynchronous thing in the library and guarded a cost (a ~2 ms one-time index
build, measured) that never needed guarding; removing it drops `async`/`await`/
`throws` from every bundled-list call site.

### Changed (breaking)

- `PublicSuffixList.shared` is now a synchronous, non-throwing `static let`,
  not an `async throws` factory. It decodes a precompiled binary blob
  (`public_suffix_list.bin`) once on first access and caches it process-wide.
  Call sites become `PublicSuffixList.shared.lookup(...)` — no `try`, no `await`.
- `loading(from:)` is now synchronous `throws(PublicSuffixListError)` (it still
  parses `.dat` text for custom lists).
- `PublicSuffixListError` is reduced to its single reachable case,
  `ruleParsingError`. A corrupt bundled blob is a package defect and traps via
  `preconditionFailure` rather than throwing.

### Removed

- The `@concurrent async` `bundled()` factory.
- The `@concurrent async` `shared()` factory and the `SharedListCache` actor
  behind it (a `static let` provides the once-only caching).
- `PublicSuffixListError.missingBundledResource` and `.bundleLoadFailed`.

### Internal

- New `PSLBinaryFormat` (PSL1 little-endian blob, encode/decode) mirroring the
  existing IDNA mapping table format.
- New in-package `psl-compile` executable that reuses the real `RulesParser` to
  generate the blob, so it can never drift from the `.dat`. `script/UpdatePSL.swift`
  regenerates the blob after a refresh.
- The bundle now ships only `public_suffix_list.bin`; the `.dat` is kept in-repo
  as the generator and staleness-test input (excluded from the app bundle),
  dropping ~142 KB of dead text from shipping builds.
- A CI staleness guard asserts the checked-in blob matches the checked-in `.dat`.

## [2.0.0] - 2026-05-29

A complete, breaking rewrite around the `PublicSuffixList` API. Not
source-compatible with Dashlane upstream's 1.x API.

### Added

- `PublicSuffixList` — an immutable, `Sendable` value type with `@concurrent`
  `async` factories `bundled()`, `shared()` (process-wide cached), and
  `loading(from:)`.
- `HostInfo` result type exposing `publicSuffix`, `registrableDomain`,
  `subdomain`, and `source` (`MatchSource`: `.icann`, `.privateRule`,
  `.defaultRule`), plus canonical forms `canonicalPublicSuffix`,
  `canonicalRegistrableDomain` (UTS-46 U-label, NFC) and `asciiRegistrableDomain`
  (A-label / `xn--`).
- `MatchScope` — `.all` (ICANN + PRIVATE, the default) or `.icannOnly`, accepted
  by every `lookup` and convenience method.
- `PublicSuffixMatching` protocol as the dependency-injection seam (only
  `lookup(_:scope:)` is required), with convenience extensions including
  `haveSameRegistrableDomain(_:_:scope:)`, `registrableDomain(of:scope:)`,
  `publicSuffix(of:scope:)`, `isPublicSuffix(_:scope:)`, and a `URL` overload.
- `PublicSuffixListError` — public typed error with `.missingBundledResource`,
  `.ruleParsingError`, and `.bundleLoadFailed` cases.
- `ListMetadata` provenance on each instance: `sourceDate`, `sourceRevision`,
  `icannRuleCount`, `privateRuleCount`.
- Implicit default `*` rule for unlisted TLDs (the PSL algorithm's step-2
  fallback), so such hosts resolve with `source == .defaultRule` instead of
  returning `nil`.
- UTS-46 IDN processing (nontransitional, `UseSTD3ASCIIRules = false`): full
  mapping table (compiled from Unicode `IdnaMappingTable.txt`), NFC, and
  Punycode decode/encode. Hosts are accepted in any form (Unicode, ACE, mapped,
  or mixed); display output preserves the caller's spelling while comparison and
  the `canonical*` fields fold equivalent spellings together, so
  `食狮.公司.cn` ≡ `xn--85x722f.xn--55qx5d.cn`. Verified against Unicode's
  `IdnaTestV2.txt`. The Bidi rule and ContextJ/O joiner checks (registration
  validity) are not implemented.
- Linux and Windows support, in addition to iOS and macOS.
- DocC catalog (overview, ICANN vs PRIVATE, choosing a scope, IDN handling).

### Changed

- Renamed the SPM module/library/target `DomainParser` → `PublicSuffixListKit`.
  Import as `import PublicSuffixListKit` and depend on the `"PublicSuffixListKit"`
  product. The module uses the `…Kit` suffix to avoid colliding with the
  `PublicSuffixList` type. Sources moved to `Sources/PublicSuffixListKit/`, tests
  to `Tests/PublicSuffixListKitTests/`.
- Replaced the synchronous `DomainParser` type with the async `PublicSuffixList`
  value type.
- Renamed `ParsedHost` → `HostInfo`, `DomainParserProtocol` →
  `PublicSuffixMatching` (the required method is now `lookup(_:scope:) ->
  HostInfo?`), and `DomainParserError` → `PublicSuffixListError`.
- IP literals (IPv4 and IPv6) passed to `lookup` now return `nil`.
- Trailing dots are preserved: a FQDN like `example.com.` round-trips with its
  trailing dot in `publicSuffix` and `registrableDomain`.
- Documented the PSL issue #694 stance: a host too short to form a registrable
  domain under a wildcard rule falls back to the base rule rather than erroring
  or returning `nil`.
- Raised the Swift tools version to 6.2 and deployment targets to iOS 18 /
  macOS 15.

### Removed

- `BasicDomainParser` — full wildcard/exception correctness is now the only
  behavior, absorbed into `PublicSuffixList`.
- `FakeDomainParser` — provide a lightweight `PublicSuffixMatching` conformance
  (or a real instance) in tests and previews instead.
- The synchronous `init()` / `DomainParser(quickParsing:)` constructors;
  construction is always `async throws`.

## [1.1.1] - 2026-05-28

Last release before the rewrite. Tracks Dashlane upstream through
[`8991b16`](https://github.com/Dashlane/SwiftDomainParser/commit/8991b16):
Swift 6 concurrency support and a refreshed bundled Public Suffix List.

[3.0.0]: https://github.com/shadone/PublicSuffixListKit/compare/2.0.0...3.0.0
[2.0.0]: https://github.com/shadone/PublicSuffixListKit/compare/1.1.1...2.0.0
[1.1.1]: https://github.com/shadone/PublicSuffixListKit/releases/tag/1.1.1
