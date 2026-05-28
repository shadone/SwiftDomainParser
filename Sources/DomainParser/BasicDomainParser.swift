import Foundation

/// Parses a hostname using only the basic (non-wildcard, non-exception) suffix rules.
/// Examples of valid rules: **com**, **co.uk**, **ide.kyoto.jp**.
public struct BasicDomainParser: DomainParserProtocol {

    let suffixes: Set<String>

    init(suffixes: Set<String>) {
        self.suffixes = suffixes
    }

    /// Loads the bundled Public Suffix List and keeps only the basic-rule
    /// suffix set. Use this when you don't need wildcard/exception matching:
    /// the lookup runs as one `Set<String>.contains` per host label.
    public init() throws(DomainParserError) {
        let parsed = try RulesParser.parse(raw: _loadBundledPSLData(), sortRules: false)
        self.init(suffixes: parsed.basicRules)
    }

    public func parse(host: String) -> ParsedHost? {
        return parse(labels: HostLabels(host: host))
    }

    func parse(labels: HostLabels) -> ParsedHost? {
        guard !labels.isEmpty else { return nil }

        // Match against the normalized (Punycode-decoded) labels, but build
        // the output by slicing the original labels at the same indices so
        // ACE callers get ACE back and Unicode callers get Unicode back.
        for suffixStart in 0..<labels.normalized.count {
            let candidate = labels.normalized[suffixStart...].joined(separator: ".")
            guard suffixes.contains(candidate) else { continue }

            let publicSuffix = labels.original[suffixStart...].joined(separator: ".")
            let registrableDomain = suffixStart > 0
                ? labels.original[(suffixStart - 1)...].joined(separator: ".")
                : nil
            return ParsedHost(publicSuffix: publicSuffix,
                              registrableDomain: registrableDomain)
        }
        return nil
    }
}
