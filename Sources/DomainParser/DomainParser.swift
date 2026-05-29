import Foundation

/// Errors thrown by `DomainParser` and `BasicDomainParser` during
/// initialization.
public enum DomainParserError: Error {
    /// The Public Suffix List bytes could not be interpreted as valid
    /// UTF-8, or contained a rule with a shape this parser does not
    /// support (e.g. a wildcard or exception rule whose final label is
    /// itself a wildcard).
    ///
    /// `message` is a human-readable description; not localized.
    case ruleParsingError(message: String)

    /// The bundled `public_suffix_list.dat` resource could not be located
    /// in `Bundle.module`. In a shipping build this indicates a packaging
    /// bug - the resource is declared in `Package.swift` and should always
    /// be present.
    case missingPublicSuffixListResource

    /// Reading the bundled `public_suffix_list.dat` resource off disk
    /// failed - typically an underlying Foundation `CocoaError` from
    /// `Data(contentsOf:)`. Wrapped so the typed-throws boundary stays
    /// closed.
    case bundleLoadFailed(underlying: any Error)
}

/// Loads the bundled `public_suffix_list.dat` resource as raw bytes.
/// Shared by `DomainParser.init` and `BasicDomainParser.init`.
internal func _loadBundledPSLData() throws(DomainParserError) -> Data {
    guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat") else {
        throw DomainParserError.missingPublicSuffixListResource
    }
    do {
        return try Data(contentsOf: url)
    } catch {
        throw DomainParserError.bundleLoadFailed(underlying: error)
    }
}

/// Parses hostnames using the bundled Public Suffix List.
///
/// Immutable and `Sendable`: build one instance and share it across threads
/// and actors. Construction parses the bundled PSL (~10K rules) and is the
/// expensive step; per-call `parse(host:)` lookups are cheap.
public struct DomainParser: DomainParserProtocol, Sendable {

    /// Test-only seam. Exposed at `internal` so `@testable import` can read it;
    /// underscore-prefixed to signal "do not depend on me outside tests."
    let _parsedRules: ParsedRules

    let basicDomainParser: BasicDomainParser

    /// Loads the bundled Public Suffix List and builds the rule set.
    public init() throws(DomainParserError) {
        // We don't need to sort the rules from "public_suffix_list" since
        // the file has already been sorted by the update script.
        try self.init(_rulesData: _loadBundledPSLData(), sortRules: false)
    }

    /// Test-only seam. Underscore-prefixed to signal "do not depend on me
    /// outside tests."
    init(_rulesData rulesData: Data,
         sortRules: Bool = true) throws(DomainParserError) {
        _parsedRules = try RulesParser.parse(raw: rulesData, sortRules: sortRules)
        basicDomainParser = BasicDomainParser(suffixes: _parsedRules.basicRules)
    }

    public func parse(host: String) -> ParsedHost? {
        let labels = HostLabels(host: host)
        return parseExceptionAndWildcardRules(labels: labels)
            ?? basicDomainParser.parse(labels: labels)
    }

    func parseExceptionAndWildcardRules(labels: HostLabels) -> ParsedHost? {
        // Look up by the rightmost normalized label so the index works against
        // the bundled PSL's Unicode-form rules even when the caller passed ACE.
        guard let lastLabel = labels.normalized.last else { return nil }

        let isMatching: (PSLRule) -> Bool = { $0.isMatching(hostLabels: labels) }
        let rule = _parsedRules.exceptions[lastLabel]?.first(where: isMatching) ??
                   _parsedRules.wildcardRules[lastLabel]?.first(where: isMatching)
        return rule?.parse(hostLabels: labels)
    }
}
