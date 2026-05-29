public import Foundation

/// Matches hostnames against the Public Suffix List.
///
/// Immutable and `Sendable`: build one instance (await a factory) and share it
/// across threads and actors. Construction parses the list; `lookup` is a pure,
/// instant value query.
public struct PublicSuffixList: Sendable {
    private let index: RuleIndex

    /// Provenance of the loaded list, for diagnostics.
    public let metadata: ListMetadata

    private init(parsed: ParsedList) {
        self.index = parsed.index
        self.metadata = parsed.metadata
    }

    /// Load the bundled Public Suffix List. Expensive (disk I/O + parse of
    /// ~10K rules); runs off the caller's actor via `@concurrent`.
    @concurrent
    public static func bundled() async throws(PublicSuffixListError) -> PublicSuffixList {
        try PublicSuffixList(parsed: RulesParser.parse(loadBundledData()))
    }

    /// Load from caller-supplied list bytes (custom lists / tests).
    @concurrent
    public static func loading(from data: Data) async throws(PublicSuffixListError) -> PublicSuffixList {
        try PublicSuffixList(parsed: RulesParser.parse(data))
    }

    /// Look a host up against the list. Returns nil only for non-hostnames
    /// (empty, IP literal, empty/leading label). Every real hostname yields a
    /// `HostInfo` because the implicit "*" rule guarantees a suffix.
    public func lookup(_ host: String, scope: MatchScope = .all) -> HostInfo? {
        guard let h = NormalizedHost(host) else { return nil }
        let rule = index.prevailingRule(for: h.matchLabels, scope: scope)

        // Public-suffix label count = rule labels, minus one if it is an
        // exception rule (an exception removes its leftmost label).
        let suffixLabelCount = rule.isException ? rule.labelCount - 1 : rule.labelCount
        guard suffixLabelCount >= 1, suffixLabelCount <= h.labelCount else { return nil }

        let suffixStart = h.labelCount - suffixLabelCount
        let publicSuffix = h.joinedOriginal(from: suffixStart)

        let registrableDomain: String?
        let subdomain: String?
        if suffixStart >= 1 {
            registrableDomain = h.joinedOriginal(from: suffixStart - 1)
            subdomain = suffixStart >= 2
                ? h.originalLabels[0..<(suffixStart - 1)].joined(separator: ".")
                : nil
        } else {
            registrableDomain = nil   // host is itself a bare public suffix
            subdomain = nil
        }

        return HostInfo(publicSuffix: publicSuffix,
                        registrableDomain: registrableDomain,
                        subdomain: subdomain,
                        source: rule.source)
    }

    private static func loadBundledData() throws(PublicSuffixListError) -> Data {
        guard let url = Bundle.module.url(forResource: "public_suffix_list",
                                          withExtension: "dat") else {
            throw .missingBundledResource
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .bundleLoadFailed(underlying: error)
        }
    }
}
