/// A host split into labels in two parallel forms, with FQDN/validity handling.
///
/// - `originalLabels`: lowercased, original ACE/Unicode form — used to build
///   output so the caller gets back the same form they passed in.
/// - `matchLabels`: full UTS-46 canonical form (mapped + NFC, xn-- labels
///   Punycode-decoded) — used to match the Unicode-form bundled rules.
struct NormalizedHost {
    let originalLabels: [String]
    let matchLabels: [String]
    let hadTrailingDot: Bool

    /// Returns nil for non-hostnames: empty input, IP literals, empty/leading
    /// labels. A single trailing dot is allowed and recorded.
    init?(_ host: String) {
        guard !host.isEmpty, !IPLiteral.isIPLiteral(host) else { return nil }

        let lowered = host.lowercased()

        // Trailing dot (FQDN): allowed once, preserved; stripped for splitting.
        var core = Substring(lowered)
        var trailingDot = false
        if core.last == "." {
            core = core.dropLast()
            trailingDot = true
        }
        guard !core.isEmpty else { return nil } // host was only dots

        // Empty labels (leading/interior/another trailing) are not permitted.
        let rawLabels = core.split(separator: ".", omittingEmptySubsequences: false)
        guard rawLabels.allSatisfy({ !$0.isEmpty }) else { return nil }

        let original = rawLabels.map(String.init)
        self.originalLabels = original
        self.hadTrailingDot = trailingDot
        self.matchLabels = original.map { IDNA.canonicalLabel($0) }
    }

    /// Join original labels from index `from` to the end, re-appending the
    /// trailing dot if the input had one.
    func joinedOriginal(from index: Int) -> String {
        let joined = originalLabels[index...].joined(separator: ".")
        return hadTrailingDot ? joined + "." : joined
    }

    var labelCount: Int { originalLabels.count }
}
