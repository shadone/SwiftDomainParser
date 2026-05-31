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

    // MARK: In-repo artifacts

    /// The in-repo Resources directory, located relative to this source file
    /// (the .dat is excluded from the bundle, so #filePath — not Bundle.module —
    /// is how the tool and this test reach it).
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()    // PublicSuffixListKitTests/
        .deletingLastPathComponent()    // Tests/
        .deletingLastPathComponent()    // repo root
        .appendingPathComponent("Sources/PublicSuffixListKit/Resources")

    /// Guards against "edited the .dat, forgot to regenerate the .bin" (and a
    /// stale checked-in .bin generally): parse the in-repo .dat with the real
    /// parser, decode the checked-in .bin, and assert they produce an identical
    /// index and metadata. A failure here means: `swift run psl-compile`.
    @Test func shippedBlobMatchesCheckedInDat() throws {
        let datData = try Data(contentsOf: Self.resources.appendingPathComponent("public_suffix_list.dat"))
        let binData = try Data(contentsOf: Self.resources.appendingPathComponent("public_suffix_list.bin"))

        let fromDat = try RulesParser.parse(datData)
        let fromBin = try #require(PSLBinaryFormat.decode(binData))

        #expect(fromBin.index.buckets == fromDat.index.buckets,
                "public_suffix_list.bin is stale — regenerate with `swift run psl-compile`")
        #expect(fromBin.metadata == fromDat.metadata)
    }

    /// Opt-in (set PSL_PERF) decode-cost guard, to keep the ~2 ms first-use cost
    /// (measured at -O on Apple Silicon) honest over time. Disabled by default
    /// because debug timing is noisy and this is a regression tripwire, not a
    /// benchmark. The ceiling catches an order-of-magnitude regression only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PSL_PERF"] != nil))
    func firstUseDecodeWithinBudget() throws {
        let binData = try Data(contentsOf: Self.resources.appendingPathComponent("public_suffix_list.bin"))
        let elapsed = ContinuousClock().measure {
            _ = PSLBinaryFormat.decode(binData)
        }
        #expect(elapsed < .milliseconds(100), "blob decode took \(elapsed)")
    }
}
