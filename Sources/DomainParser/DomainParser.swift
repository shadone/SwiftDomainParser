import Foundation

public enum DomainParserError: Error {
    case ruleParsingError(message: String)
    case missingPublicSuffixListResource
}

/// Loads the bundled `public_suffix_list.dat` resource as raw bytes.
/// Shared by `DomainParser.init` and `BasicDomainParser.init`.
internal func _loadBundledPSLData() throws -> Data {
    guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat") else {
        throw DomainParserError.missingPublicSuffixListResource
    }
    return try Data(contentsOf: url)
}

/// Parses hostnames using the bundled Public Suffix List.
public struct DomainParser: DomainParserProtocol {

    /// Test-only seam. Exposed at `internal` so `@testable import` can read it;
    /// underscore-prefixed to signal "do not depend on me outside tests."
    let _parsedRules: ParsedRules

    let onlyBasicRules: Bool

    let basicDomainParser: BasicDomainParser

    /// Loads the bundled Public Suffix List and builds the rule set.
    public init() throws {
        // We don't need to sort the rules from "public_suffix_list" since
        // the file has already been sorted by the update script.
        try self.init(_rulesData: _loadBundledPSLData(), quickParsing: false, sortRules: false)
    }

    /// Loads the bundled Public Suffix List with optional wildcard/exception skipping.
    ///
    /// - Parameter quickParsing: If `true`, exception and wildcard rules are
    ///   ignored at parse time.
    ///
    /// Deprecated: use ``BasicDomainParser`` directly for the basic-only path.
    /// It exposes the same lookup without paying for wildcard/exception
    /// parsing up front, and the API surface is clearer about what's
    /// happening at the call site.
    @available(*, deprecated, message: "Use BasicDomainParser() for the basic-only path; use DomainParser() for full PSL parsing.")
    public init(quickParsing: Bool) throws {
        try self.init(_rulesData: _loadBundledPSLData(), quickParsing: quickParsing, sortRules: false)
    }

    /// Test-only seam. Underscore-prefixed to signal "do not depend on me
    /// outside tests."
    init(_rulesData rulesData: Data, quickParsing: Bool = false, sortRules: Bool = true) throws {
        _parsedRules = try RulesParser.parse(raw: rulesData, sortRules: sortRules)
        basicDomainParser = BasicDomainParser(suffixes: _parsedRules.basicRules)
        onlyBasicRules = quickParsing
    }

    public func parse(host: String) -> ParsedHost? {
        // PSL rules are all lowercase; URL host comparison is case-insensitive.
        // Lowercase once here so both branches see canonical labels.
        let host = host.lowercased()
        if onlyBasicRules {
            return basicDomainParser.parse(host: host)
        } else {
            return parseExceptionsAndWildCardRules(host: host) ?? basicDomainParser.parse(host: host)
        }
     }

    func parseExceptionsAndWildCardRules(host: String) -> ParsedHost? {
        let hostComponents = host.split(separator: ".")
        guard let lastLabelSubstring = hostComponents.last else {
            return nil
        }

        let lastLabel = String(lastLabelSubstring)
        let isMatching: (Rule) -> Bool = { $0.isMatching(hostLabels: hostComponents) }
        let rule = _parsedRules.exceptions[lastLabel]?.first(where: isMatching) ??
                   _parsedRules.wildcardRules[lastLabel]?.first(where: isMatching)

        return rule?.parse(hostLabels: hostComponents)
    }
}
