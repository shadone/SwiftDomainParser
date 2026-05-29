import Testing
@testable import PublicSuffixListKit

@Suite("UTS-46 mapping")
struct IDNAMappingTests {
    @Test func bundledTableLoads() throws {
        let table = try #require(IDNAMapping.bundled)
        #expect(!table.version.isEmpty)
        #expect(table.entries.count > 1000)
    }

    @Test func casefoldsAscii() {
        #expect(IDNA.canonicalLabel("ExAmPle") == "example")
    }

    @Test func fullwidthMapsToAscii() {
        // FULLWIDTH LATIN A/B/C -> a/b/c
        #expect(IDNA.canonicalLabel("\u{FF21}\u{FF22}\u{FF23}") == "abc")
    }

    @Test func ignoredCodePointDropped() {
        // SOFT HYPHEN (U+00AD) is ignored
        #expect(IDNA.canonicalLabel("ab\u{00AD}c") == "abc")
    }

    @Test func deviationKeptUnderNontransitional() {
        // ß (deviation) stays ß, NOT mapped to "ss"
        #expect(IDNA.canonicalLabel("stra\u{00DF}e") == "stra\u{00DF}e")
        // final sigma ς (deviation) kept
        #expect(IDNA.canonicalLabel("\u{03C2}") == "\u{03C2}")
    }

    @Test func mappedSymbolBecomesCanonical() {
        // OHM SIGN (U+2126) -> GREEK SMALL LETTER OMEGA (U+03C9)
        #expect(IDNA.canonicalLabel("\u{2126}") == "\u{03C9}")
    }

    @Test func uppercaseAceDecodes() {
        #expect(IDNA.canonicalLabel("XN--85X722F") == "食狮")
    }

    @Test func nfcNormalizes() {
        // "e" + COMBINING ACUTE ACCENT (NFD) -> precomposed "é" (NFC)
        #expect(IDNA.canonicalLabel("cafe\u{0301}") == "caf\u{00E9}")
    }
}
