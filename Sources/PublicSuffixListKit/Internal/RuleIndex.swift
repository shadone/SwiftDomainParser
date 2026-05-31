/// The outcome of resolving the prevailing rule for a host.
struct ResolvedRule: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case explicit, defaultStar }
    let kind: Kind
    let labelCount: Int      // labels the prevailing rule constrains
    let isException: Bool
    let isWildcard: Bool
    let source: MatchSource  // .icann / .privateRule / .defaultRule

    static let defaultStar = ResolvedRule(
        kind: .defaultStar, labelCount: 1, isException: false,
        isWildcard: true, source: .defaultRule)
}

/// All rules indexed by their rightmost (literal) label. Querying fetches the
/// small bucket for the host's rightmost label and resolves among it.
package struct RuleIndex: Sendable {
    private let rulesByLastLabel: [String: [Rule]]

    package init(rules: [Rule]) {
        var byLast: [String: [Rule]] = [:]
        for rule in rules where !rule.lastLabel.isEmpty {
            byLast[rule.lastLabel, default: []].append(rule)
        }
        self.rulesByLastLabel = byLast
    }

    /// Buckets keyed by rightmost label, for cross-checking two indexes are
    /// structurally identical (the `.dat`-vs-`.bin` staleness guard).
    package var buckets: [String: [Rule]] { rulesByLastLabel }

    var icannRuleCount: Int {
        rulesByLastLabel.values.reduce(0) { $0 + $1.filter { $0.section == .icann }.count }
    }
    var privateRuleCount: Int {
        rulesByLastLabel.values.reduce(0) { $0 + $1.filter { $0.section == .privateSection }.count }
    }

    /// Resolve the prevailing rule for `hostLabels` (normalized, left-to-right).
    func prevailingRule(for hostLabels: [String], scope: MatchScope) -> ResolvedRule {
        guard let last = hostLabels.last,
              let bucket = rulesByLastLabel[last] else {
            return .defaultStar
        }

        var best: Rule?
        for rule in bucket {
            if scope == .icannOnly, rule.section == .privateSection { continue }
            guard rule.matches(hostLabels) else { continue }
            if isHigherPriority(rule, than: best) { best = rule }
        }

        guard let winner = best else { return .defaultStar }
        return ResolvedRule(
            kind: .explicit,
            labelCount: winner.labelCount,
            isException: winner.isException,
            isWildcard: winner.isWildcard,
            source: winner.section == .icann ? .icann : .privateRule)
    }

    /// PSL priority: an exception beats any non-exception; otherwise more
    /// labels wins. (Two exceptions or two non-exceptions tie on label count;
    /// real PSL data has no such ambiguous pair, so either order is fine.)
    private func isHigherPriority(_ candidate: Rule, than current: Rule?) -> Bool {
        guard let current else { return true }
        if candidate.isException != current.isException {
            return candidate.isException
        }
        return candidate.labelCount > current.labelCount
    }
}
