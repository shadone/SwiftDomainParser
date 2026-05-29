import Foundation

/// UTS-46 processing. The lookup path uses the lenient `canonicalLabel` for
/// normalization and comparison; the strict `toASCII` / `toUnicode` entry points
/// (added for conformance) report errors.
///
/// Profile: nontransitional processing, `UseSTD3ASCIIRules = true`. Bidi
/// (RFC 5893) and ContextJ/ContextO joiner checks are intentionally not
/// implemented — they validate registerability, not which registrable domain a
/// host belongs to. See <doc:IDNHandling>.
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
}
