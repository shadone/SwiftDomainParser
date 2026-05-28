//
//  PSLTests.swift
//  DomainParserTests
//
//  Behavioural tests for DomainParser, written with Swift Testing.
//  Performance measurements remain in DomainParserTests.swift (XCTest's
//  measure {} block has no Swift Testing equivalent yet).
//

import Foundation
import Testing
@testable import DomainParser

@Suite("DomainParser")
struct DomainParserSuite {

    let parser: DomainParser

    init() throws {
        parser = try DomainParser()
    }

    // MARK: - PSL conformance

    /// Common PSL test cases, sourced from:
    /// https://raw.githubusercontent.com/publicsuffix/list/master/tests/test_psl.txt
    ///
    /// The library does not implement Punycode, so the punycoded IDN cases in
    /// upstream's test file are intentionally omitted.
    @Test("PSL conformance",
          arguments: [
            // Mixed case
            ("COM", nil),
            ("example.COM", "example.com"),
            ("WwW.example.COM", "example.com"),
            // TLD with only 1 rule
            ("biz", nil),
            ("domain.biz", "domain.biz"),
            ("b.domain.biz", "domain.biz"),
            ("a.b.domain.biz", "domain.biz"),
            // TLD with some 2-level rules
            ("com", nil),
            ("example.com", "example.com"),
            ("b.example.com", "example.com"),
            ("a.b.example.com", "example.com"),
            ("uk.com", nil),
            ("example.uk.com", "example.uk.com"),
            ("b.example.uk.com", "example.uk.com"),
            ("a.b.example.uk.com", "example.uk.com"),
            ("test.ac", "test.ac"),
            // TLD with only 1 (wildcard) rule
            ("mm", nil),
            ("c.mm", nil),
            ("b.c.mm", "b.c.mm"),
            ("a.b.c.mm", "b.c.mm"),
            // More complex TLD
            ("jp", nil),
            ("test.jp", "test.jp"),
            ("www.test.jp", "test.jp"),
            ("ac.jp", nil),
            ("test.ac.jp", "test.ac.jp"),
            ("www.test.ac.jp", "test.ac.jp"),
            ("kyoto.jp", nil),
            ("test.kyoto.jp", "test.kyoto.jp"),
            ("ide.kyoto.jp", nil),
            ("b.ide.kyoto.jp", "b.ide.kyoto.jp"),
            ("a.b.ide.kyoto.jp", "b.ide.kyoto.jp"),
            ("c.kobe.jp", nil),
            ("b.c.kobe.jp", "b.c.kobe.jp"),
            ("a.b.c.kobe.jp", "b.c.kobe.jp"),
            ("city.kobe.jp", "city.kobe.jp"),
            ("www.city.kobe.jp", "city.kobe.jp"),
            // TLD with wildcard and exceptions
            ("ck", nil),
            ("test.ck", nil),
            ("b.test.ck", "b.test.ck"),
            ("a.b.test.ck", "b.test.ck"),
            ("www.ck", "www.ck"),
            ("www.www.ck", "www.ck"),
            // US K12
            ("us", nil),
            ("test.us", "test.us"),
            ("www.test.us", "test.us"),
            ("ak.us", nil),
            ("test.ak.us", "test.ak.us"),
            ("www.test.ak.us", "test.ak.us"),
            ("k12.ak.us", nil),
            ("test.k12.ak.us", "test.k12.ak.us"),
            ("www.test.k12.ak.us", "test.k12.ak.us"),
            // IDN labels (non-punycode)
            ("食狮.com.cn", "食狮.com.cn"),
            ("食狮.公司.cn", "食狮.公司.cn"),
            ("www.食狮.公司.cn", "食狮.公司.cn"),
            ("shishi.公司.cn", "shishi.公司.cn"),
            ("公司.cn", nil),
            ("食狮.中国", "食狮.中国"),
            ("www.食狮.中国", "食狮.中国"),
            ("shishi.中国", "shishi.中国"),
            ("中国", nil),
          ] as [(String, String?)])
    func psl(host: String, expectedDomain: String?) {
        // checkPublicSuffix in upstream's test file lowercases the host before
        // calling the parser, so we do the same here.
        #expect(parser.parse(host: host.lowercased())?.domain == expectedDomain)
    }

    // MARK: - TLD with no domain

    @Test func tldWithNoDomain() {
        #expect(parser.parse(host: "com") == ParsedHost(publicSuffix: "com", domain: nil))
        #expect(parser.parse(host: "co.uk") == ParsedHost(publicSuffix: "co.uk", domain: nil))
        #expect(parser.parse(host: "ide.kyoto.jp") == ParsedHost(publicSuffix: "ide.kyoto.jp", domain: nil))
        // Wildcard
        #expect(parser.parse(host: "any.ck") == ParsedHost(publicSuffix: "any.ck", domain: nil))
        #expect(parser.parse(host: "any.mm") == ParsedHost(publicSuffix: "any.mm", domain: nil))
    }

    // MARK: - Mixed-case host on the exception/wildcard branch

    /// PSL rules are emitted lowercase; the parser must lowercase the host
    /// before matching - on the exception/wildcard branch too. Regression
    /// test for the case-sensitivity bug fixed alongside this commit's
    /// ancestor.
    @Test func mixedCaseHostHittingWildcardOrExceptionRule() {
        // `*.ck` wildcard
        #expect(parser.parse(host: "B.Test.CK") ==
                ParsedHost(publicSuffix: "test.ck", domain: "b.test.ck"))
        // `!www.ck` exception
        #expect(parser.parse(host: "WWW.CK") ==
                ParsedHost(publicSuffix: "ck", domain: "www.ck"))
        #expect(parser.parse(host: "Sub.WWW.CK") ==
                ParsedHost(publicSuffix: "ck", domain: "www.ck"))
    }

    // MARK: - URL convenience overload

    @Test func parseURLConvenience() {
        #expect(parser.parse(url: URL(string: "https://www.example.com/path?q=1")!) ==
                ParsedHost(publicSuffix: "com", domain: "example.com"))
        #expect(parser.parse(url: URL(string: "https://api.example.co.uk")!) ==
                ParsedHost(publicSuffix: "co.uk", domain: "example.co.uk"))
        // file:// URLs have no host
        #expect(parser.parse(url: URL(string: "file:///etc/hosts")!) == nil)
    }

    // MARK: - Wildcard / exception precedence on a custom rule set

    /// From https://github.com/publicsuffix/list/wiki/Format#example
    @Test func wildcardRulesSorting() throws {
        let rules = [
            "com",
            "*.jp",
            "*.hokkaido.jp",
            "*.tokyo.jp",
            "!pref.hokkaido.jp",
            "!metro.tokyo.jp",
        ].joined(separator: "\n")
        let custom = try DomainParser(rulesData: Data(rules.utf8))

        // Sanity: a domain that would normally resolve doesn't under this custom set.
        #expect(custom.parse(host: "google.fr")?.domain == nil)

        #expect(custom.parse(host: "foo.com")?.domain == "foo.com")
        #expect(custom.parse(host: "foo.bar.jp")?.domain == "foo.bar.jp")
        #expect(custom.parse(host: "bar.jp")?.domain == nil)
        #expect(custom.parse(host: "foo.bar.hokkaido.jp")?.domain == "foo.bar.hokkaido.jp")
        #expect(custom.parse(host: "bar.hokkaido.jp")?.domain == nil)
        #expect(custom.parse(host: "foo.bar.tokyo.jp")?.domain == "foo.bar.tokyo.jp")
        #expect(custom.parse(host: "bar.tokyo.jp")?.domain == nil)
        // Exceptions override the wildcard
        #expect(custom.parse(host: "pref.hokkaido.jp")?.domain == "pref.hokkaido.jp")
        #expect(custom.parse(host: "metro.tokyo.jp")?.domain == "metro.tokyo.jp")
    }

    // MARK: - The bundled PSL is already sorted

    /// The local PSL is sorted at update time (in script/UpdatePSL.swift) so
    /// the runtime doesn't have to. Verify the wildcard/exception rule arrays
    /// come out sorted by descending rankingScore.
    @Test func parsedRulesFromLocalListAreSorted() {
        let isSortedByDescendingScore: ([Rule]) -> Bool = { rules in
            zip(rules, rules.dropFirst())
                .allSatisfy { $0.rankingScore >= $1.rankingScore }
        }
        for (lastLabel, rules) in parser.parsedRules.wildcardRules {
            #expect(isSortedByDescendingScore(rules),
                    "wildcard rules for \"\(lastLabel)\" are not sorted")
        }
        for (lastLabel, rules) in parser.parsedRules.exceptions {
            #expect(isSortedByDescendingScore(rules),
                    "exception rules for \"\(lastLabel)\" are not sorted")
        }
    }
}
