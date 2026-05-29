# DomainParser → PublicSuffixList API redesign

Date: 2026-05-29
Status: Design approved, pending spec review

A clean-slate redesign of this library's public API, ignoring backwards
compatibility. Goal: the best possible Swift API for matching hostnames
against the Public Suffix List, optimized for a clean general-purpose core
with conveniences for password-manager autofill (the Passie consumer).

## Motivation

The current API has four problems:

1. **Misnamed.** `DomainParser` does not parse — it matches a host against the
   PSL. `ParsedHost` is a host decomposition, not a "parsed host."
2. **A correctness footgun in the public surface.** `BasicDomainParser` is
   exposed publicly as a "skip wildcard/exception rules, slightly faster"
   variant. In this domain "faster but occasionally wrong about which site
   this is" is a security hazard, not a feature.
3. **Two semantic gaps:** it ignores the ICANN-vs-PRIVATE division of the PSL
   (so `alice.github.io` and `bob.github.io` collapse to the same registrable
   domain — wrong for credential isolation), and it returns `nil` for unlisted
   TLDs instead of the spec's implicit `*` rule, with no way for the caller to
   tell a real match from a fallback.
4. **A silently expensive initializer.** `init()` loads and parses ~10K rules
   (~20ms + disk I/O) behind a cheap-looking initializer.

## Resolved decisions

| Decision | Choice |
|---|---|
| Audience | Clean general-purpose core + app conveniences as extensions |
| ICANN vs PRIVATE | First-class; **PRIVATE included by default** (safe for credential matching), opt down to ICANN-only |
| Result richness | Rich result value + thin convenience accessors |
| Unlisted TLD | Typed result: caller distinguishes ICANN / PRIVATE / default-rule and decides whether to trust the fallback |
| `BasicDomainParser` | **Removed** from public API; basic-rule lookup absorbed as an internal detail |
| Protocol | **Kept** (`PublicSuffixMatching`), slim — the DI/test seam; conveniences are protocol extensions |
| Built-in mock | **None.** Consumers add their own conforming type if they need one |
| Loading | Explicit `@concurrent async throws` factory; **no** `prepare()`/`cleanup()`; `parse()` stays pure/sync |
| Memory reclaim | Drop the reference (value type → ARC frees it); no explicit hook |

## Public API

### Result type

```swift
public struct HostInfo: Sendable, Equatable, Hashable {
    /// Public suffix, e.g. "co.uk", "github.io". Always present.
    public let publicSuffix: String
    /// Registrable domain (eTLD+1), e.g. "alice.github.io".
    /// nil when the host IS a public suffix (e.g. "co.uk" itself).
    public let registrableDomain: String?
    /// Everything left of the registrable domain, e.g. "app" in
    /// "app.alice.github.io". nil when there is none.
    public let subdomain: String?
    /// Which part of the list decided this match.
    public let source: MatchSource
}

public enum MatchSource: Sendable, Equatable {
    case icann          // matched an ICANN-section rule
    case privateRule    // matched a PRIVATE-section rule (per-tenant isolation)
    case defaultRule    // no rule matched; implicit "*" applied — a guess
}
```

`source` folds the typed-result decision into one field rather than a wrapping
enum, so the rich-result and typed-result goals don't fight. A caller wanting
"known suffixes only" filters `source != .defaultRule`; a security boundary
trusts `.icann` / `.privateRule`.

### Protocol (the DI seam) and scope

```swift
public protocol PublicSuffixMatching: Sendable {
    func parse(_ host: String, scope: MatchScope) -> HostInfo?
}

public enum MatchScope: Sendable {
    case all        // ICANN + PRIVATE  (default — safe for credential matching)
    case icannOnly  // ignore PRIVATE rules
}
```

Only `parse` is a protocol requirement; everything else is a protocol
extension so any conformer (real or a consumer's test double) gets it free.

### Concrete type and loading

```swift
public struct PublicSuffixList: PublicSuffixMatching, Sendable {
    /// Load the bundled Public Suffix List. Expensive (disk I/O + ~20ms
    /// parse of ~10K rules); runs off the caller's actor via @concurrent.
    @concurrent
    public static func bundled() async throws(PublicSuffixListError) -> PublicSuffixList

    /// Load from caller-supplied list bytes (custom lists / tests).
    @concurrent
    public static func loading(from data: Data) async throws(PublicSuffixListError) -> PublicSuffixList

    /// Pure, synchronous, instant. Never loads, never blocks.
    public func parse(_ host: String, scope: MatchScope = .all) -> HostInfo?
}
```

There is deliberately **no loading `init()`**: construction is explicit and
awaited so the cost is visible at the call site (`try await .bundled()`).
`parse()` is a pure value query — no lazy load, no lock, no first-call hitch.
"Cleanup" = release the reference; ARC frees the few-hundred-KB rule sets.

`@concurrent` matters under Swift 6.2's nonisolated-nonsending default: a plain
`async` called from `@MainActor` would still run on the main actor. `@concurrent`
forces the parse onto the cooperative pool, so even a main-actor caller gets no
hitch.

### Conveniences (protocol extensions — the "app" layer)

```swift
extension PublicSuffixMatching {
    func parse(_ url: URL, scope: MatchScope = .all) -> HostInfo?
    func registrableDomain(of host: String, scope: MatchScope = .all) -> String?
    func publicSuffix(of host: String, scope: MatchScope = .all) -> String?
    func isPublicSuffix(_ host: String, scope: MatchScope = .all) -> Bool

    /// Passie's key primitive: do two hosts share a registrable domain?
    /// false if either is a bare suffix or unparseable. PRIVATE rules
    /// included by default, so alice.github.io and bob.github.io are NOT
    /// the same site.
    func sameSite(_ a: String, _ b: String, scope: MatchScope = .all) -> Bool
}
```

## Behavior details

- **`parse` returns `nil`** only for non-hostnames: empty input and IP literals
  (a new quality touch — `192.168.0.1` must not pretend to have a registrable
  domain). Every real hostname yields a `HostInfo`, because `.defaultRule`
  guarantees a suffix.
- **Scope.** With `.all`, PRIVATE rules are consulted first (more specific),
  then ICANN, then the implicit `*`. With `.icannOnly`, PRIVATE rules are
  ignored: `alice.github.io` → suffix `io` (icann), registrable `github.io`.
- **IDN.** Preserve the caller's ACE/Unicode form in the output; match
  internally via Punycode-decode (current behavior, passes the official PSL
  test suite). No new surface.
- **Errors.** Typed throws `throws(PublicSuffixListError)` on the factories
  only; queries never throw.

## Internal structure

- Tag each rule with its section (ICANN / PRIVATE) at parse time; keep separate
  index sets per section.
- A query walks labels right-to-left: PRIVATE first when `scope == .all`, then
  ICANN, then the implicit `*` fallback.
- Keep the current allocation-light `Substring`-view lookup for the basic-rule
  set; it just carries the section bit now.
- Lifecycle/singleton policy is a **consumer** concern. Passie can hold a small
  `actor DomainService { private var psl: PublicSuffixList? }` that loads once
  and shares — the library stays a pure immutable matcher.

## Out of scope (deferred / YAGNI)

- **Built-in mock / fake.** Consumers add their own `PublicSuffixMatching`
  conformer if needed.
- **Faster loading via build-time serialization.** If 20ms proves to matter,
  the lever is having `script/UpdatePSL.swift` emit a pre-tokenized binary
  resource that decodes in a few ms instead of parsing text at runtime. Has its
  own build-tooling cost; do it only if measured.
- **IDN output normalization options** (force ACE / force Unicode). Preserve
  input form for now.

## Public surface, before → after

| Today | Proposed |
|---|---|
| `DomainParser` (loading `init()`) | `PublicSuffixList` (`@concurrent async` factories) |
| `BasicDomainParser` | removed (logic absorbed internally) |
| `DomainParserProtocol` | `PublicSuffixMatching` (slim; conveniences are extensions) |
| `FakeDomainParser` | removed (consumer-owned) |
| `ParsedHost { publicSuffix, registrableDomain? }` | `HostInfo { publicSuffix, registrableDomain?, subdomain?, source }` |
| `DomainParserError` | `PublicSuffixListError` |
| — | `MatchScope`, `MatchSource`, `sameSite(_:_:)`, IP-literal rejection |
