// `public` because `parse(url:)` exposes Foundation's `URL` through this
// module's public API (required under the InternalImportsByDefault feature).
public import Foundation

/// The common interface implemented by every parser in this module
/// (`DomainParser`, `BasicDomainParser`, `FakeDomainParser`).
///
/// Conformers are `Sendable` so a single instance can be shared across
/// isolation domains - hold onto one instance and reuse it.
///
/// Construction is the expensive step (it loads and parses the bundled
/// Public Suffix List, ~10K rules); per-call lookup is cheap.
public protocol DomainParserProtocol: Sendable {
    /// Returns the registrable domain and public suffix for `host`, or
    /// `nil` if no matching PSL rule applies.
    ///
    /// Host comparison is case-insensitive when called through
    /// `DomainParser`; `BasicDomainParser` requires lowercase input.
    func parse(host: String) -> ParsedHost?
}

extension DomainParserProtocol {
    /// Convenience overload for callers that already have a `URL`.
    /// Returns `nil` if the URL has no host component.
    public func parse(url: URL) -> ParsedHost? {
        guard let host = url.host() else { return nil }
        return parse(host: host)
    }
}

#if DEBUG
/// A no-op DomainParserProtocol implementation for tests and SwiftUI previews.
/// Always returns nil so callers can exercise the "no PSL match" path without
/// loading the real public suffix list.
public struct FakeDomainParser: DomainParserProtocol {
    public init() {}
    public func parse(host: String) -> ParsedHost? {
        return nil
    }
}
#endif
