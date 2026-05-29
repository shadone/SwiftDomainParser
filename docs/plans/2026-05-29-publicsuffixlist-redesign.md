# PublicSuffixList Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `DomainParser` API with a clean, spec-compliant `PublicSuffixList` library: rich `HostInfo` results, first-class ICANN/PRIVATE scope (private by default), explicit `@concurrent async` loading, full PSL prevailing-rule resolution, and cross-platform support.

**Architecture:** One immutable `Sendable` value type `PublicSuffixList` holds rules indexed by rightmost label, each tagged with its section. A single `lookup(_:scope:)` resolves the prevailing rule (exception → most-labels → implicit `*`) and returns a `HostInfo`. A slim `PublicSuffixMatching` protocol carries only `lookup`; all conveniences are protocol extensions. Loading is explicit async factories; the bundled list and its provenance are produced by `script/UpdatePSL.swift`.

**Tech Stack:** Swift 6.2 (Approachable Concurrency: `@concurrent`, typed throws), Swift Testing, SwiftPM resources (`Bundle.module`), DocC, GitHub Actions (macOS + Linux).

**Spec:** `docs/specs/2026-05-29-psl-api-redesign-design.md`

**Sequencing note:** This is a breaking rewrite. Land the entire library (Phases 1–8) on a branch, keep the old API building until the new one is green, then delete the old files in Phase 7. The Passie consumer migration (Phase 9) is cross-repo and must come last, after the library is published — it begins with a call-site scan that has not yet been done.

---

## File Structure

New/changed files under `Sources/DomainParser/` (the SPM target name `DomainParser` and module name stay; only the public API changes):

| File | Responsibility |
|---|---|
| `PublicSuffixList.swift` | The concrete type: loading factories, `lookup`, `metadata`, internal index. |
| `PublicSuffixMatching.swift` | The protocol (just `lookup`) + all convenience extensions. |
| `HostInfo.swift` | `HostInfo` result + `MatchSource`. |
| `MatchScope.swift` | `MatchScope` enum. |
| `PublicSuffixListError.swift` | Typed error. |
| `ListMetadata.swift` | Provenance value type. |
| `SharedList.swift` | Internal actor backing `PublicSuffixList.shared()`. |
| `Internal/NormalizedHost.swift` | Host normalization (lowercase, punycode, trailing-dot, IP/empty rejection) + label splitting. |
| `Internal/Rule.swift` | `Rule`, `RuleLabel`, `Section`; matching predicate. |
| `Internal/RuleIndex.swift` | `RuleIndex` (rules by rightmost label) + prevailing-rule resolution. |
| `Internal/RulesParser.swift` | Parse the bundled `.dat` (sectioned) + metadata header into a `RuleIndex` + `ListMetadata`. |
| `Internal/Punycode.swift` | RFC 3492 decoder — **moved unchanged** from `Punycode.swift`. |
| `Internal/IPLiteral.swift` | IPv4/IPv6 literal detection. |

Deleted at end of Phase 7: `DomainParser.swift`, `DomainParserProtocol.swift`, `BasicDomainParser.swift`, `HostLabels.swift`, `ParsedHost.swift`, `PSLSyntax.swift`, `Model/Rule.swift`, `Model/RuleLabel.swift`, old `RulesParser.swift`, old `Punycode.swift`.

Tooling/docs: `script/UpdatePSL.swift` (sections + metadata), `Sources/DomainParser/DomainParser.docc/` (catalog), `.github/workflows/test.yml` (matrix), `README.md`, `CHANGELOG.md`.

---

## Phase 1 — Public value types

### Task 1: `HostInfo` and `MatchSource`

**Files:**
- Create: `Sources/DomainParser/HostInfo.swift`
- Test: `Tests/DomainParserTests/HostInfoTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/HostInfoTests.swift
import Testing
@testable import DomainParser

@Suite("HostInfo")
struct HostInfoTests {
    @Test func barePublicSuffixFlags() {
        let info = HostInfo(publicSuffix: "co.uk", registrableDomain: nil,
                            subdomain: nil, source: .icann)
        #expect(info.isPublicSuffix)
        #expect(!info.isRegistrableDomain)
    }

    @Test func apexDomainFlags() {
        let info = HostInfo(publicSuffix: "com", registrableDomain: "github.com",
                            subdomain: nil, source: .icann)
        #expect(!info.isPublicSuffix)
        #expect(info.isRegistrableDomain)
    }

    @Test func subdomainIsNotRegistrableDomain() {
        let info = HostInfo(publicSuffix: "com", registrableDomain: "github.com",
                            subdomain: "api", source: .icann)
        #expect(!info.isRegistrableDomain)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HostInfo`
Expected: FAIL — `cannot find 'HostInfo' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/DomainParser/HostInfo.swift

/// The decomposition of a host against the Public Suffix List.
public struct HostInfo: Sendable, Equatable, Hashable {
    /// Public suffix, e.g. "co.uk", "github.io". Always present.
    public let publicSuffix: String
    /// Registrable domain (eTLD+1), e.g. "alice.github.io".
    /// nil when the host IS a public suffix (e.g. "co.uk").
    public let registrableDomain: String?
    /// Everything left of the registrable domain, e.g. "app" in
    /// "app.alice.github.io". nil when there is none.
    public let subdomain: String?
    /// Which part of the list decided this match.
    public let source: MatchSource

    public init(publicSuffix: String, registrableDomain: String?,
                subdomain: String?, source: MatchSource) {
        self.publicSuffix = publicSuffix
        self.registrableDomain = registrableDomain
        self.subdomain = subdomain
        self.source = source
    }

    /// The host is itself a bare public suffix (e.g. "co.uk").
    public var isPublicSuffix: Bool { registrableDomain == nil }

    /// The host IS exactly the registrable domain (eTLD+1) with no subdomain.
    public var isRegistrableDomain: Bool {
        subdomain == nil && registrableDomain != nil
    }
}

/// Which class of PSL rule produced a match.
public enum MatchSource: Sendable, Equatable {
    /// Matched an ICANN-section rule.
    case icann
    /// Matched a PRIVATE-section rule (per-tenant isolation).
    case privateRule
    /// No rule matched; the implicit "*" rule was applied — a guess.
    case defaultRule
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HostInfo`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/HostInfo.swift Tests/DomainParserTests/HostInfoTests.swift
git commit -m "feat: add HostInfo result type and MatchSource"
```

### Task 2: `MatchScope`, `PublicSuffixListError`, `ListMetadata`

**Files:**
- Create: `Sources/DomainParser/MatchScope.swift`
- Create: `Sources/DomainParser/PublicSuffixListError.swift`
- Create: `Sources/DomainParser/ListMetadata.swift`

These are plain declarations with no behavior to test; they are exercised by later tasks.

- [ ] **Step 1: Write `MatchScope`**

```swift
// Sources/DomainParser/MatchScope.swift

/// Which sections of the Public Suffix List a query consults.
public enum MatchScope: Sendable {
    /// ICANN + PRIVATE rules. The default — correct for credential matching,
    /// where alice.github.io and bob.github.io must be different sites.
    case all
    /// ICANN rules only; PRIVATE rules are ignored.
    case icannOnly
}
```

- [ ] **Step 2: Write `PublicSuffixListError`**

```swift
// Sources/DomainParser/PublicSuffixListError.swift
import Foundation

/// Errors thrown while loading a Public Suffix List. Queries never throw.
public enum PublicSuffixListError: Error {
    /// The list bytes were not valid UTF-8, or a rule had an unsupported shape.
    case ruleParsingError(message: String)
    /// The bundled `public_suffix_list.dat` resource was not found in
    /// `Bundle.module`. In a shipping build this is a packaging bug.
    case missingBundledResource
    /// Reading the bundled resource off disk failed (wrapped Foundation error).
    case bundleLoadFailed(underlying: any Error)
}
```

- [ ] **Step 3: Write `ListMetadata`**

```swift
// Sources/DomainParser/ListMetadata.swift

/// Provenance of a loaded Public Suffix List, for diagnostics.
public struct ListMetadata: Sendable, Equatable {
    /// Date the bundled list was fetched (ISO-8601, e.g. "2026-05-28"), if known.
    public let sourceDate: String?
    /// Upstream commit/revision the list was fetched at, if known.
    public let sourceRevision: String?
    /// Number of ICANN-section rules loaded.
    public let icannRuleCount: Int
    /// Number of PRIVATE-section rules loaded.
    public let privateRuleCount: Int

    public init(sourceDate: String?, sourceRevision: String?,
                icannRuleCount: Int, privateRuleCount: Int) {
        self.sourceDate = sourceDate
        self.sourceRevision = sourceRevision
        self.icannRuleCount = icannRuleCount
        self.privateRuleCount = privateRuleCount
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build`
Expected: Build complete (old API still present; these are additive).

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/MatchScope.swift Sources/DomainParser/PublicSuffixListError.swift Sources/DomainParser/ListMetadata.swift
git commit -m "feat: add MatchScope, PublicSuffixListError, ListMetadata"
```

---

## Phase 2 — Internal model

### Task 3: Move `Punycode` into `Internal/`, add `IPLiteral`

**Files:**
- Create: `Sources/DomainParser/Internal/Punycode.swift` (moved content, unchanged)
- Create: `Sources/DomainParser/Internal/IPLiteral.swift`
- Test: `Tests/DomainParserTests/IPLiteralTests.swift`

- [ ] **Step 1: Move Punycode unchanged**

```bash
mkdir -p Sources/DomainParser/Internal
git mv Sources/DomainParser/Punycode.swift Sources/DomainParser/Internal/Punycode.swift
```

The existing `PunycodeTests.swift` continues to cover it; no code change.

- [ ] **Step 2: Write the failing IPLiteral test**

```swift
// Tests/DomainParserTests/IPLiteralTests.swift
import Testing
@testable import DomainParser

@Suite("IPLiteral")
struct IPLiteralTests {
    @Test(arguments: [
        "192.168.0.1", "8.8.8.8", "0.0.0.0", "255.255.255.255",
        "::1", "fe80::1", "2001:db8::ff00:42:8329",
        "[::1]", "[fe80::1]",
    ])
    func detectsIPLiterals(_ s: String) {
        #expect(IPLiteral.isIPLiteral(s))
    }

    @Test(arguments: [
        "example.com", "co.uk", "a.b.c", "1.2.3", // 3 octets: not IPv4
        "999.1.1.1",                              // out of range
        "localhost", "xn--85x722f.com.cn",
    ])
    func rejectsHostnames(_ s: String) {
        #expect(!IPLiteral.isIPLiteral(s))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter IPLiteral`
Expected: FAIL — `cannot find 'IPLiteral' in scope`.

- [ ] **Step 4: Implement IPLiteral**

```swift
// Sources/DomainParser/Internal/IPLiteral.swift
import Foundation

/// Detects IP-address literals so they can be rejected as non-hostnames.
/// A host is a literal if it parses as IPv4 (exactly four 0–255 octets) or as
/// IPv6 (optionally wrapped in `[...]`, the form a URL host component yields).
enum IPLiteral {
    static func isIPLiteral(_ host: String) -> Bool {
        var s = Substring(host)
        if s.first == "[", s.last == "]" {
            s = s.dropFirst().dropLast()
            return isIPv6(String(s))
        }
        return isIPv4(host) || isIPv6(host)
    }

    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            part.count >= 1 && part.count <= 3
                && part.allSatisfy(\.isNumber)
                && (UInt8(part) != nil)
        }
    }

    private static func isIPv6(_ s: String) -> Bool {
        // An IPv6 literal must contain a colon and parse via in6_addr.
        guard s.contains(":") else { return false }
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `swift test --filter IPLiteral` and `swift test --filter Punycode`
Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add Sources/DomainParser/Internal/Punycode.swift Sources/DomainParser/Internal/IPLiteral.swift Tests/DomainParserTests/IPLiteralTests.swift
git commit -m "refactor: move Punycode to Internal/, add IP-literal detection"
```

### Task 4: `Rule`, `RuleLabel`, `Section` + matching predicate

**Files:**
- Create: `Sources/DomainParser/Internal/Rule.swift`
- Test: `Tests/DomainParserTests/RuleTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/RuleTests.swift
import Testing
@testable import DomainParser

@Suite("Rule")
struct RuleTests {
    @Test func basicRuleMatchesEqualOrLongerHost() {
        let rule = Rule(source: "co.uk", section: .icann)
        #expect(rule.matches(["example", "co", "uk"]))
        #expect(rule.matches(["co", "uk"]))
        #expect(!rule.matches(["uk"]))               // too short
        #expect(!rule.matches(["example", "com"]))   // labels differ
    }

    @Test func wildcardMatchesAnyLeftmostLabel() {
        let rule = Rule(source: "*.ck", section: .icann)
        #expect(rule.matches(["example", "ck"]))
        #expect(rule.matches(["b", "example", "ck"]))
        #expect(!rule.matches(["ck"]))               // too short for *.ck
        #expect(rule.isWildcard)
        #expect(!rule.isException)
    }

    @Test func exceptionRuleParsesBangAndCountsLabels() {
        let rule = Rule(source: "!www.ck", section: .icann)
        #expect(rule.isException)
        #expect(rule.labelCount == 2)               // bang stripped: www.ck
        #expect(rule.matches(["www", "ck"]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Rule`
Expected: FAIL — `cannot find 'Rule' in scope`.

- [ ] **Step 3: Implement Rule**

```swift
// Sources/DomainParser/Internal/Rule.swift

/// Which division of the PSL a rule belongs to.
enum Section: Sendable, Equatable { case icann, privateSection }

/// One label of a rule.
enum RuleLabel: Sendable, Equatable {
    case literal(String)
    case wildcard          // a bare "*"; per the format, only ever leftmost
}

/// A single Public Suffix List rule, parsed from one line of the list.
struct Rule: Sendable {
    /// Labels left-to-right, e.g. ["*", "ck"] or ["co", "uk"]. The leading "!"
    /// of an exception is stripped here and recorded in `isException`.
    let labels: [RuleLabel]
    let isException: Bool
    let section: Section

    /// Rightmost label as a string — always literal in real PSL data.
    /// Used as the index key.
    let lastLabel: String

    init(source: Substring, section: Section) {
        let isException = source.first == "!"
        let body = isException ? source.dropFirst() : source
        let parts = body.split(separator: ".").map { part -> RuleLabel in
            part == "*" ? .wildcard : .literal(String(part))
        }
        self.labels = parts
        self.isException = isException
        self.section = section
        if case .literal(let s) = parts.last { self.lastLabel = s }
        else { self.lastLabel = "" } // a rule ending in "*" is invalid input
    }

    init(source: String, section: Section) {
        self.init(source: Substring(source), section: section)
    }

    /// Number of labels the rule constrains (bang already excluded).
    var labelCount: Int { labels.count }

    var isWildcard: Bool { labels.contains(.wildcard) }

    /// True if this rule matches a host given as normalized labels
    /// (left-to-right). PSL rule: the host must have at least as many labels
    /// as the rule, and, comparing from the right, each rule label is identical
    /// to the host label or is the wildcard.
    func matches(_ hostLabels: [String]) -> Bool {
        guard hostLabels.count >= labels.count else { return false }
        for offset in 1...labels.count {
            let ruleLabel = labels[labels.count - offset]
            let hostLabel = hostLabels[hostLabels.count - offset]
            switch ruleLabel {
            case .wildcard: continue
            case .literal(let s): if s != hostLabel { return false }
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter Rule`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/Internal/Rule.swift Tests/DomainParserTests/RuleTests.swift
git commit -m "feat: add sectioned Rule model with matching predicate"
```

### Task 5: `RuleIndex` + prevailing-rule resolution

This is the heart of the algorithm: gather candidate rules by rightmost label, filter by scope, and pick the prevailing rule (exception → most labels → implicit `*`).

**Files:**
- Create: `Sources/DomainParser/Internal/RuleIndex.swift`
- Test: `Tests/DomainParserTests/RuleIndexTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/RuleIndexTests.swift
import Testing
@testable import DomainParser

@Suite("RuleIndex")
struct RuleIndexTests {
    // Mini list exercising every priority path.
    let index = RuleIndex(rules: [
        Rule(source: "com", section: .icann),
        Rule(source: "jp", section: .icann),
        Rule(source: "*.yokohama.jp", section: .icann),
        Rule(source: "*.ck", section: .icann),
        Rule(source: "!www.ck", section: .icann),
        Rule(source: "*.foo", section: .icann),
        Rule(source: "bar.baz.foo", section: .icann),
        Rule(source: "github.io", section: .privateSection),
    ])

    func resolve(_ host: String, _ scope: MatchScope = .all) -> ResolvedRule {
        index.prevailingRule(for: host.split(separator: ".").map(String.init),
                             scope: scope)
    }

    @Test func basicMatch() {
        let r = resolve("a.b.example.com")
        #expect(r.labelCount == 1)
        #expect(r.source == .icann)
        #expect(!r.isException)
    }

    @Test func exceptionBeatsWildcard() {
        let r = resolve("www.ck")            // matches *.ck and !www.ck
        #expect(r.isException)
        #expect(r.labelCount == 2)
    }

    @Test func mostLabelsWins_wildcardOverBase() {
        let r = resolve("a.b.ck")            // matches *.ck (2) and ck? (no base ck)
        #expect(r.isWildcard)
        #expect(r.labelCount == 2)
    }

    @Test func longerBasicRuleBeatsShorterWildcard() {
        // x.bar.baz.foo matches both *.foo (2 labels) and bar.baz.foo (3).
        // Most-labels wins across rule types → the basic rule.
        let r = resolve("x.bar.baz.foo")
        #expect(!r.isWildcard)
        #expect(r.labelCount == 3)
    }

    @Test func issue694_tooShortHostFallsBackToBase() {
        let r = resolve("yokohama.jp")       // *.yokohama.jp needs 3 labels
        #expect(!r.isWildcard)
        #expect(r.labelCount == 1)           // resolves to "jp"
    }

    @Test func defaultRuleWhenNothingMatches() {
        let r = resolve("foo.invalidtld")
        #expect(r.kind == .defaultStar)
        #expect(r.labelCount == 1)
    }

    @Test func privateRuleIgnoredUnderIcannOnly() {
        let all = resolve("alice.github.io", .all)
        #expect(all.labelCount == 2)         // github.io (private)
        #expect(all.source == .privateRule)
        let icann = resolve("alice.github.io", .icannOnly)
        #expect(icann.kind == .defaultStar)  // only "io" would match; none here
        #expect(icann.labelCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RuleIndex`
Expected: FAIL — `cannot find 'RuleIndex' in scope`.

- [ ] **Step 3: Implement RuleIndex and ResolvedRule**

```swift
// Sources/DomainParser/Internal/RuleIndex.swift

/// The outcome of resolving the prevailing rule for a host.
struct ResolvedRule: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case explicit, defaultStar }
    let kind: Kind
    let labelCount: Int      // labels the prevailing rule constrains
    let isException: Bool
    let isWildcard: Bool
    let source: MatchSource  // .icann / .privateRule / .defaultRule

    static let defaultStar = ResolvedRule(
        kind: .defaultStar, labelCount: 1, isException: false,
        isWildcard: true, source: .defaultRule)
}

/// All rules indexed by their rightmost (literal) label. Querying fetches the
/// small bucket for the host's rightmost label and resolves among it.
struct RuleIndex: Sendable {
    private let rulesByLastLabel: [String: [Rule]]

    init(rules: [Rule]) {
        var byLast: [String: [Rule]] = [:]
        for rule in rules where !rule.lastLabel.isEmpty {
            byLast[rule.lastLabel, default: []].append(rule)
        }
        self.rulesByLastLabel = byLast
    }

    var icannRuleCount: Int {
        rulesByLastLabel.values.reduce(0) { $0 + $1.filter { $0.section == .icann }.count }
    }
    var privateRuleCount: Int {
        rulesByLastLabel.values.reduce(0) { $0 + $1.filter { $0.section == .privateSection }.count }
    }

    /// Resolve the prevailing rule for `hostLabels` (normalized, left-to-right).
    func prevailingRule(for hostLabels: [String], scope: MatchScope) -> ResolvedRule {
        guard let last = hostLabels.last,
              let bucket = rulesByLastLabel[last] else {
            return .defaultStar
        }

        var best: Rule?
        for rule in bucket {
            if scope == .icannOnly, rule.section == .privateSection { continue }
            guard rule.matches(hostLabels) else { continue }
            if isHigherPriority(rule, than: best) { best = rule }
        }

        guard let winner = best else { return .defaultStar }
        return ResolvedRule(
            kind: .explicit,
            labelCount: winner.labelCount,
            isException: winner.isException,
            isWildcard: winner.isWildcard,
            source: winner.section == .icann ? .icann : .privateRule)
    }

    /// PSL priority: an exception beats any non-exception; otherwise more
    /// labels wins. (Two exceptions or two non-exceptions tie on label count;
    /// real PSL data has no such ambiguous pair, so either order is fine.)
    private func isHigherPriority(_ candidate: Rule, than current: Rule?) -> Bool {
        guard let current else { return true }
        if candidate.isException != current.isException {
            return candidate.isException
        }
        return candidate.labelCount > current.labelCount
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RuleIndex`
Expected: PASS (all six tests, including #694 and scope).

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/Internal/RuleIndex.swift Tests/DomainParserTests/RuleIndexTests.swift
git commit -m "feat: add RuleIndex with full PSL prevailing-rule resolution"
```

---

## Phase 3 — Host normalization and the loader

### Task 6: `NormalizedHost`

**Files:**
- Create: `Sources/DomainParser/Internal/NormalizedHost.swift`
- Test: `Tests/DomainParserTests/NormalizedHostTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/NormalizedHostTests.swift
import Testing
@testable import DomainParser

@Suite("NormalizedHost")
struct NormalizedHostTests {
    @Test func lowercasesAndSplits() throws {
        let h = try #require(NormalizedHost("WwW.Example.COM"))
        #expect(h.originalLabels == ["www", "example", "com"])
        #expect(h.matchLabels == ["www", "example", "com"])
        #expect(!h.hadTrailingDot)
    }

    @Test func preservesTrailingDot() throws {
        let h = try #require(NormalizedHost("example.com."))
        #expect(h.originalLabels == ["example", "com"])
        #expect(h.hadTrailingDot)
    }

    @Test func decodesPunycodeForMatchingOnly() throws {
        let h = try #require(NormalizedHost("xn--85x722f.com.cn"))
        #expect(h.originalLabels == ["xn--85x722f", "com", "cn"]) // ACE preserved
        #expect(h.matchLabels.first != "xn--85x722f")             // decoded
    }

    @Test func rejectsEmptyAndLeadingDotAndDoubleDot() {
        #expect(NormalizedHost("") == nil)
        #expect(NormalizedHost(".") == nil)
        #expect(NormalizedHost(".com") == nil)
        #expect(NormalizedHost("foo..com") == nil)
    }

    @Test func rejectsIPLiterals() {
        #expect(NormalizedHost("192.168.0.1") == nil)
        #expect(NormalizedHost("[::1]") == nil)
    }

    @Test func outputJoinAppendsTrailingDotWhenPresent() throws {
        let h = try #require(NormalizedHost("example.com."))
        #expect(h.joinedOriginal(from: 0) == "example.com.")
        let h2 = try #require(NormalizedHost("example.com"))
        #expect(h2.joinedOriginal(from: 0) == "example.com")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NormalizedHost`
Expected: FAIL — `cannot find 'NormalizedHost' in scope`.

- [ ] **Step 3: Implement NormalizedHost**

```swift
// Sources/DomainParser/Internal/NormalizedHost.swift

/// A host split into labels in two parallel forms, with FQDN/validity handling.
///
/// - `originalLabels`: lowercased, original ACE/Unicode form — used to build
///   output so the caller gets back the same form they passed in.
/// - `matchLabels`: lowercased, xn-- labels Punycode-decoded — used to match
///   the Unicode-form bundled rules.
struct NormalizedHost {
    let originalLabels: [String]
    let matchLabels: [String]
    let hadTrailingDot: Bool

    /// Returns nil for non-hostnames: empty input, IP literals, empty/leading
    /// labels. A single trailing dot is allowed and recorded.
    init?(_ host: String) {
        guard !host.isEmpty, !IPLiteral.isIPLiteral(host) else { return nil }

        let lowered = host.lowercased()

        // Trailing dot (FQDN): allowed once, preserved; stripped for splitting.
        var core = Substring(lowered)
        var trailingDot = false
        if core.last == "." {
            core = core.dropLast()
            trailingDot = true
        }
        guard !core.isEmpty else { return nil } // host was only dots

        // Empty labels (leading/interior/another trailing) are not permitted.
        let rawLabels = core.split(separator: ".", omittingEmptySubsequences: false)
        guard rawLabels.allSatisfy({ !$0.isEmpty }) else { return nil }

        let original = rawLabels.map(String.init)
        self.originalLabels = original
        self.hadTrailingDot = trailingDot
        self.matchLabels = original.map { label in
            guard label.hasPrefix("xn--"),
                  let decoded = Punycode.decode(String(label.dropFirst(4))) else {
                return label
            }
            return decoded
        }
    }

    /// Join original labels from index `from` to the end, re-appending the
    /// trailing dot if the input had one.
    func joinedOriginal(from index: Int) -> String {
        let joined = originalLabels[index...].joined(separator: ".")
        return hadTrailingDot ? joined + "." : joined
    }

    var labelCount: Int { originalLabels.count }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NormalizedHost`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/Internal/NormalizedHost.swift Tests/DomainParserTests/NormalizedHostTests.swift
git commit -m "feat: add NormalizedHost (FQDN, punycode, IP/empty rejection)"
```

### Task 7: `RulesParser` (sectioned + metadata header)

The bundled `.dat` will, after Task 12, contain a metadata header and section markers. The parser reads them. Format the loader expects (produced by `UpdatePSL.swift`):

```
# source-date: 2026-05-28
# source-revision: <git-sha-or-blank>
# ===ICANN===
com
co.uk
...
# ===PRIVATE===
github.io
...
```

(`#`-prefixed header lines and `# ===SECTION===` markers; rule lines are bare.)

**Files:**
- Create: `Sources/DomainParser/Internal/RulesParser.swift`
- Test: `Tests/DomainParserTests/RulesParserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/RulesParserTests.swift
import Foundation
import Testing
@testable import DomainParser

@Suite("RulesParser")
struct RulesParserTests {
    let sample = """
    # source-date: 2026-05-28
    # source-revision: abc123
    # ===ICANN===
    com
    co.uk
    *.ck
    !www.ck
    # ===PRIVATE===
    github.io
    """

    @Test func parsesSectionsAndMetadata() throws {
        let parsed = try RulesParser.parse(Data(sample.utf8))
        #expect(parsed.metadata.sourceDate == "2026-05-28")
        #expect(parsed.metadata.sourceRevision == "abc123")
        #expect(parsed.metadata.icannRuleCount == 4)
        #expect(parsed.metadata.privateRuleCount == 1)
    }

    @Test func icannOnlyExcludesPrivate() throws {
        let parsed = try RulesParser.parse(Data(sample.utf8))
        // github.io resolves only when private rules are included.
        let all = parsed.index.prevailingRule(for: ["alice", "github", "io"], scope: .all)
        #expect(all.source == .privateRule)
        let icann = parsed.index.prevailingRule(for: ["alice", "github", "io"], scope: .icannOnly)
        #expect(icann.kind == .defaultStar)
    }

    @Test func rejectsNonUTF8() {
        let bad = Data([0xFF, 0xFE, 0xFF])
        #expect(throws: PublicSuffixListError.self) {
            try RulesParser.parse(bad)
        }
    }

    @Test func toleratesRawUpstreamFormatWithoutHeader() throws {
        // A list with no header/markers: treat everything as ICANN, read each
        // line up to first whitespace, skip "//" comments.
        let raw = "// comment\ncom\nco.uk  trailing ignored\n"
        let parsed = try RulesParser.parse(Data(raw.utf8))
        #expect(parsed.metadata.icannRuleCount == 2)
        #expect(parsed.metadata.sourceDate == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RulesParser`
Expected: FAIL — `cannot find 'RulesParser' in scope`.

- [ ] **Step 3: Implement RulesParser**

```swift
// Sources/DomainParser/Internal/RulesParser.swift
import Foundation

struct ParsedList: Sendable {
    let index: RuleIndex
    let metadata: ListMetadata
}

enum RulesParser {
    static func parse(_ data: Data) throws(PublicSuffixListError) -> ParsedList {
        guard let text = String(data: data, encoding: .utf8) else {
            throw .ruleParsingError(message: "List bytes are not valid UTF-8.")
        }

        var sourceDate: String?
        var sourceRevision: String?
        var section: Section = .icann   // default before any marker
        var rules: [Rule] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: \.isWhitespace)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let header = line.dropFirst().drop(while: { $0 == " " })
                if header.hasPrefix("===ICANN===") { section = .icann }
                else if header.hasPrefix("===PRIVATE===") { section = .privateSection }
                else if let v = value(of: "source-date:", in: header) { sourceDate = v }
                else if let v = value(of: "source-revision:", in: header) { sourceRevision = v }
                continue
            }
            if line.hasPrefix("//") { continue } // raw upstream comment

            // Each rule line is read up to the first whitespace.
            let token = line.prefix { !$0.isWhitespace }
            guard !token.isEmpty else { continue }
            rules.append(Rule(source: token, section: section))
        }

        let index = RuleIndex(rules: rules)
        let metadata = ListMetadata(
            sourceDate: sourceDate, sourceRevision: sourceRevision,
            icannRuleCount: index.icannRuleCount,
            privateRuleCount: index.privateRuleCount)
        return ParsedList(index: index, metadata: metadata)
    }

    private static func value(of key: String, in header: Substring) -> String? {
        guard header.hasPrefix(key) else { return nil }
        let v = header.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RulesParser`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/Internal/RulesParser.swift Tests/DomainParserTests/RulesParserTests.swift
git commit -m "feat: add sectioned RulesParser with metadata header"
```

---

## Phase 4 — Public type, protocol, conveniences

### Task 8: `PublicSuffixList` core (factories + `lookup`)

**Files:**
- Create: `Sources/DomainParser/PublicSuffixList.swift`
- Test: `Tests/DomainParserTests/PublicSuffixListCoreTests.swift`

- [ ] **Step 1: Write the failing test** (drives `lookup` end-to-end with `loading(from:)`)

```swift
// Tests/DomainParserTests/PublicSuffixListCoreTests.swift
import Foundation
import Testing
@testable import DomainParser

@Suite("PublicSuffixList core")
struct PublicSuffixListCoreTests {
    static let listText = """
    # source-date: 2026-05-28
    # ===ICANN===
    com
    co.uk
    jp
    *.yokohama.jp
    *.ck
    !www.ck
    # ===PRIVATE===
    github.io
    """

    func make() async throws -> PublicSuffixList {
        try await PublicSuffixList.loading(from: Data(Self.listText.utf8))
    }

    @Test func apexAndSubdomain() async throws {
        let psl = try await make()
        let info = try #require(psl.lookup("api.github.com"))
        #expect(info.publicSuffix == "com")
        #expect(info.registrableDomain == "github.com")
        #expect(info.subdomain == "api")
        #expect(info.source == .icann)
    }

    @Test func privateRuleIsolatesTenants() async throws {
        let psl = try await make()
        let a = try #require(psl.lookup("alice.github.io"))
        #expect(a.publicSuffix == "github.io")
        #expect(a.registrableDomain == "alice.github.io")
        #expect(a.source == .privateRule)
    }

    @Test func icannOnlyCollapsesPrivate() async throws {
        let psl = try await make()
        let a = try #require(psl.lookup("alice.github.io", scope: .icannOnly))
        // No "io" rule in this mini list → default rule, suffix "io".
        #expect(a.publicSuffix == "io")
        #expect(a.registrableDomain == "github.io")
        #expect(a.source == .defaultRule)
    }

    @Test func bareSuffixHasNoRegistrableDomain() async throws {
        let psl = try await make()
        let info = try #require(psl.lookup("co.uk"))
        #expect(info.publicSuffix == "co.uk")
        #expect(info.registrableDomain == nil)
        #expect(info.isPublicSuffix)
    }

    @Test func issue694() async throws {
        let psl = try await make()
        let info = try #require(psl.lookup("yokohama.jp"))
        #expect(info.publicSuffix == "jp")
        #expect(info.registrableDomain == "yokohama.jp")
        #expect(info.source == .icann)
    }

    @Test func trailingDotPreserved() async throws {
        let psl = try await make()
        let info = try #require(psl.lookup("api.github.com."))
        #expect(info.publicSuffix == "com.")
        #expect(info.registrableDomain == "github.com.")
        #expect(info.subdomain == "api")
    }

    @Test func nonHostnamesReturnNil() async throws {
        let psl = try await make()
        #expect(psl.lookup("") == nil)
        #expect(psl.lookup("192.168.0.1") == nil)
        #expect(psl.lookup(".com") == nil)
    }

    @Test func metadataExposed() async throws {
        let psl = try await make()
        #expect(psl.metadata.sourceDate == "2026-05-28")
        #expect(psl.metadata.privateRuleCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "PublicSuffixList core"`
Expected: FAIL — `cannot find 'PublicSuffixList' in scope`.

- [ ] **Step 3: Implement PublicSuffixList**

```swift
// Sources/DomainParser/PublicSuffixList.swift
import Foundation

/// Matches hostnames against the Public Suffix List.
///
/// Immutable and `Sendable`: build one instance (await a factory) and share it
/// across threads and actors. Construction parses the list; `lookup` is a pure,
/// instant value query.
public struct PublicSuffixList: PublicSuffixMatching, Sendable {
    private let index: RuleIndex

    /// Provenance of the loaded list, for diagnostics.
    public let metadata: ListMetadata

    private init(parsed: ParsedList) {
        self.index = parsed.index
        self.metadata = parsed.metadata
    }

    /// Load the bundled Public Suffix List. Expensive (disk I/O + parse of
    /// ~10K rules); runs off the caller's actor via `@concurrent`.
    @concurrent
    public static func bundled() async throws(PublicSuffixListError) -> PublicSuffixList {
        try PublicSuffixList(parsed: RulesParser.parse(loadBundledData()))
    }

    /// Load from caller-supplied list bytes (custom lists / tests).
    @concurrent
    public static func loading(from data: Data) async throws(PublicSuffixListError) -> PublicSuffixList {
        try PublicSuffixList(parsed: RulesParser.parse(data))
    }

    /// Look a host up against the list. Returns nil only for non-hostnames
    /// (empty, IP literal, empty/leading label). Every real hostname yields a
    /// `HostInfo` because the implicit "*" rule guarantees a suffix.
    public func lookup(_ host: String, scope: MatchScope = .all) -> HostInfo? {
        guard let h = NormalizedHost(host) else { return nil }
        let rule = index.prevailingRule(for: h.matchLabels, scope: scope)

        // Public-suffix label count = rule labels, minus one if it is an
        // exception rule (an exception removes its leftmost label).
        let suffixLabelCount = rule.isException ? rule.labelCount - 1 : rule.labelCount
        guard suffixLabelCount >= 1, suffixLabelCount <= h.labelCount else { return nil }

        let suffixStart = h.labelCount - suffixLabelCount
        let publicSuffix = h.joinedOriginal(from: suffixStart)

        let registrableDomain: String?
        let subdomain: String?
        if suffixStart >= 1 {
            registrableDomain = h.joinedOriginal(from: suffixStart - 1)
            subdomain = suffixStart >= 2
                ? h.originalLabels[0..<(suffixStart - 1)].joined(separator: ".")
                : nil
        } else {
            registrableDomain = nil   // host is itself a bare public suffix
            subdomain = nil
        }

        return HostInfo(publicSuffix: publicSuffix,
                        registrableDomain: registrableDomain,
                        subdomain: subdomain,
                        source: rule.source)
    }

    private static func loadBundledData() throws(PublicSuffixListError) -> Data {
        guard let url = Bundle.module.url(forResource: "public_suffix_list",
                                          withExtension: "dat") else {
            throw .missingBundledResource
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .bundleLoadFailed(underlying: error)
        }
    }
}
```

Note: `registrableDomain` is built from `joinedOriginal` so it carries the trailing dot; `subdomain` never includes the trailing dot (it is never the rightmost label).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "PublicSuffixList core"`
Expected: PASS (all cases incl. trailing dot, #694, scope, metadata).

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/PublicSuffixList.swift Tests/DomainParserTests/PublicSuffixListCoreTests.swift
git commit -m "feat: add PublicSuffixList with async factories and lookup"
```

### Task 9: `PublicSuffixMatching` protocol + conveniences

**Files:**
- Create: `Sources/DomainParser/PublicSuffixMatching.swift`
- Test: `Tests/DomainParserTests/ConvenienceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/ConvenienceTests.swift
import Foundation
import Testing
@testable import DomainParser

@Suite("Conveniences")
struct ConvenienceTests {
    func make() async throws -> PublicSuffixList {
        try await PublicSuffixList.loading(from: Data("""
        # ===ICANN===
        com
        co.uk
        # ===PRIVATE===
        github.io
        """.utf8))
    }

    @Test func accessors() async throws {
        let psl = try await make()
        #expect(psl.registrableDomain(of: "api.github.com") == "github.com")
        #expect(psl.publicSuffix(of: "api.github.com") == "com")
        #expect(psl.isPublicSuffix("co.uk"))
        #expect(!psl.isPublicSuffix("example.co.uk"))
    }

    @Test func urlOverload() async throws {
        let psl = try await make()
        let url = URL(string: "https://api.github.com/x")!
        #expect(psl.lookup(url)?.registrableDomain == "github.com")
        #expect(psl.lookup(URL(string: "file:///tmp/x")!) == nil) // no host
    }

    @Test func sameRegistrableDomain() async throws {
        let psl = try await make()
        #expect(psl.haveSameRegistrableDomain("a.github.com", "b.github.com"))
        #expect(!psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io"))
        #expect(!psl.haveSameRegistrableDomain("co.uk", "co.uk")) // bare suffix
        #expect(psl.haveSameRegistrableDomain("github.com", "github.com.")) // trailing dot
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Conveniences`
Expected: FAIL — `cannot find 'PublicSuffixMatching'`/missing methods.

- [ ] **Step 3: Implement the protocol + extensions**

```swift
// Sources/DomainParser/PublicSuffixMatching.swift
import Foundation

/// The capability implemented by `PublicSuffixList`. Conformers are `Sendable`
/// so a single instance can be shared across isolation domains. Construction
/// is the expensive step; per-call lookup is cheap.
///
/// Only `lookup(_:scope:)` is a requirement — every other entry point below is
/// a default implementation, so a test double need only implement `lookup`.
public protocol PublicSuffixMatching: Sendable {
    /// Returns the decomposition of `host`, or nil for non-hostnames.
    func lookup(_ host: String, scope: MatchScope) -> HostInfo?
}

extension PublicSuffixMatching {
    /// Look up a URL's host component. Returns nil if the URL has no host.
    public func lookup(_ url: URL, scope: MatchScope = .all) -> HostInfo? {
        guard let host = url.host() else { return nil }
        return lookup(host, scope: scope)
    }

    public func registrableDomain(of host: String, scope: MatchScope = .all) -> String? {
        lookup(host, scope: scope)?.registrableDomain
    }

    public func publicSuffix(of host: String, scope: MatchScope = .all) -> String? {
        lookup(host, scope: scope)?.publicSuffix
    }

    public func isPublicSuffix(_ host: String, scope: MatchScope = .all) -> Bool {
        lookup(host, scope: scope)?.isPublicSuffix ?? false
    }

    /// Do two hosts resolve to the same registrable domain? false if either is
    /// a bare suffix or unparseable. PRIVATE rules included by default, so
    /// alice.github.io and bob.github.io are NOT equal.
    ///
    /// Scheme-agnostic registrable-domain equality — not the web platform's
    /// schemeful "same-site" (RFC 6265bis). Trailing dots are canonicalized
    /// away before comparing.
    public func haveSameRegistrableDomain(_ a: String, _ b: String,
                                          scope: MatchScope = .all) -> Bool {
        func key(_ host: String) -> String? {
            guard var rd = lookup(host, scope: scope)?.registrableDomain else { return nil }
            if rd.hasSuffix(".") { rd.removeLast() }
            return rd
        }
        guard let ka = key(a), let kb = key(b) else { return false }
        return ka == kb
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter Conveniences`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/PublicSuffixMatching.swift Tests/DomainParserTests/ConvenienceTests.swift
git commit -m "feat: add PublicSuffixMatching protocol and convenience extensions"
```

### Task 10: `shared()` accessor

**Files:**
- Create: `Sources/DomainParser/SharedList.swift`
- Modify: `Sources/DomainParser/PublicSuffixList.swift` (add `shared()`)
- Test: `Tests/DomainParserTests/SharedListTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DomainParserTests/SharedListTests.swift
import Testing
@testable import DomainParser

@Suite("shared()")
struct SharedListTests {
    @Test func returnsSameUnderlyingListTwice() async throws {
        let a = try await PublicSuffixList.shared()
        let b = try await PublicSuffixList.shared()
        // Same bundled data → identical metadata and lookups.
        #expect(a.metadata == b.metadata)
        #expect(a.lookup("api.github.com")?.registrableDomain
                == b.lookup("api.github.com")?.registrableDomain)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "shared()"`
Expected: FAIL — `type 'PublicSuffixList' has no member 'shared'`.

- [ ] **Step 3: Implement the cache actor and `shared()`**

```swift
// Sources/DomainParser/SharedList.swift

/// Caches the bundled list so `PublicSuffixList.shared()` loads it once.
actor SharedListCache {
    static let instance = SharedListCache()
    private var cached: PublicSuffixList?

    func value() async throws(PublicSuffixListError) -> PublicSuffixList {
        if let cached { return cached }
        let list = try await PublicSuffixList.bundled()
        cached = list
        return list
    }
}
```

Add to `PublicSuffixList.swift` (after `loading(from:)`):

```swift
    /// Convenience for callers that don't want to own the lifecycle: loads the
    /// bundled list once and returns the cached value thereafter. Cost is still
    /// explicit (you await); trade-off is process-lifetime retention. Use
    /// `bundled()` to control the lifetime yourself.
    public static func shared() async throws(PublicSuffixListError) -> PublicSuffixList {
        try await SharedListCache.instance.value()
    }
```

Note: `try await` of an actor method that has a typed `throws(PublicSuffixListError)` propagates the typed error. If the compiler rejects the typed-throws propagation across the actor hop, change `SharedListCache.value()` to untyped `throws` and re-wrap: `do { return try await ... } catch let e as PublicSuffixListError { throw e } catch { throw .bundleLoadFailed(underlying: error) }`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "shared()"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DomainParser/SharedList.swift Sources/DomainParser/PublicSuffixList.swift Tests/DomainParserTests/SharedListTests.swift
git commit -m "feat: add actor-cached PublicSuffixList.shared()"
```

---

## Phase 5 — Tooling: sectioned bundled list + metadata

### Task 11: Update `UpdatePSL.swift` to preserve sections and write a header

The current normalizer strips all `//` lines (including the section markers) and writes bare rules sorted by label count. The new format keeps the two sections and prepends a metadata header.

**Files:**
- Modify: `script/UpdatePSL.swift`

- [ ] **Step 1: Replace `PublicSuffixListNormalizer.normalize()`**

Replace the body so it walks the upstream file, tracks the current section from the `===BEGIN ICANN DOMAINS===` / `===BEGIN PRIVATE DOMAINS===` markers, and emits the new format. Replace the existing `struct PublicSuffixListNormalizer { ... }` with:

```swift
struct PublicSuffixListNormalizer {
    let data: Data
    let sourceDate: String          // ISO-8601, passed in (no Date() in scripts/tests)

    private func isComment(_ line: String) -> Bool { line.hasPrefix("//") }

    func normalize() throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PSLUpdateError.notUTF8Convertible
        }

        var icann: [String] = []
        var priv: [String] = []
        var inPrivate = false

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("===BEGIN PRIVATE DOMAINS===") { inPrivate = true; continue }
            if trimmed.contains("===BEGIN ICANN DOMAINS===") { inPrivate = false; continue }
            if trimmed.isEmpty || isComment(trimmed) { continue }
            guard let token = trimmed.components(separatedBy: .whitespaces).first,
                  !token.isEmpty else { continue }
            if inPrivate { priv.append(token) } else { icann.append(token) }
        }

        // Higher-label-count rules first within each section (priority hint).
        let byLabels: (String, String) -> Bool = {
            $0.split(separator: ".").count > $1.split(separator: ".").count
        }
        icann.sort(by: byLabels)
        priv.sort(by: byLabels)

        var out = "# source-date: \(sourceDate)\n"
        out += "# source-revision:\n"          // upstream .dat has no revision; left blank
        out += "# ===ICANN===\n"
        out += icann.joined(separator: "\n")
        out += "\n# ===PRIVATE===\n"
        out += priv.joined(separator: "\n")
        out += "\n"
        return Data(out.utf8)
    }
}
```

- [ ] **Step 2: Pass the date at the call site**

In the `do { ... }` block, change the normalizer construction to supply the date. Replace:

```swift
    let normalized = try PublicSuffixListNormalizer(data: raw).normalize()
```

with:

```swift
    let today = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt,
        formatOptions: [.withFullDate])
    let normalized = try PublicSuffixListNormalizer(data: raw, sourceDate: today).normalize()
```

(`Date()` is fine in this script — it runs in CI, not inside a Workflow.)

- [ ] **Step 3: Regenerate the bundled list and confirm shape**

Run: `swift script/UpdatePSL.swift`
Then verify the header and both markers are present:

Run: `head -5 Sources/DomainParser/Resources/public_suffix_list.dat && grep -c '===PRIVATE===' Sources/DomainParser/Resources/public_suffix_list.dat`
Expected: header lines visible; grep prints `1`.

- [ ] **Step 4: Confirm the library loads the regenerated file**

Run: `swift test --filter "PublicSuffixList core"` is unaffected (uses `loading(from:)`); add a quick bundled check:

Run: `swift test --filter "shared()"`
Expected: PASS — `shared()` loads the regenerated bundled file with non-zero `privateRuleCount`.

- [ ] **Step 5: Commit (code + regenerated data separately)**

```bash
git add script/UpdatePSL.swift
git commit -m "feat(script): preserve ICANN/PRIVATE sections and write metadata header"
git add Sources/DomainParser/Resources/public_suffix_list.dat
git commit -m "data: regenerate bundled PSL in sectioned format with header"
```

---

## Phase 6 — Conformance suite + cleanup of old API

### Task 12: Port the official PSL conformance suite

The current `PSLTests.swift` hand-lists cases against `DomainParser`. Replace with a suite that runs the upstream `tests/test_psl.txt` format against `lookup`, plus the curated edge cases.

**Files:**
- Create: `Tests/DomainParserTests/Resources/test_psl.txt` (vendored upstream test file)
- Create: `Tests/DomainParserTests/ConformanceTests.swift`
- Modify: `Package.swift` (add test resource)

- [ ] **Step 1: Vendor the upstream test file**

Download the official suite into the test resources:

Run:
```bash
mkdir -p Tests/DomainParserTests/Resources
curl -fsSL https://raw.githubusercontent.com/publicsuffix/list/master/tests/test_psl.txt \
  -o Tests/DomainParserTests/Resources/test_psl.txt
head -20 Tests/DomainParserTests/Resources/test_psl.txt
```
Expected: file of `checkPublicSuffix('...', '...');` lines and `//` comments.

- [ ] **Step 2: Declare the test resource in `Package.swift`**

In the `testTarget(name: "DomainParserTests", ...)` add a resources argument:

```swift
        .testTarget(
            name: "DomainParserTests",
            dependencies: ["DomainParser"],
            resources: [.process("Resources")],
            swiftSettings: upcomingFeatures
        ),
```

- [ ] **Step 3: Write the conformance runner test**

```swift
// Tests/DomainParserTests/ConformanceTests.swift
import Foundation
import Testing
@testable import DomainParser

@Suite("Official PSL conformance")
struct ConformanceTests {
    struct Case: Sendable { let host: String; let expected: String? }

    static let cases: [Case] = {
        guard let url = Bundle.module.url(forResource: "test_psl", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Case] = []
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("checkPublicSuffix(") else { continue }
            // checkPublicSuffix('host', 'expected');  | expected may be null
            let inner = t.dropFirst("checkPublicSuffix(".count).dropLast(2) // ");
            let args = inner.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            func unquote(_ s: String) -> String? {
                if s == "null" { return nil }
                return String(s.dropFirst().dropLast()) // strip surrounding quotes
            }
            guard args.count == 2, let host = unquote(args[0]) else { continue }
            out.append(Case(host: host, expected: unquote(args[1])))
        }
        return out
    }()

    @Test func suiteIsLoaded() {
        #expect(Self.cases.count > 50) // sanity: file parsed
    }

    @Test func conformance() async throws {
        let psl = try await PublicSuffixList.bundled()
        for c in Self.cases {
            // checkPublicSuffix expects the registrable domain (eTLD+1).
            let got = psl.lookup(c.host)?.registrableDomain
            #expect(got == c.expected, "host \(c.host): got \(String(describing: got)), expected \(String(describing: c.expected))")
        }
    }
}
```

- [ ] **Step 4: Run the conformance suite**

Run: `swift test --filter "Official PSL conformance"`
Expected: PASS. If specific cases fail, they indicate a real algorithm gap — fix `RuleIndex`/`PublicSuffixList`, not the test. (The upstream file omits a leading-dot/IP cases; it focuses on registrable-domain extraction.)

- [ ] **Step 5: Commit**

```bash
git add Tests/DomainParserTests/Resources/test_psl.txt Tests/DomainParserTests/ConformanceTests.swift Package.swift
git commit -m "test: run official PSL conformance suite against lookup"
```

### Task 13: Add curated edge-case tests (#694, scope, normalization)

**Files:**
- Create: `Tests/DomainParserTests/EdgeCaseTests.swift`

- [ ] **Step 1: Write the tests** (uses the bundled list, which contains the real rules)

```swift
// Tests/DomainParserTests/EdgeCaseTests.swift
import Foundation
import Testing
@testable import DomainParser

@Suite("Edge cases")
struct EdgeCaseTests {
    func psl() async throws -> PublicSuffixList { try await PublicSuffixList.bundled() }

    @Test func issue694_yokohamaAndKobe() async throws {
        let psl = try await psl()
        // Literal-algorithm reading: too-short host under *.yokohama.jp falls
        // back to base rule jp.
        #expect(psl.lookup("yokohama.jp")?.registrableDomain == "yokohama.jp")
        #expect(psl.lookup("yokohama.jp")?.publicSuffix == "jp")
        #expect(psl.lookup("kobe.jp")?.registrableDomain == "kobe.jp")
    }

    @Test func wildcardFamily_mm() async throws {
        let psl = try await psl()  // *.mm is a real rule
        #expect(psl.lookup("mm")?.registrableDomain == nil)
        #expect(psl.lookup("c.mm")?.registrableDomain == nil)
        #expect(psl.lookup("b.c.mm")?.registrableDomain == "b.c.mm")
    }

    @Test func privateTenantsAreDistinct() async throws {
        let psl = try await psl()  // github.io is a real PRIVATE rule
        #expect(!psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io"))
        // ICANN-only collapses them under the io registry.
        #expect(psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io",
                                              scope: .icannOnly))
    }

    @Test func defaultRuleForUnlistedTLD() async throws {
        let psl = try await psl()
        let info = try #require(psl.lookup("app.mycorp.internal"))
        #expect(info.publicSuffix == "internal")
        #expect(info.registrableDomain == "mycorp.internal")
        #expect(info.source == .defaultRule)
    }

    @Test func trailingDotPreservedAndCanonicalizedForComparison() async throws {
        let psl = try await psl()
        #expect(psl.lookup("github.com.")?.registrableDomain == "github.com.")
        #expect(psl.haveSameRegistrableDomain("github.com", "github.com."))
    }

    @Test(arguments: ["", ".", ".com", "foo..com", "192.168.0.1", "[::1]"])
    func nonHostnames(_ s: String) async throws {
        let psl = try await psl()
        #expect(psl.lookup(s) == nil)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter "Edge cases"`
Expected: PASS. (If `defaultRuleForUnlistedTLD` fails because `.internal` becomes a real PSL entry someday, switch to a guaranteed-unlisted TLD like `app.example.invalidtld`.)

- [ ] **Step 3: Commit**

```bash
git add Tests/DomainParserTests/EdgeCaseTests.swift
git commit -m "test: cover #694, scope, default-rule, normalization edge cases"
```

### Task 14: Delete the old API and its tests

**Files:**
- Delete: `Sources/DomainParser/DomainParser.swift`, `DomainParserProtocol.swift`, `BasicDomainParser.swift`, `HostLabels.swift`, `ParsedHost.swift`, `PSLSyntax.swift`, `Model/Rule.swift`, `Model/RuleLabel.swift`, `RulesParser.swift` (old)
- Delete: old `Tests/DomainParserTests/PSLTests.swift`, and the perf/old portions of `DomainParserTests.swift`

- [ ] **Step 1: Remove old sources**

```bash
git rm Sources/DomainParser/DomainParser.swift \
       Sources/DomainParser/DomainParserProtocol.swift \
       Sources/DomainParser/BasicDomainParser.swift \
       Sources/DomainParser/HostLabels.swift \
       Sources/DomainParser/ParsedHost.swift \
       Sources/DomainParser/PSLSyntax.swift \
       Sources/DomainParser/Model/Rule.swift \
       Sources/DomainParser/Model/RuleLabel.swift \
       Sources/DomainParser/RulesParser.swift
rmdir Sources/DomainParser/Model
```

- [ ] **Step 2: Remove/replace old tests**

`PSLTests.swift` and `DomainParserTests.swift` reference `DomainParser`. Delete `PSLTests.swift`; preserve any perf measurement by rewriting it against `PublicSuffixList.bundled()` if still wanted, else delete.

```bash
git rm Tests/DomainParserTests/PSLTests.swift
```

For `DomainParserTests.swift`: if it only held the XCTest `measure {}` perf test plus cases now covered by conformance, delete it; otherwise port the `measure` block to load `PublicSuffixList.bundled()`. Decide by reading it; default to delete if fully redundant.

- [ ] **Step 3: Build and run the whole suite**

Run: `swift build && swift test`
Expected: Build clean, all suites pass, no reference to removed symbols.

- [ ] **Step 4: Strict-concurrency gate**

Run: `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove the old DomainParser API"
```

---

## Phase 7 — Documentation

### Task 15: DocC catalog

**Files:**
- Create: `Sources/DomainParser/DomainParser.docc/DomainParser.md`
- Create: `Sources/DomainParser/DomainParser.docc/ICANNvsPrivate.md`
- Create: `Sources/DomainParser/DomainParser.docc/ChoosingAScope.md`
- Create: `Sources/DomainParser/DomainParser.docc/IDNHandling.md`

- [ ] **Step 1: Landing page**

```markdown
# ``DomainParser``

Match hostnames against the Public Suffix List.

## Overview

Given a host like `app.alice.github.io`, ``PublicSuffixList`` tells you the
public suffix (`github.io`), the registrable domain (`alice.github.io`), and
the subdomain (`app`). Loading parses the bundled list once; build a
``PublicSuffixList`` (await ``PublicSuffixList/bundled()`` or
``PublicSuffixList/shared()``) and share the immutable, `Sendable` value.

## Topics

### Essentials
- ``PublicSuffixList``
- ``HostInfo``
- ``MatchScope``

### Articles
- <doc:ICANNvsPrivate>
- <doc:ChoosingAScope>
- <doc:IDNHandling>
```

- [ ] **Step 2: ICANN vs PRIVATE article**

```markdown
# ICANN vs PRIVATE

Why `alice.github.io` and `bob.github.io` are different sites.

## Overview

The PSL has two sections. ICANN rules are real registry suffixes (`com`,
`co.uk`). PRIVATE rules are operators who delegate subdomains to untrusted
third parties (`github.io`, `blogspot.com`). For credential isolation you must
consult PRIVATE rules — otherwise per-tenant subdomains collapse to one
registrable domain. ``MatchScope/all`` (the default) includes PRIVATE rules;
``MatchScope/icannOnly`` ignores them.
```

- [ ] **Step 3: Choosing a scope article**

```markdown
# Choosing a Scope

When to use ``MatchScope/all`` versus ``MatchScope/icannOnly``.

## Overview

Use ``MatchScope/all`` (default) for credential matching and any "are these the
same site for trust purposes" question — it isolates per-tenant subdomains.
Use ``MatchScope/icannOnly`` when you want registry-level grouping that matches
cookie-style semantics and intentionally treats `*.github.io` as one site.
```

- [ ] **Step 4: IDN article**

```markdown
# IDN Handling

How internationalized names are matched, and the UTS-46 caveat.

## Overview

Hosts are lowercased and any `xn--` labels are Punycode-decoded for matching
against the Unicode-form bundled rules; the output preserves whichever form
(ACE or Unicode) you passed in. Normalization is `lowercased()` + Punycode, not
full UTS-46/IDNA2008 mapping, which needs ICU-grade tables. This passes the
official PSL test suite; a deliberately exotic Unicode host could in principle
normalize differently than a fully IDNA-compliant implementation.
```

- [ ] **Step 5: Build docs to verify the catalog resolves**

Run: `swift package generate-documentation --target DomainParser 2>/dev/null || swift build`
Expected: docs build with no unresolved symbol-link warnings (or, if the DocC plugin is unavailable locally, at least `swift build` stays clean — the catalog is compiled as a resource).

- [ ] **Step 6: Commit**

```bash
git add Sources/DomainParser/DomainParser.docc
git commit -m "docs: add DocC catalog (overview + ICANN/PRIVATE, scope, IDN)"
```

### Task 16: Rewrite README + CHANGELOG

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Rewrite the README usage section**

Replace the old `DomainParser()` examples with the new API. Core snippet to include verbatim:

````markdown
## Usage

```swift
import DomainParser

let psl = try await PublicSuffixList.shared()   // load once, cached

let info = psl.lookup("app.alice.github.io")!
info.publicSuffix        // "github.io"   (PRIVATE rule)
info.registrableDomain   // "alice.github.io"
info.subdomain           // "app"
info.source              // .privateRule

// Credential-matching primitive:
psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io")  // false

// Registry-level grouping instead:
psl.lookup("alice.github.io", scope: .icannOnly)?.publicSuffix     // "io"
```

Build one instance and share it — `PublicSuffixList` is an immutable `Sendable`
value. Use `PublicSuffixList.bundled()` if you want to own its lifetime, or
`shared()` for a process-wide cached instance.
````

Update the badges (Swift 6.2; platforms iOS/macOS/Linux/Windows). Remove all references to `DomainParser`, `ParsedHost`, `BasicDomainParser`.

- [ ] **Step 2: Add a CHANGELOG entry**

Prepend an entry documenting the breaking rewrite: renamed types, removed `BasicDomainParser`/fake, new `MatchScope`/`HostInfo.source`, ICANN/PRIVATE split, async loading, default-`*` rule, trailing-dot preservation, IP rejection, #694 stance.

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: rewrite README and CHANGELOG for the PublicSuffixList API"
```

---

## Phase 8 — Cross-platform CI

### Task 17: Linux (and Windows) test matrix

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Read the current test job**

Run: `cat .github/workflows/test.yml`
Confirm the existing macOS job and the `concurrency` block.

- [ ] **Step 2: Add a Linux job (and optional Windows)**

Add jobs that build + test on Linux via the official Swift container, keeping the existing macOS job:

```yaml
  test-linux:
    name: Test (Linux)
    runs-on: ubuntu-latest
    container: swift:6.2-noble
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift build
      - run: swift test

  test-windows:
    name: Test (Windows)
    runs-on: windows-latest
    continue-on-error: true   # best-effort until proven stable
    steps:
      - uses: actions/checkout@v4
      - uses: compnerd/gha-setup-swift@main
        with:
          branch: swift-6.2-release
          tag: 6.2-RELEASE
      - run: swift build
      - run: swift test
```

- [ ] **Step 3: Verify locally what you can**

Run (if Docker is available): `docker run --rm -v "$PWD":/p -w /p swift:6.2-noble swift test`
Expected: PASS on Linux — this is the real portability check (verifies `Bundle.module` resource loading and `inet_pton` under swift-corelibs-foundation).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add Linux and (best-effort) Windows test matrix"
```

---

## Phase 9 — Consumer migration (Passie, cross-repo)

> This phase happens in the `Passie/` repo after the library above is merged and the Forgejo `develop` tip is updated. It must start with a scan — the real call sites are not yet known.

### Task 18: Scan Passie for old-API usage

**Files:** (read-only investigation, in `Passie/`)

- [ ] **Step 1: Find every usage**

Run from `Passie/`:
```bash
rg -n "DomainParser|ParsedHost|BasicDomainParser|FakeDomainParser" Modules Passie-iOS Passie-macOS* 2>/dev/null
```
Record each call site and what it does (registrable-domain extraction, same-site check, preview/test fake).

- [ ] **Step 2: Write a migration sub-plan**

Based on the scan, write `Passie/docs/plans/<date>-adopt-publicsuffixlist.md` mapping each call site to the new API: `parse(host:)` → `lookup(_:)`; `.registrableDomain` access unchanged; any "same domain" logic → `haveSameRegistrableDomain`; preview/test `FakeDomainParser` → a consumer-local `struct StubPublicSuffixList: PublicSuffixMatching` returning canned `HostInfo`s. Confirm load happens off the hot path (await `shared()` at session/extension startup, not inside an autofill interaction).

- [ ] **Step 3: Execute the sub-plan** (its own TDD cycles, per call site), build the affected schemes, and verify AutoFill domain matching against a manual check (e.g. `alice.github.io` vs `bob.github.io` are not offered each other's credentials).

- [ ] **Step 4: Commit on the Passie side**, library-first ordering already satisfied (library merged in Phase 1–8).

---

## Self-review notes

- **Spec coverage:** every spec section maps to a task — types (T1–T2), loading/`@concurrent`/`shared` (T8, T10), protocol+conveniences+`haveSameRegistrableDomain` (T9), normalization incl. trailing-dot/IP/empty (T6), prevailing-rule resolution + #694 + wildcard semantics (T5, T13), ICANN/PRIVATE + tooling (T4, T7, T11), metadata (T2, T7, T11), conformance + edge tests (T12–T13), DocC (T15), README/CHANGELOG (T16), Linux/Windows (T17), Passie migration (T18).
- **Known follow-up flagged in tooling:** the stale "wildcards not restricted to leftmost" comment from the old `RuleLabel.swift` is dropped with the old files in T14; the new `Rule.swift` comment states the correct leftmost-only rule.
- **Type consistency:** `lookup(_:scope:)`, `HostInfo`, `MatchSource` (`.icann`/`.privateRule`/`.defaultRule`), `MatchScope` (`.all`/`.icannOnly`), `Section` (`.icann`/`.privateSection`), `ResolvedRule`, `RuleIndex.prevailingRule(for:scope:)`, `NormalizedHost.matchLabels/originalLabels/hadTrailingDot/joinedOriginal(from:)`, `ParsedList(index:metadata:)` are used consistently across tasks.
