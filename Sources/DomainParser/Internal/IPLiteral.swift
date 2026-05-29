import Foundation

/// Detects IP-address literals so they can be rejected as non-hostnames.
/// A host is a literal if it parses as IPv4 (exactly four 0–255 octets) or as
/// IPv6 (optionally wrapped in `[...]`, the form a URL host component yields).
enum IPLiteral {
    static func isIPLiteral(_ host: String) -> Bool {
        var s = Substring(host)
        if s.first == "[", s.last == "]" {
            s = s.dropFirst().dropLast()
            return isIPv6(String(s))
        }
        return isIPv4(host) || isIPv6(host)
    }

    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            part.count >= 1 && part.count <= 3
                && part.allSatisfy(\.isNumber)
                && (UInt8(part) != nil)
        }
    }

    private static func isIPv6(_ s: String) -> Bool {
        // An IPv6 literal must contain a colon and parse via in6_addr.
        guard s.contains(":") else { return false }
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
    }
}
