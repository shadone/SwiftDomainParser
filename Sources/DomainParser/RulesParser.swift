import Foundation

struct ParsedRules: Sendable {
    /// Dictionary of rule arrays indexed by the last label of a rule.
    let exceptions: [String: [Rule]]
    /// Dictionary of rule arrays indexed by the last label of a rule.
    let wildcardRules: [String: [Rule]]
    /// Set of suffixes
    let basicRules: Set<String>
}

enum RulesParser {

    /// Parse the Data to extract the rule collections, optionally sorted by importance.
    static func parse(raw: Data, sortRules: Bool) throws(DomainParserError) -> ParsedRules {
        guard let rulesText = String(data: raw, encoding: .utf8) else {
            throw DomainParserError.ruleParsingError(message: "Can't parse rules data. Is it in UTF-8 format?")
        }

        var exceptions: [String: [Rule]] = [:]
        var wildcardRules: [String: [Rule]] = [:]
        var basicRules: Set<String> = []

        for line in rulesText.split(separator: "\n") {
            try parse(line: line,
                      into: &exceptions,
                      wildcardRules: &wildcardRules,
                      basicRules: &basicRules)
        }

        if sortRules {
            // Sort the collections from big to small so that the highest-priority rules are first.
            let byScoreDescending: (Rule, Rule) -> Bool = { $0.rankingScore > $1.rankingScore }
            wildcardRules = wildcardRules.mapValues { $0.sorted(by: byScoreDescending) }
            exceptions = exceptions.mapValues { $0.sorted(by: byScoreDescending) }
        }

        return ParsedRules(exceptions: exceptions,
                           wildcardRules: wildcardRules,
                           basicRules: basicRules)
    }

    private static func parse(line rawLine: Substring,
                              into exceptions: inout [String: [Rule]],
                              wildcardRules: inout [String: [Rule]],
                              basicRules: inout Set<String>) throws(DomainParserError) {
        // From publicsuffix.org/list/: each line is only read up to the
        // first whitespace; entire lines can also be commented using "//".
        // The bundled .dat file is pre-normalized by script/UpdatePSL.swift,
        // but accept raw upstream input here too so init(_rulesData:) and
        // any future direct caller can pass it unmodified.
        let line = rawLine.prefix { !$0.isWhitespace }
        guard !line.isEmpty, !line.hasPrefix("//") else { return }

        if line.contains("*") {
            let rule = Rule(raw: line)
            guard case .text(let lastLabelText) = rule.parts.last else {
                throw DomainParserError.ruleParsingError(
                    message: "Last label of PSL rule must be text (Rule: \(line))")
            }
            wildcardRules[lastLabelText, default: []].append(rule)
        } else if line.starts(with: "!") {
            let rule = Rule(raw: line)
            guard case .text(let lastLabelText) = rule.parts.last else {
                throw DomainParserError.ruleParsingError(
                    message: "Last label of PSL rule must be text (Rule: \(line))")
            }
            exceptions[lastLabelText, default: []].append(rule)
        } else {
            basicRules.insert(String(line))
        }
    }
}
