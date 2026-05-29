import Testing
@testable import PublicSuffixListKit

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
