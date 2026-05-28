import Foundation

public struct ParsedHost: Sendable, Equatable, Hashable {

    /// E.g. "com", "co.uk"
    public let publicSuffix: String

    /// (Registrable) domain excluding subdomains. E.g. "github.com", "amazon.co.uk"
    public let domain: String?
}
