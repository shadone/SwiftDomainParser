import Foundation

public struct ParsedHost: Sendable, Equatable, Hashable {

    /// The public suffix from the PSL. E.g. `"com"`, `"co.uk"`.
    public let publicSuffix: String

    /// The registrable domain - the public suffix plus one label to the left
    /// (the "label a registrar lets you buy"). E.g. `"github.com"`,
    /// `"amazon.co.uk"`. `nil` when the host is itself a public suffix
    /// (e.g. `"co.uk"`) and therefore has no domain to register under it.
    public let registrableDomain: String?
}
