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
| Loading | Explicit `@concurrent async throws` factory; **no** `prepare()`/`cleanup()`; `lookup()` stays pure/sync |
| Method name | `lookup(_:)` (the type is `PublicSuffixList`, not a parser) |
| Convenience accessor | `shared()` — actor-cached, load-once, for callers that don't want to own lifecycle |
| Platforms | iOS / macOS / **Linux / Windows** (portable Foundation only) |
| Docs | DocC catalog (landing page + ICANN-vs-PRIVATE, scope, IDN articles) |
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

    /// The host is itself a bare public suffix (e.g. "co.uk") — nothing to
    /// register under it. Equivalent to `registrableDomain == nil`.
    public var isPublicSuffix: Bool { registrableDomain == nil }

    /// The host IS exactly the registrable domain (eTLD+1) with no subdomain,
    /// e.g. "github.com". Useful for autofill "is this the apex domain" checks.
    public var isRegistrableDomain: Bool { subdomain == nil && registrableDomain != nil }
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
    func lookup(_ host: String, scope: MatchScope) -> HostInfo?
}

public enum MatchScope: Sendable {
    case all        // ICANN + PRIVATE  (default — safe for credential matching)
    case icannOnly  // ignore PRIVATE rules
}
```

Only `lookup` is a protocol requirement; everything else is a protocol
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

    /// Convenience for callers that don't want to own the lifecycle: loads the
    /// bundled list once and returns the cached value thereafter. Backed by an
    /// internal actor. Cost is still explicit (you await); trade-off is
    /// process-lifetime retention (no memory reclaim). Use `bundled()` if you
    /// want to control the lifetime yourself.
    public static func shared() async throws(PublicSuffixListError) -> PublicSuffixList

    /// Pure, synchronous, instant. Never loads, never blocks.
    public func lookup(_ host: String, scope: MatchScope = .all) -> HostInfo?

    /// Provenance of the loaded list, for diagnostics ("which list version
    /// produced this match?").
    public var metadata: ListMetadata { get }
}

public struct ListMetadata: Sendable, Equatable {
    /// Date the bundled list was fetched, if known (ISO-8601), e.g. "2026-05-28".
    public let sourceDate: String?
    /// Upstream commit/revision the list was fetched at, if known.
    public let sourceRevision: String?
    /// Rule counts, useful in logs.
    public let icannRuleCount: Int
    public let privateRuleCount: Int
}
```

`metadata` is populated from a header comment that `script/UpdatePSL.swift`
writes into the bundled `.dat` at update time (the upstream list has no
standard version line); the loader parses it. `loading(from:)` fills what it
can and leaves the rest `nil`.

There is deliberately **no loading `init()`**: construction is explicit and
awaited so the cost is visible at the call site (`try await .bundled()`).
`lookup()` is a pure value query — no lazy load, no lock, no first-call hitch.
"Cleanup" = release the reference; ARC frees the few-hundred-KB rule sets.

`@concurrent` matters under Swift 6.2's nonisolated-nonsending default: a plain
`async` called from `@MainActor` would still run on the main actor. `@concurrent`
forces the parse onto the cooperative pool, so even a main-actor caller gets no
hitch.

### Conveniences (protocol extensions — the "app" layer)

```swift
extension PublicSuffixMatching {
    func lookup(_ url: URL, scope: MatchScope = .all) -> HostInfo?
    func registrableDomain(of host: String, scope: MatchScope = .all) -> String?
    func publicSuffix(of host: String, scope: MatchScope = .all) -> String?
    func isPublicSuffix(_ host: String, scope: MatchScope = .all) -> Bool

    /// Passie's key primitive: do two hosts resolve to the same registrable
    /// domain? false if either is a bare suffix or unparseable. PRIVATE rules
    /// included by default, so alice.github.io and bob.github.io are NOT equal.
    ///
    /// Named to avoid collision with the web platform's "same-site" (RFC
    /// 6265bis), which is schemeful and cookie-specific. This is purely
    /// scheme-agnostic registrable-domain equality.
    func haveSameRegistrableDomain(_ a: String, _ b: String, scope: MatchScope = .all) -> Bool
}
```

## Behavior details

### Input normalization (defined explicitly)

Applied before matching, in this order:

- **Lowercase** (Unicode-aware), as today.
- **Trailing dot (FQDN form):** a single trailing `.` is **ignored for matching
  but preserved in the output** — `example.com.` → registrableDomain
  `example.com.`. This follows the PSL algorithm literally: *"A trailing dot
  shall be added if the domain included one."* The Passie primitive
  `haveSameRegistrableDomain` canonicalizes the trailing dot away before
  comparing, so `example.com` and `example.com.` are still the same site.
- **Empty / leading-dot labels → `nil`:** a host that is only dots, has a
  *leading* dot, or contains an interior **empty label** (`foo..com`, `.com`) is
  rejected, per *"Empty labels are not permitted."* (We do not let `split`
  silently swallow them.) Note this is distinct from the single trailing dot
  above, which is allowed.
- **IP literals → `nil`:** reject both IPv4 dotted-quads (`192.168.0.1`) and
  IPv6, including the bracketed form a URL host yields (`[::1]`, `[fe80::1]`).
  An IP is not a domain and must not appear to have a registrable domain.

`lookup` returns `nil` for these non-hostnames (and for empty input). Every
*real* hostname yields a `HostInfo`, because `.defaultRule` guarantees a suffix.

### Matching

- **Prevailing-rule resolution (the exact PSL algorithm).** A rule *matches*
  when the host has at least as many labels as the rule and, comparing from the
  right, each rule label is identical to the host label or is `*`. Among all
  matching rules pick, in order: (1) an **exception** rule if any; else (2) the
  matching rule with the **most labels**; else (3) the implicit `*`. An
  exception rule's public suffix is the rule minus its leftmost label. This must
  consider basic and wildcard rules **together** — not "check wildcards, then
  basic and stop" — so a longer basic rule correctly outranks a shorter matching
  wildcard. (The current code's bucket-then-fallback shortcut can mis-rank that
  case; the rewrite resolves across all matching rules.)
- **Scope.** `.all` considers ICANN + PRIVATE rules; `.icannOnly` ignores
  PRIVATE rules. Resolution within the chosen set is the algorithm above, so
  `alice.github.io` → `github.io` (private) under `.all`, but `io` (icann),
  registrable `github.io`, under `.icannOnly`.
- **Wildcards.** Per the format, a wildcard appears only as the **leftmost label
  of a rule** and wildcards an entire label — only a bare `*` is a wildcard
  label (`*bar` is literal text). The rule may still be deep, e.g.
  `*.compute.amazonaws.com` (the `*` is leftmost; the rule is four labels).
- **IDN.** Preserve the caller's ACE/Unicode form in the output; match
  internally via Punycode-decode. See the IDNA limitation below.
- **Errors.** Typed throws `throws(PublicSuffixListError)` on the factories
  only; queries never throw.

### Edge case: too-short host under a wildcard (PSL issue #694)

For a host with *fewer* labels than a wildcard rule that would otherwise cover
it — e.g. `yokohama.jp` against rules `jp` + `*.yokohama.jp` — the wildcard does
**not** match (the host lacks the required label count), so resolution falls
back to the next matching rule, `jp`. Result: publicSuffix `jp`,
registrableDomain `yokohama.jp`, source `.icann`.

This is the literal-algorithm reading and matches Servo's behavior; libpsl
instead treats the incomplete match specially and returns `yokohama.jp` as the
suffix. [PSL issue #694](https://github.com/publicsuffix/list/issues/694) is
unresolved upstream — we deliberately take the literal reading and **pin it with
a test** so the choice is explicit, not accidental. (The current code already
behaves this way.)

### Known limitation: IDNA normalization

Normalization is `String.lowercased()` + Punycode-decode of `xn--` labels — not
full UTS-46 / IDNA2008 mapping (case folding, NFC, disallowed-codepoint
handling), which needs ICU-grade tables. This matches the current library and
passes the official PSL test suite, but a deliberately exotic Unicode host could
in principle normalize differently than a fully IDNA-compliant implementation.
Documented as an accepted trade-off, not an accidental gap.

## Internal structure

- Tag each rule with its section (ICANN / PRIVATE) at parse time; keep separate
  index sets per section.
- A query walks labels right-to-left: PRIVATE first when `scope == .all`, then
  ICANN, then the implicit `*` fallback.
- Keep the current allocation-light `Substring`-view lookup for the basic-rule
  set; it just carries the section bit now.
- Lifecycle/singleton policy is a **consumer** concern. Passie can hold a small
  `actor DomainService { private var psl: PublicSuffixList? }` that loads once
  and shares — or just call `PublicSuffixList.shared()`. The library stays a
  pure immutable matcher either way.
- `shared()` is backed by a tiny internal actor caching `PublicSuffixList?`; the
  first caller triggers `bundled()`, the rest await the cached value.

## Portability (iOS / macOS / Linux / Windows)

The library targets all Swift platforms, not just Apple ones.

- Depend only on portable Foundation (`Data`, `URL`, `Bundle.module`,
  `String`/`Unicode` APIs) — these exist in swift-corelibs-foundation on
  Linux/Windows. Avoid Apple-only frameworks entirely (there are none today).
- `Package.swift` keeps the Apple `platforms:` floors (iOS 18 / macOS 15) but
  imposes no restriction on Linux/Windows, which SwiftPM treats as available by
  default.
- `Bundle.module` resource access is the one portability-sensitive spot;
  verify the `.dat` loads under swift-corelibs-foundation.
- **CI matrix:** build + run the full test suite (incl. the official
  conformance suite) on macOS and Linux at minimum; add Windows if the runner
  is cheap. This is what actually keeps portability honest.

## Documentation (DocC)

Ship a DocC catalog, not just doc comments — the security-relevant nuances
deserve a narrative home:

- Landing page: what the PSL is, the registrable-domain concept, the
  build-once-share model.
- Article: **ICANN vs PRIVATE** — why `alice.github.io` ≠ `bob.github.io` and
  when to care (credential isolation).
- Article: **Choosing a scope** — `.all` vs `.icannOnly`, with the cookie-vs-
  credential framing.
- Article: **IDN handling & limitations** — ACE/Unicode round-tripping and the
  UTS-46 caveat.

## Testing

- **Official conformance suite is the backbone.** Keep running the upstream
  `tests.txt` from publicsuffix.org against `lookup` (scope `.all`) — this is the
  primary correctness guarantee and must stay green on every list update.
- **New-behavior cases** (Swift Testing, parameterized where natural):
  - Scope: same host under `.all` vs `.icannOnly` (e.g. `alice.github.io`).
  - `source`: assert `.icann` / `.privateRule` / `.defaultRule` on representative
    hosts (`example.com`, `alice.github.io`, `app.mycorp.internal`).
  - Normalization: empty/leading-dot labels and IPv4 + IPv6 (incl. bracketed)
    → `nil`; **trailing dot preserved** in output (`example.com.` →
    registrableDomain `example.com.`), and `haveSameRegistrableDomain` treats
    `example.com` ≡ `example.com.`.
  - **Issue #694:** `yokohama.jp` / `kobe.jp` → suffix `jp`, registrable
    `yokohama.jp` (literal-algorithm reading), and the `*.mm` family
    (`mm`→nil suffix `mm`, `c.mm`→nil, `b.c.mm`→`b.c.mm`).
  - **Priority resolution:** a host matching both a shorter wildcard and a
    longer basic rule resolves to the longer rule.
  - `haveSameRegistrableDomain`: same-domain true; cross-tenant private false;
    bare-suffix / unparseable false.
  - `metadata`: counts non-zero, `sourceDate` parsed from the bundled header.
  - IDN: ACE-in and Unicode-in for the same host agree.
- **Invariant test:** the bundled `.dat` stays sorted/normalized as the loader
  expects (carried over from current tests).

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
| — | `MatchScope`, `MatchSource`, `ListMetadata`, `haveSameRegistrableDomain(_:_:)`, IP-literal rejection |
