/// Caches the bundled list so `PublicSuffixList.shared()` loads it once.
actor SharedListCache {
    static let instance = SharedListCache()
    private var cached: PublicSuffixList?

    func value() async throws -> PublicSuffixList {
        if let cached { return cached }
        let list = try await PublicSuffixList.bundled()
        cached = list
        return list
    }
}
