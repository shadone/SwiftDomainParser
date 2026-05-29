import Foundation

/// Canonical comparison form for a host string.
///
/// Produces a single normalized U-label representation so that the same domain
/// expressed as an A-label (`xn--`), a U-label (Unicode), or any mix compares
/// equal: each label is Punycode-decoded if it is an `xn--` label, then NFC-
/// normalized and lowercased. A trailing FQDN dot is dropped.
///
/// Normalization is full UTS-46 (mapped/ignored/deviation/disallowed handling +
/// NFC), delegated to ``IDNA/canonicalLabel(_:)``.
enum IDNCanonical {
    /// Canonical form of a whole host, or nil for empty input.
    static func host(_ host: String?) -> String? {
        guard var s = host, !s.isEmpty else { return nil }
        if s.hasSuffix(".") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        return s
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { IDNA.canonicalLabel(String($0)) }
            .joined(separator: ".")
    }
}
