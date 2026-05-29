import Foundation

enum PSLRuleLabel: Sendable {
    case text(String)
    /// The wildcard character * (asterisk) matches any valid sequence of characters in a hostname part.
    /// Wildcards are not restricted to appear only in the leftmost position, but they must wildcard an entire label. (I.e. *.*.foo is a valid rule: *bar.foo is not.)
    case wildcard

    init(fromComponent component: Substring) {
        self = component == PSLSyntax.wildcardComponent ? .wildcard : .text(String(component))
    }

    /// Return true if self matches the given label
    func isMatching(label: some StringProtocol) -> Bool {
        switch self {
        case let .text(text):
            return text == label
        case .wildcard:
            return true
        }
    }
}
