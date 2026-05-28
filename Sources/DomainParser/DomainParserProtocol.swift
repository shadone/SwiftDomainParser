//
//  DomainParserProtocol.swift
//  DomainParser
//
//  Created by Rayane Kurrimboccus on 31/01/2023.
//  Copyright © 2023 Dashlane. All rights reserved.
//

import Foundation

public protocol DomainParserProtocol: Sendable {
    func parse(host: String) -> ParsedHost?
}

extension DomainParserProtocol {
    /// Convenience overload for callers that already have a `URL`.
    /// Returns `nil` if the URL has no host component.
    public func parse(url: URL) -> ParsedHost? {
        guard let host = url.host else { return nil }
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
