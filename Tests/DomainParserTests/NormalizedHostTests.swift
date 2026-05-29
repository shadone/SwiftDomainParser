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
