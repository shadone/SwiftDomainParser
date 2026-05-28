import Foundation

/// Parses a hostname using only the basic (non-wildcard, non-exception) suffix rules.
/// Examples of valid rules: **com**, **co.uk**, **ide.kyoto.jp**.
///
/// - Precondition: `host` is already lowercased. Callers reaching this through
///   `DomainParser.parse(host:)` get this for free; direct callers should pass
///   `host.lowercased()` themselves.
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
        let hostComponents = host.split(separator: ".")
        var hostSlices = ArraySlice(hostComponents)

        var candidateSuffix = ""

        // Check if the host ends with a suffix in the set.
        // For api.dashlane.co.uk: first check whether dashlane.co.uk is a
        // known suffix, then co.uk, then uk, ...
        repeat {
            guard !hostSlices.isEmpty else { return nil }
            candidateSuffix = hostSlices.joined(separator: ".")
            hostSlices = hostSlices.dropFirst()
        } while !suffixes.contains(candidateSuffix)

        // The registrable domain is the suffix plus one more left-side label.
        let domainRange = (hostSlices.startIndex - 2)..<hostComponents.endIndex
        let registrableDomain = domainRange.startIndex >= 0
            ? hostComponents[domainRange].joined(separator: ".")
            : nil
        return ParsedHost(publicSuffix: candidateSuffix, registrableDomain: registrableDomain)
    }
}
