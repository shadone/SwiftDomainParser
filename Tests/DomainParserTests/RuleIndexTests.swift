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
        let r = resolve("a.b.ck")            // matches *.ck (2); no base ck
        #expect(r.isWildcard)
        #expect(r.labelCount == 2)
    }

    @Test func longerBasicRuleBeatsShorterWildcard() {
        // x.bar.baz.foo matches both *.foo (2 labels) and bar.baz.foo (3).
        // Most-labels wins across rule types -> the basic rule.
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
