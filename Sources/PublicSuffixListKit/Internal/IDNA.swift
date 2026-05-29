import Foundation

/// UTS-46 processing. The lookup path uses the lenient `canonicalLabel` for
/// normalization and comparison; the strict `toASCII` / `toUnicode` entry points
/// (added for conformance) report errors.
///
/// Profile: nontransitional processing, `UseSTD3ASCIIRules = false` — the
/// WHATWG URL / browser default, and the disposition the bundled mapping table
/// encodes. Bidi (RFC 5893) and ContextJ/ContextO joiner checks are
/// intentionally not implemented — they validate registerability, not which
/// registrable domain a host belongs to. See <doc:IDNHandling>.
enum IDNA {
    /// Lenient per-label canonicalization for lookup and comparison: apply the
    /// UTS-46 mapping (nontransitional, UseSTD3) — which also case-folds —
    /// Punycode-decode an `xn--` label, then NFC-normalize. Best-effort:
    /// disallowed code points are kept rather than rejected, so lookup never
    /// fails on exotic input.
    static func canonicalLabel(_ label: String) -> String {
        let mapped = mapForLookup(label)
        let unicode: String
        if mapped.hasPrefix("xn--"),
           let decoded = Punycode.decode(String(mapped.dropFirst(4))) {
            unicode = mapForLookup(decoded)
        } else {
            unicode = mapped
        }
        return unicode.precomposedStringWithCanonicalMapping
    }

    /// Apply the UTS-46 mapping step for the lookup profile, keeping disallowed
    /// code points as-is. Falls back to `lowercased()` if the bundled table is
    /// unavailable.
    static func mapForLookup(_ s: String) -> String {
        guard let table = IDNAMapping.bundled else { return s.lowercased() }
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            let (status, mapping) = table.status(of: scalar)
            switch status {
            case .ignored:
                continue
            case .mapped, .disallowedSTD3Mapped:
                out.append(contentsOf: mapping)
            case .valid, .deviation, .disallowed, .disallowedSTD3Valid:
                // Nontransitional treats deviation as valid; lenient mode keeps
                // disallowed / STD3-disallowed code points instead of failing.
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// ACE (A-label) form of an already-canonical (UTS-46 U-label, NFC) host:
    /// each non-ASCII label becomes `xn--` + Punycode. nil for nil input or on
    /// encode overflow.
    static func aceFromCanonical(_ host: String?) -> String? {
        guard let host else { return nil }
        var labels: [String] = []
        for label in host.split(separator: ".", omittingEmptySubsequences: false) {
            if label.allSatisfy(\.isASCII) {
                labels.append(String(label))
            } else {
                guard let encoded = Punycode.encode(String(label)) else { return nil }
                labels.append("xn--" + encoded)
            }
        }
        return labels.joined(separator: ".")
    }

    // MARK: - Strict UTS-46 (conformance)

    /// Result of UTS-46 Processing: the U-labels and whether any error was
    /// recorded. Errors covered: disallowed / STD3 (P1/U1), invalid code point
    /// (V6), NFC (V1), hyphen rules (V2/V3), leading combining mark (V5), and
    /// Punycode decode failure. Bidi (Bn) and ContextJ/O (Cn) are not checked.
    struct Processed {
        var labels: [String]
        var error: Bool
    }

    static func process(_ domain: String, transitional: Bool,
                        useSTD3: Bool = false, checkHyphens: Bool = true) -> Processed {
        guard let table = IDNAMapping.bundled else { return Processed(labels: [domain], error: true) }

        var mapped = String.UnicodeScalarView()
        var error = false
        for scalar in domain.unicodeScalars {
            let (status, mapping) = table.status(of: scalar)
            switch status {
            case .valid: mapped.append(scalar)
            case .ignored: break
            case .mapped: mapped.append(contentsOf: mapping)
            case .deviation:
                if transitional { mapped.append(contentsOf: mapping) } else { mapped.append(scalar) }
            case .disallowed:
                error = true; mapped.append(scalar)
            case .disallowedSTD3Valid:
                if useSTD3 { error = true }; mapped.append(scalar)
            case .disallowedSTD3Mapped:
                if useSTD3 { error = true; mapped.append(scalar) } else { mapped.append(contentsOf: mapping) }
            }
        }

        let normalized = String(mapped).precomposedStringWithCanonicalMapping
        var labels: [String] = []
        for labelSub in normalized.split(separator: ".", omittingEmptySubsequences: false) {
            var label = String(labelSub)
            if label.hasPrefix("xn--") {
                guard let decoded = Punycode.decode(String(label.dropFirst(4))) else {
                    error = true; labels.append(label); continue
                }
                label = decoded
                if !isValidLabel(label, table: table, transitional: false,
                                 checkHyphens: checkHyphens) { error = true }
            } else if !isValidLabel(label, table: table, transitional: transitional,
                                    checkHyphens: checkHyphens) {
                error = true
            }
            labels.append(label)
        }
        return Processed(labels: labels, error: error)
    }

    /// UTS-46 validity criteria (4.1), minus Bidi (V8) and ContextJ.
    private static func isValidLabel(_ label: String, table: IDNAMapping,
                                     transitional: Bool, checkHyphens: Bool) -> Bool {
        if label.isEmpty { return true }                 // empty (root) label
        if label.precomposedStringWithCanonicalMapping != label { return false }   // V1: NFC

        let scalars = Array(label.unicodeScalars)
        if checkHyphens {
            if scalars.count >= 4, scalars[2] == "-", scalars[3] == "-" { return false }  // V2
            if scalars.first == "-" || scalars.last == "-" { return false }               // V3
        }
        if let first = scalars.first, isMark(first) { return false }                       // V5

        for scalar in scalars {                                                            // V6
            switch table.status(of: scalar).status {
            case .valid: continue
            case .deviation: if transitional { return false }
            default: return false
            }
        }
        return true
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// UTS-46 ToUnicode (nontransitional). Returns the U-label form and whether
    /// any error was recorded.
    static func toUnicode(_ domain: String) -> (result: String, error: Bool) {
        let processed = process(domain, transitional: false)
        return (processed.labels.joined(separator: "."), processed.error)
    }

    /// UTS-46 ToASCII (nontransitional). Returns the A-label form and whether any
    /// error was recorded (processing errors plus DNS-length when requested).
    static func toASCII(_ domain: String, verifyDnsLength: Bool = true) -> (result: String, error: Bool) {
        let processed = process(domain, transitional: false)
        var error = processed.error

        var aceLabels: [String] = []
        for label in processed.labels {
            if label.allSatisfy(\.isASCII) {
                aceLabels.append(label)
            } else if let encoded = Punycode.encode(label) {
                aceLabels.append("xn--" + encoded)
            } else {
                error = true; aceLabels.append(label)
            }
        }

        let result = aceLabels.joined(separator: ".")
        if verifyDnsLength {
            for (i, label) in aceLabels.enumerated() {
                let isRootDot = i == aceLabels.count - 1 && label.isEmpty && aceLabels.count > 1
                if !isRootDot && (label.utf8.count < 1 || label.utf8.count > 63) { error = true }
            }
            // Total length excludes a single trailing root dot.
            var total = result.utf8.count
            if result.hasSuffix(".") { total -= 1 }
            if total < 1 || total > 253 { error = true }
        }
        return (result, error)
    }
}
