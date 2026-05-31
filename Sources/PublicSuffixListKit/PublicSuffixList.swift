public import Foundation

/// Matches hostnames against the Public Suffix List.
///
/// Immutable and `Sendable`. Use ``shared`` for the bundled list — it decodes
/// the precompiled blob once, synchronously, on first access. `lookup` is a
/// pure, instant value query.
public struct PublicSuffixList: Sendable {
    private let index: RuleIndex

    /// Provenance of the loaded list, for diagnostics.
    public let metadata: ListMetadata

    private init(parsed: ParsedList) {
        self.index = parsed.index
        self.metadata = parsed.metadata
    }

    /// The bundled Public Suffix List, decoded from the precompiled binary blob
    /// on first access and cached for the process lifetime.
    ///
    /// Synchronous and non-throwing: `static let` gives lazy, thread-safe,
    /// once-only initialization, and the blob is a build-time artifact we
    /// generate and check in — a missing or corrupt blob can only mean the
    /// package itself is broken, so this traps rather than throwing.
    public static let shared: PublicSuffixList = {
        guard let url = Bundle.module.url(forResource: "public_suffix_list",
                                          withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              let parsed = PSLBinaryFormat.decode(data) else {
            preconditionFailure(
                "PublicSuffixListKit: bundled public_suffix_list.bin is missing "
                + "or corrupt. This is a package defect, not a runtime condition.")
        }
        return PublicSuffixList(parsed: parsed)
    }()

    /// Load from caller-supplied list bytes (custom / non-bundled `.dat` text
    /// lists, and tests). Parses text, so it throws.
    public static func loading(from data: Data) throws(PublicSuffixListError) -> PublicSuffixList {
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
}
