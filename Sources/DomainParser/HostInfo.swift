/// The decomposition of a host against the Public Suffix List.
public struct HostInfo: Sendable, Equatable, Hashable {
    /// Public suffix, e.g. "co.uk", "github.io". Always present.
    public let publicSuffix: String
    /// Registrable domain (eTLD+1), e.g. "example.co.uk".
    /// nil when the host IS a public suffix (e.g. "co.uk").
    public let registrableDomain: String?
    /// Everything left of the registrable domain, e.g. "app" in
    /// "app.alice.github.io". nil when there is none.
    public let subdomain: String?
    /// Which part of the list decided this match.
    public let source: MatchSource

    public init(publicSuffix: String, registrableDomain: String?,
                subdomain: String?, source: MatchSource) {
        self.publicSuffix = publicSuffix
        self.registrableDomain = registrableDomain
        self.subdomain = subdomain
        self.source = source
    }

    /// The host is itself a bare public suffix (e.g. "co.uk").
    public var isPublicSuffix: Bool { registrableDomain == nil }

    /// The host IS exactly the registrable domain (eTLD+1) with no subdomain.
    public var isRegistrableDomain: Bool {
        subdomain == nil && registrableDomain != nil
    }
}

/// Which class of PSL rule produced a match.
public enum MatchSource: Sendable, Equatable {
    /// Matched an ICANN-section rule.
    case icann
    /// Matched a PRIVATE-section rule (per-tenant isolation).
    case privateRule
    /// No rule matched; the implicit "*" rule was applied — a guess.
    case defaultRule
}
