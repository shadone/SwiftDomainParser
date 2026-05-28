//
//  PSLSyntax.swift
//  DomainParser
//
//  Markers from the Public Suffix List rule format:
//  https://github.com/publicsuffix/list/wiki/Format
//

enum PSLSyntax {
    /// Lines starting with "!" are exception rules.
    static let exceptionMarker = "!"
    /// "*" is the wildcard label.
    static let wildcardComponent = "*"
}
