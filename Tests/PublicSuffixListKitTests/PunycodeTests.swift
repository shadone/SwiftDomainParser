import Foundation
import Testing
@testable import PublicSuffixListKit

@Suite("Punycode")
struct PunycodeSuite {

    // MARK: - RFC 3492 §7.1 sample strings

    @Test("RFC 3492 §7.1 sample decodes",
          arguments: [
            // (A) Arabic (Egyptian).
            ("egbpdaj6bu4bxfgehfvwxn",
             "\u{0644}\u{064A}\u{0647}\u{0645}\u{0627}\u{0628}\u{062A}\u{0643}\u{0644}\u{0645}\u{0648}\u{0634}\u{0639}\u{0631}\u{0628}\u{064A}\u{061F}"),
            // (B) Chinese (simplified): "他们为什么不说中文"
            ("ihqwcrb4cv8a8dqg056pqjye",
             "\u{4ED6}\u{4EEC}\u{4E3A}\u{4EC0}\u{4E48}\u{4E0D}\u{8BF4}\u{4E2D}\u{6587}"),
            // (C) Chinese (traditional): "他們爲什麽不說中文"
            ("ihqwctvzc91f659drss3x8bo0yb",
             "\u{4ED6}\u{5011}\u{7232}\u{4EC0}\u{9EBD}\u{4E0D}\u{8AAA}\u{4E2D}\u{6587}"),
            // (D) Czech: "Pročprostěnemluvíčesky"
            ("Proprostnemluvesky-uyb24dma41a",
             "\u{0050}\u{0072}\u{006F}\u{010D}\u{0070}\u{0072}\u{006F}\u{0073}\u{0074}\u{011B}\u{006E}\u{0065}\u{006D}\u{006C}\u{0075}\u{0076}\u{00ED}\u{010D}\u{0065}\u{0073}\u{006B}\u{0079}"),
            // (E) Hebrew.
            ("4dbcagdahymbxekheh6e0a7fei0b",
             "\u{05DC}\u{05DE}\u{05D4}\u{05D4}\u{05DD}\u{05E4}\u{05E9}\u{05D5}\u{05D8}\u{05DC}\u{05D0}\u{05DE}\u{05D3}\u{05D1}\u{05E8}\u{05D9}\u{05DD}\u{05E2}\u{05D1}\u{05E8}\u{05D9}\u{05EA}"),
            // (F) Hindi (Devanagari).
            ("i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd",
             "\u{092F}\u{0939}\u{0932}\u{094B}\u{0917}\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}\u{0928}\u{0939}\u{0940}\u{0902}\u{092C}\u{094B}\u{0932}\u{0938}\u{0915}\u{0924}\u{0947}\u{0939}\u{0948}\u{0902}"),
          ] as [(String, String)])
    func decodeRFCVector(encoded: String, expected: String) {
        #expect(Punycode.decode(encoded) == expected)
    }

    // MARK: - PSL IDN labels (from the bundled list)

    @Test("PSL IDN labels decode",
          arguments: [
            ("85x722f",        "\u{98DF}\u{72EE}"),  // 食狮
            ("55qx5d",         "\u{516C}\u{53F8}"),  // 公司
            ("fiqs8s",         "\u{4E2D}\u{56FD}"),  // 中国
          ] as [(String, String)])
    func decodePSLIDNLabel(encoded: String, expected: String) {
        #expect(Punycode.decode(encoded) == expected)
    }

    // MARK: - Malformed input

    @Test func decodeRejectsMalformed() {
        // Non-alphabet bytes anywhere in the variable-length integer fail.
        #expect(Punycode.decode("$$$") == nil)
    }

    @Test func decodeEdgeCases() {
        // Empty input decodes to an empty string (no codepoints to emit).
        #expect(Punycode.decode("") == "")
    }
}
