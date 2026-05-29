import Foundation
import Testing
@testable import PublicSuffixListKit

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
        let raw = "// comment\ncom\nco.uk  trailing ignored\n"
        let parsed = try RulesParser.parse(Data(raw.utf8))
        #expect(parsed.metadata.icannRuleCount == 2)
        #expect(parsed.metadata.sourceDate == nil)
    }
}
