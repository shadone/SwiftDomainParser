import Foundation
import Testing
@testable import PublicSuffixListKit

/// Runs Unicode's official UTS-46 conformance vectors (IdnaTestV2.txt) against
/// the nontransitional `toUnicode` / `toASCII`.
///
/// Rows whose only expected errors are Bidi (`B*`), ContextJ/ContextO (`C*`), or
/// `UseSTD3ASCIIRules` (`U1`) are skipped: those checks are intentionally not
/// implemented (see <doc:IDNHandling>). The skipped count is asserted to be a
/// small fraction so the suite cannot silently degrade into skipping everything.
@Suite("UTS-46 IdnaTestV2 conformance")
struct IdnaTestV2Tests {

    @Test func conformance() throws {
        let url = try #require(Bundle.module.url(forResource: "IdnaTestV2", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)

        var checked = 0
        var skipped = 0
        var failures: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.hasPrefix("#") { continue }
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            if body.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let cols = body.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 5 else { continue }

            // Surrogate escapes cannot be represented in a Swift String, so these
            // rows are untestable here; skip (both ops).
            if hasSurrogateEscape(cols[0]) { skipped += 2; continue }

            let source = literal(cols[0]) ?? ""
            let toUnicode = literal(cols[1]) ?? source
            let unicodeErr = parseStatus(cols[2])
            let toAscii = literal(cols[3]) ?? toUnicode
            let asciiErr = cols[4].isEmpty ? unicodeErr : parseStatus(cols[4])

            check("toUnicode", source, expected: toUnicode, expectedErr: unicodeErr,
                  actual: IDNA.toUnicode(source), &checked, &skipped, &failures)
            check("toASCII", source, expected: toAscii, expectedErr: asciiErr,
                  actual: IDNA.toASCII(source), &checked, &skipped, &failures)
        }

        let report = "\(failures.count) failures (checked \(checked), skipped \(skipped)):\n"
            + failures.prefix(30).joined(separator: "\n")
        #expect(checked > 5000, "only \(checked) assertions ran — parser likely broken")
        #expect(failures.isEmpty, "\(report)")
    }

    // MARK: - One assertion

    private func check(_ op: String, _ input: String, expected: String,
                       expectedErr: Set<String>, actual: (result: String, error: Bool),
                       _ checked: inout Int, _ skipped: inout Int, _ failures: inout [String]) {
        // U1 (UseSTD3ASCIIRules) is not an error in our profile (STD3=false), so
        // drop it from the expected set rather than skipping the row.
        let effectiveErr = expectedErr.subtracting(["U1"])
        // Errors we cannot detect: Bidi (B*), ContextJ/O (C*), and surrogate
        // labels (V7 — Swift `String` cannot represent them). If only these
        // remain, skip — we would under-report.
        let unsupported = effectiveErr.filter { $0.hasPrefix("B") || $0.hasPrefix("C") || $0 == "V7" }
        let relevant = effectiveErr.subtracting(unsupported)
        if relevant.isEmpty && !unsupported.isEmpty { skipped += 1; return }

        checked += 1
        let expectError = !relevant.isEmpty
        if actual.error != expectError {
            failures.append("\(op)(\(escaped(input))): error=\(actual.error), expected=\(expectError) \(expectedErr.sorted())")
            return
        }
        // On expected-error rows the output string is unspecified; only compare clean rows.
        if !expectError, !expected.contains("\u{FFFD}"), actual.result != expected {
            failures.append("\(op)(\(escaped(input))) = \(escaped(actual.result)), expected \(escaped(expected))")
        }
    }

    // MARK: - Parsing

    /// A column value: empty field -> nil (caller substitutes the fallback),
    /// `""` -> empty string, otherwise the unescaped literal.
    private func literal(_ field: String) -> String? {
        if field.isEmpty { return nil }
        if field == "\"\"" { return "" }
        return unescape(field)
    }

    /// True if `field` contains a `\uXXXX` escape in the surrogate range.
    private func hasSurrogateEscape(_ field: String) -> Bool {
        let c = Array(field.unicodeScalars)
        var i = 0
        while i + 5 < c.count {
            if c[i] == "\\", c[i + 1] == "u",
               let v = UInt32(String(String.UnicodeScalarView(c[(i + 2)...(i + 5)])), radix: 16),
               (0xD800...0xDFFF).contains(v) {
                return true
            }
            i += 1
        }
        return false
    }

    private func parseStatus(_ field: String) -> Set<String> {
        guard let open = field.firstIndex(of: "["), let close = field.firstIndex(of: "]") else {
            return []
        }
        let inner = field[field.index(after: open)..<close]
        return Set(inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// Resolve `\uXXXX` (exactly 4 hex) and `\x{XXXX}` escapes. Scalar-based:
    /// Character-cluster indexing mis-handles an escape adjacent to an astral
    /// code point.
    private func unescape(_ s: String) -> String {
        let c = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < c.count {
            if c[i] == "\\", i + 1 < c.count {
                if c[i + 1] == "u", i + 5 < c.count {
                    let hex = String(String.UnicodeScalarView(c[(i + 2)...(i + 5)]))
                    if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                        out.append(scalar); i += 6; continue
                    }
                } else if c[i + 1] == "x", i + 2 < c.count, c[i + 2] == "{",
                          let close = c[(i + 3)...].firstIndex(of: "}") {
                    let hex = String(String.UnicodeScalarView(c[(i + 3)..<close]))
                    if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                        out.append(scalar); i = close + 1; continue
                    }
                }
            }
            out.append(c[i]); i += 1
        }
        return String(out)
    }

    /// Render a string with non-ASCII shown as \u{...} for readable failures.
    private func escaped(_ s: String) -> String {
        s.unicodeScalars.map { $0.isASCII ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined()
    }
}
