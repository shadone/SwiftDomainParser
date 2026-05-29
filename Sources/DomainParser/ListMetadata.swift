/// Provenance of a loaded Public Suffix List, for diagnostics.
public struct ListMetadata: Sendable, Equatable {
    /// Date the bundled list was fetched (ISO-8601, e.g. "2026-05-28"), if known.
    public let sourceDate: String?
    /// Upstream commit/revision the list was fetched at, if known.
    public let sourceRevision: String?
    /// Number of ICANN-section rules loaded.
    public let icannRuleCount: Int
    /// Number of PRIVATE-section rules loaded.
    public let privateRuleCount: Int

    public init(sourceDate: String?, sourceRevision: String?,
                icannRuleCount: Int, privateRuleCount: Int) {
        self.sourceDate = sourceDate
        self.sourceRevision = sourceRevision
        self.icannRuleCount = icannRuleCount
        self.privateRuleCount = privateRuleCount
    }
}
