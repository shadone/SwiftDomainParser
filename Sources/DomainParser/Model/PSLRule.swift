import Foundation

/// Represents a Public Suffix Rule
struct PSLRule: Sendable {

    /// Is this rule an exception
    let exception: Bool

    /// The raw rule in the PSL format
    let source: String

    /// Labels separated rules
    let parts: [PSLRuleLabel]

    /// Score used to sort the rules. If a URL match multiple rules, the one with the highest Score is prevailing
    let rankingScore: Int

    init(raw: Substring) {

        /// If the line starts with "!" it's an exceptional Rule
        exception = raw.starts(with: PSLSyntax.exceptionMarker)
        source = exception ? String(raw.dropFirst()) : String(raw)
        parts = source.split(separator: ".").map(PSLRuleLabel.init)

        /// Exceptions should have a higher Rank than regular rules
        rankingScore = (exception ? 1000 : 0) + parts.count
    }
}

extension PSLRule {

    /// From https://publicsuffix.org/list/
    /// A domain is said to match a rule if and only if all of the following conditions are met:
    /// - When the domain and rule are split into corresponding labels,
    ///     that the domain contains as many or more labels than the rule.
    /// - Beginning with the right-most labels of both the domain and the rule,
    ///     and continuing for all labels in the rule, one finds that for every pair,
    ///     either they are identical, or that the label from the rule is "*".
    ///
    /// Matching is done against the *normalized* (Punycode-decoded) labels so
    /// it works against the bundled PSL's Unicode-form rules regardless of
    /// whether the caller passed an ACE or Unicode host.
    func isMatching(hostLabels: HostLabels) -> Bool {
        let labels = hostLabels.normalized
        let delta = labels.count - self.parts.count
        guard delta >= 0 else { return false }
        let trimmed = labels.dropFirst(delta)
        return zip(self.parts, trimmed)
            .allSatisfy { ruleComponent, hostComponent in
                ruleComponent.isMatching(label: hostComponent)
            }
    }

    /// ⚠️ Should be called only for host matching the rule.
    ///
    /// Output is constructed from the *original* labels so the caller gets
    /// the suffix and registrable domain back in the same ACE/Unicode form
    /// they passed in.
    func parse(hostLabels: HostLabels) -> ParsedHost {
        let labels = hostLabels.original
        let partsCount = parts.count - (self.exception ? 1 : 0)
        let delta = labels.count - partsCount

        let registrableDomain = delta == 0
            ? nil
            : labels.dropFirst(delta - 1).joined(separator: ".")
        let publicSuffix = labels.dropFirst(delta).joined(separator: ".")
        return ParsedHost(publicSuffix: publicSuffix,
                          registrableDomain: registrableDomain)
    }
}

