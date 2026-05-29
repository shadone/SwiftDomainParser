import Foundation

/// Canonical comparison form for a host string.
///
/// Produces a single normalized U-label representation so that the same domain
/// expressed as an A-label (`xn--`), a U-label (Unicode), or any mix compares
/// equal: each label is Punycode-decoded if it is an `xn--` label, then NFC-
/// normalized and lowercased. A trailing FQDN dot is dropped.
///
/// This is the P0 normalization (lowercase + NFC + Punycode). Full UTS-46
/// mapping (deviation/mapped/disallowed code points) replaces `lowercased()`
/// here in a later phase; the call sites do not change.
enum IDNCanonical {
    /// Canonical form of a whole host, or nil for empty input.
    static func host(_ host: String?) -> String? {
        guard var s = host, !s.isEmpty else { return nil }
        if s.hasSuffix(".") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        return s
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { label(String($0)) }
            .joined(separator: ".")
    }

    /// Canonical form of a single label.
    static func label(_ label: String) -> String {
        let lowered = label.lowercased()
        let unicode: String
        if lowered.hasPrefix("xn--"),
           let decoded = Punycode.decode(String(lowered.dropFirst(4))) {
            unicode = decoded.lowercased()
        } else {
            unicode = lowered
        }
        return unicode.precomposedStringWithCanonicalMapping
    }
}
