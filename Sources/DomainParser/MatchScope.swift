/// Which sections of the Public Suffix List a query consults.
public enum MatchScope: Sendable {
    /// ICANN + PRIVATE rules. The default — correct for credential matching,
    /// where alice.github.io and bob.github.io must be different sites.
    case all
    /// ICANN rules only; PRIVATE rules are ignored.
    case icannOnly
}
