package import Foundation

package struct ParsedList: Sendable {
    /// Flat rules left-to-right, in priority-hint order. Retained so the
    /// codegen tool can serialize them; the bundled list drops this array after
    /// `PublicSuffixList` reads `index`/`metadata` out of it.
    package let rules: [Rule]
    package let index: RuleIndex
    package let metadata: ListMetadata

    package init(rules: [Rule], index: RuleIndex, metadata: ListMetadata) {
        self.rules = rules
        self.index = index
        self.metadata = metadata
    }
}

package enum RulesParser {
    package static func parse(_ data: Data) throws(PublicSuffixListError) -> ParsedList {
        guard let text = String(data: data, encoding: .utf8) else {
            throw .ruleParsingError(message: "List bytes are not valid UTF-8.")
        }

        var sourceDate: String?
        var sourceRevision: String?
        var section: Section = .icann   // default before any marker
        var rules: [Rule] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: \.isWhitespace)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let header = line.dropFirst().drop(while: { $0 == " " })
                if header.hasPrefix("===ICANN===") { section = .icann }
                else if header.hasPrefix("===PRIVATE===") { section = .privateSection }
                else if let v = value(of: "source-date:", in: header) { sourceDate = v }
                else if let v = value(of: "source-revision:", in: header) { sourceRevision = v }
                continue
            }
            if line.hasPrefix("//") { continue } // raw upstream comment

            // Each rule line is read up to the first whitespace.
            let token = line.prefix { !$0.isWhitespace }
            guard !token.isEmpty else { continue }
            rules.append(Rule(source: token, section: section))
        }

        let index = RuleIndex(rules: rules)
        let metadata = ListMetadata(
            sourceDate: sourceDate, sourceRevision: sourceRevision,
            icannRuleCount: index.icannRuleCount,
            privateRuleCount: index.privateRuleCount)
        return ParsedList(rules: rules, index: index, metadata: metadata)
    }

    private static func value(of key: String, in header: Substring) -> String? {
        guard header.hasPrefix(key) else { return nil }
        let v = header.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
