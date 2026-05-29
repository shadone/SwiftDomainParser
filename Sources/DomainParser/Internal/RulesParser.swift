import Foundation

struct ParsedList: Sendable {
    let index: RuleIndex
    let metadata: ListMetadata
}

enum RulesParser {
    static func parse(_ data: Data) throws(PublicSuffixListError) -> ParsedList {
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
        return ParsedList(index: index, metadata: metadata)
    }

    private static func value(of key: String, in header: Substring) -> String? {
        guard header.hasPrefix(key) else { return nil }
        let v = header.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
