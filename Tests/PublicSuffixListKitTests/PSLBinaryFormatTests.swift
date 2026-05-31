import Foundation
import Testing
@testable import PublicSuffixListKit

@Suite("PSLBinaryFormat")
struct PSLBinaryFormatTests {
    /// A small synthetic list exercising literals, multi-label rules, a
    /// wildcard, an exception, and both sections.
    private static func sampleParsed(sourceDate: String?, sourceRevision: String?) -> ParsedList {
        let rules: [Rule] = [
            Rule(labels: [.literal("com")], isException: false, section: .icann),
            Rule(labels: [.literal("co"), .literal("uk")], isException: false, section: .icann),
            Rule(labels: [.wildcard, .literal("ck")], isException: false, section: .icann),
            Rule(labels: [.literal("www"), .literal("ck")], isException: true, section: .icann),
            Rule(labels: [.literal("github"), .literal("io")], isException: false, section: .privateSection),
        ]
        let index = RuleIndex(rules: rules)
        let metadata = ListMetadata(
            sourceDate: sourceDate, sourceRevision: sourceRevision,
            icannRuleCount: index.icannRuleCount,
            privateRuleCount: index.privateRuleCount)
        return ParsedList(rules: rules, index: index, metadata: metadata)
    }

    @Test func roundTripPreservesRulesAndMetadata() throws {
        let original = Self.sampleParsed(sourceDate: "2026-05-31", sourceRevision: "abc123")

        let data = PSLBinaryFormat.encode(original)
        let decoded = try #require(PSLBinaryFormat.decode(data))

        #expect(decoded.rules == original.rules)
        #expect(decoded.index.buckets == original.index.buckets)
        #expect(decoded.metadata == original.metadata)
    }

    @Test func roundTripWithAbsentMetadataStrings() throws {
        let original = Self.sampleParsed(sourceDate: nil, sourceRevision: nil)

        let data = PSLBinaryFormat.encode(original)
        let decoded = try #require(PSLBinaryFormat.decode(data))

        #expect(decoded.metadata.sourceDate == nil)
        #expect(decoded.metadata.sourceRevision == nil)
        #expect(decoded.rules == original.rules)
    }

    @Test func decodeRejectsTruncatedAndWrongMagic() {
        let good = PSLBinaryFormat.encode(Self.sampleParsed(sourceDate: "2026-05-31", sourceRevision: nil))

        #expect(PSLBinaryFormat.decode(Data()) == nil)
        #expect(PSLBinaryFormat.decode(Data("XXXX".utf8)) == nil)
        #expect(PSLBinaryFormat.decode(good.prefix(good.count - 1)) == nil)
    }
}
