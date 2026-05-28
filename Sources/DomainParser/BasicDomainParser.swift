import Foundation

/// Parses a hostname using only the basic (non-wildcard, non-exception) suffix rules.
/// Examples of valid rules: **com**, **co.uk**, **ide.kyoto.jp**.
public struct BasicDomainParser: DomainParserProtocol {

    /// PSL basic-rule set stored as `Substring` views. Each Substring keeps
    /// its base `String` (the original rule from `RulesParser`) alive via
    /// ARC, so no extra backing buffer is needed.
    ///
    /// `Substring` hashes by content - the Swift standard library guarantees
    /// `String` and `Substring` hash equally for equivalent contents - so
    /// `contains(_:)` can be called with a Substring view of a different host
    /// string with no per-query allocation.
    let suffixes: Set<Substring>

    init(suffixes basicRules: Set<String>) {
        var views: Set<Substring> = []
        views.reserveCapacity(basicRules.count)
        for rule in basicRules {
            views.insert(rule[...])
        }
        self.suffixes = views
    }

    /// Loads the bundled Public Suffix List and keeps only the basic-rule
    /// suffix set. Use this when you don't need wildcard/exception matching:
    /// the lookup runs as one `Set.contains` per host label.
    public init() throws(DomainParserError) {
        let parsed = try RulesParser.parse(raw: _loadBundledPSLData(), sortRules: false)
        self.init(suffixes: parsed.basicRules)
    }

    public func parse(host: String) -> ParsedHost? {
        return parse(labels: HostLabels(host: host))
    }

    func parse(labels: HostLabels) -> ParsedHost? {
        guard !labels.isEmpty else { return nil }

        // Build the normalized host as one String, then walk it by label
        // boundary - each candidate suffix is a free Substring view, and
        // `suffixes.contains(_: Substring)` is alloc-free.
        let normalizedHost = labels.normalized.joined(separator: ".")
        var labelStart = normalizedHost.startIndex

        for (i, label) in labels.normalized.enumerated() {
            let candidate = normalizedHost[labelStart...]
            if suffixes.contains(candidate) {
                // Output uses the original labels so the caller gets ACE-out
                // for ACE-in and Unicode-out for Unicode-in.
                let publicSuffix = labels.original[i...].joined(separator: ".")
                let registrableDomain = i > 0
                    ? labels.original[(i - 1)...].joined(separator: ".")
                    : nil
                return ParsedHost(publicSuffix: publicSuffix,
                                  registrableDomain: registrableDomain)
            }
            // Advance past this label and its trailing '.' separator. Skip
            // for the last label - we don't need labelStart again, and
            // advancing would step off the end of `normalizedHost`.
            if i < labels.normalized.count - 1 {
                labelStart = normalizedHost.index(labelStart, offsetBy: label.count + 1)
            }
        }
        return nil
    }
}
