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

[2.0.0]: https://github.com/shadone/PublicSuffixListKit/compare/1.1.1...2.0.0
[1.1.1]: https://github.com/shadone/PublicSuffixListKit/releases/tag/1.1.1
