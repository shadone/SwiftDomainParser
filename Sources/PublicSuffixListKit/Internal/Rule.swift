/// Which division of the PSL a rule belongs to.
package enum Section: Sendable, Equatable { case icann, privateSection }

/// One label of a rule.
package enum RuleLabel: Sendable, Equatable {
    case literal(String)
    case wildcard          // a bare "*"; per the format, only ever leftmost
}

/// A single Public Suffix List rule, parsed from one line of the list.
package struct Rule: Sendable, Equatable {
    /// Labels left-to-right, e.g. ["*", "ck"] or ["co", "uk"]. The leading "!"
    /// of an exception is stripped here and recorded in `isException`.
    package let labels: [RuleLabel]
    package let isException: Bool
    package let section: Section

    /// Rightmost label as a string — always literal in real PSL data.
    /// Used as the index key.
    package let lastLabel: String

    /// Construct directly from already-parsed labels. Used when rebuilding rules
    /// from the precompiled binary blob (`PSLBinaryFormat.decode`), bypassing
    /// the text tokenizer.
    package init(labels: [RuleLabel], isException: Bool, section: Section) {
        self.labels = labels
        self.isException = isException
        self.section = section
        if case .literal(let s)? = labels.last { self.lastLabel = s }
        else { self.lastLabel = "" }
    }

    init(source: Substring, section: Section) {
        let isException = source.first == "!"
        let body = isException ? source.dropFirst() : source
        let parts = body.split(separator: ".").map { part -> RuleLabel in
            part == "*" ? .wildcard : .literal(String(part))
        }
        self.labels = parts
        self.isException = isException
        self.section = section
        if case .literal(let s)? = parts.last { self.lastLabel = s }
        else { self.lastLabel = "" } // a rule ending in "*" is invalid input
    }

    init(source: String, section: Section) {
        self.init(source: Substring(source), section: section)
    }

    /// Number of labels the rule constrains (bang already excluded).
    package var labelCount: Int { labels.count }

    var isWildcard: Bool { labels.contains(.wildcard) }

    /// True if this rule matches a host given as normalized labels
    /// (left-to-right). PSL rule: the host must have at least as many labels
    /// as the rule, and, comparing from the right, each rule label is identical
    /// to the host label or is the wildcard.
    func matches(_ hostLabels: [String]) -> Bool {
        guard hostLabels.count >= labels.count else { return false }
        for offset in 1...labels.count {
            let ruleLabel = labels[labels.count - offset]
            let hostLabel = hostLabels[hostLabels.count - offset]
            switch ruleLabel {
            case .wildcard: continue
            case .literal(let s): if s != hostLabel { return false }
            }
        }
        return true
    }
}
