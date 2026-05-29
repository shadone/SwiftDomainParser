public import Foundation

/// The capability implemented by `PublicSuffixList`. Conformers are `Sendable`
/// so a single instance can be shared across isolation domains. Construction
/// is the expensive step; per-call lookup is cheap.
///
/// Only `lookup(_:scope:)` is a requirement — every other entry point below is
/// a default implementation, so a test double need only implement `lookup`.
public protocol PublicSuffixMatching: Sendable {
    /// Returns the decomposition of `host`, or nil for non-hostnames.
    func lookup(_ host: String, scope: MatchScope) -> HostInfo?
}

extension PublicSuffixList: PublicSuffixMatching {}

extension PublicSuffixMatching {
    /// Look up a URL's host component. Returns nil if the URL has no host.
    public func lookup(_ url: URL, scope: MatchScope = .all) -> HostInfo? {
        guard let host = url.host() else { return nil }
        return lookup(host, scope: scope)
    }

    public func registrableDomain(of host: String, scope: MatchScope = .all) -> String? {
        lookup(host, scope: scope)?.registrableDomain
    }

    public func publicSuffix(of host: String, scope: MatchScope = .all) -> String? {
        lookup(host, scope: scope)?.publicSuffix
    }

    public func isPublicSuffix(_ host: String, scope: MatchScope = .all) -> Bool {
        lookup(host, scope: scope)?.isPublicSuffix ?? false
    }

    /// Do two hosts resolve to the same registrable domain? false if either is
    /// a bare suffix or unparseable. PRIVATE rules included by default, so
    /// alice.github.io and bob.github.io are NOT equal.
    ///
    /// Scheme-agnostic registrable-domain equality — not the web platform's
    /// schemeful "same-site" (RFC 6265bis). Compares the canonical registrable
    /// domain, so A-label/U-label forms and trailing dots are equated:
    /// `食狮.公司.cn` ≡ `xn--85x722f.xn--55qx5d.cn`, `example.com` ≡ `example.com.`.
    public func haveSameRegistrableDomain(_ a: String, _ b: String,
                                          scope: MatchScope = .all) -> Bool {
        func key(_ host: String) -> String? {
            lookup(host, scope: scope)?.canonicalRegistrableDomain
        }
        guard let ka = key(a), let kb = key(b) else { return false }
        return ka == kb
    }
}
