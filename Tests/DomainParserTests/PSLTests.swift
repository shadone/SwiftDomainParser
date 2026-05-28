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
            // IDN labels - Unicode form (input form preserved in output).
            ("食狮.com.cn", "食狮.com.cn"),
            ("食狮.公司.cn", "食狮.公司.cn"),
            ("www.食狮.公司.cn", "食狮.公司.cn"),
            ("shishi.公司.cn", "shishi.公司.cn"),
            ("公司.cn", nil),
            ("食狮.中国", "食狮.中国"),
            ("www.食狮.中国", "食狮.中国"),
            ("shishi.中国", "shishi.中国"),
            ("中国", nil),
            // IDN labels - ACE/Punycode form (input form preserved in output).
            ("xn--85x722f.com.cn", "xn--85x722f.com.cn"),
            ("xn--85x722f.xn--55qx5d.cn", "xn--85x722f.xn--55qx5d.cn"),
            ("www.xn--85x722f.xn--55qx5d.cn", "xn--85x722f.xn--55qx5d.cn"),
            ("shishi.xn--55qx5d.cn", "shishi.xn--55qx5d.cn"),
            ("xn--55qx5d.cn", nil),
            ("xn--85x722f.xn--fiqs8s", "xn--85x722f.xn--fiqs8s"),
            ("www.xn--85x722f.xn--fiqs8s", "xn--85x722f.xn--fiqs8s"),
            ("shishi.xn--fiqs8s", "shishi.xn--fiqs8s"),
            ("xn--fiqs8s", nil),
          ] as [(String, String?)])
    func psl(host: String, expectedDomain: String?) {
        // checkPublicSuffix in upstream's test file lowercases the host before
        // calling the parser, so we do the same here.
        #expect(parser.parse(host: host.lowercased())?.registrableDomain == expectedDomain)
    }

    // MARK: - TLD with no domain

    @Test func tldWithNoDomain() {
        #expect(parser.parse(host: "com") == ParsedHost(publicSuffix: "com", registrableDomain:nil))
        #expect(parser.parse(host: "co.uk") == ParsedHost(publicSuffix: "co.uk", registrableDomain:nil))
        #expect(parser.parse(host: "ide.kyoto.jp") == ParsedHost(publicSuffix: "ide.kyoto.jp", registrableDomain:nil))
        // Wildcard
        #expect(parser.parse(host: "any.ck") == ParsedHost(publicSuffix: "any.ck", registrableDomain:nil))
        #expect(parser.parse(host: "any.mm") == ParsedHost(publicSuffix: "any.mm", registrableDomain:nil))
    }

    // MARK: - IDN: ACE-encoded labels are matched against Unicode PSL rules

    /// The bundled PSL stores IDN entries in Unicode form. Hosts may arrive
    /// in either Unicode (e.g. `公司.cn`) or ACE (e.g. `xn--55qx5d.cn`) form
    /// depending on where they came from. Verify both forms find the same
    /// rule, and that the output preserves the caller's form.
    @Test func idnACEAndUnicodeBothMatch() {
        // ACE input → ACE output.
        #expect(parser.parse(host: "shishi.xn--55qx5d.cn") ==
                ParsedHost(publicSuffix: "xn--55qx5d.cn",
                           registrableDomain: "shishi.xn--55qx5d.cn"))
        // Unicode input → Unicode output (same rule matched).
        #expect(parser.parse(host: "shishi.公司.cn") ==
                ParsedHost(publicSuffix: "公司.cn",
                           registrableDomain: "shishi.公司.cn"))
        // Mixed: ACE registrable label, Unicode suffix.
        #expect(parser.parse(host: "xn--85x722f.公司.cn") ==
                ParsedHost(publicSuffix: "公司.cn",
                           registrableDomain: "xn--85x722f.公司.cn"))
    }

    // MARK: - Mixed-case host on the exception/wildcard branch

    /// PSL rules are emitted lowercase; the parser must lowercase the host
    /// before matching - on the exception/wildcard branch too. Regression
    /// test for the case-sensitivity bug fixed alongside this commit's
    /// ancestor.
    @Test func mixedCaseHostHittingWildcardOrExceptionRule() {
        // `*.ck` wildcard
        #expect(parser.parse(host: "B.Test.CK") ==
                ParsedHost(publicSuffix: "test.ck", registrableDomain:"b.test.ck"))
        // `!www.ck` exception
        #expect(parser.parse(host: "WWW.CK") ==
                ParsedHost(publicSuffix: "ck", registrableDomain:"www.ck"))
        #expect(parser.parse(host: "Sub.WWW.CK") ==
                ParsedHost(publicSuffix: "ck", registrableDomain:"www.ck"))
    }

    // MARK: - URL convenience overload

    @Test func parseURLConvenience() {
        #expect(parser.parse(url: URL(string: "https://www.example.com/path?q=1")!) ==
                ParsedHost(publicSuffix: "com", registrableDomain:"example.com"))
        #expect(parser.parse(url: URL(string: "https://api.example.co.uk")!) ==
                ParsedHost(publicSuffix: "co.uk", registrableDomain:"example.co.uk"))
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
        let custom = try DomainParser(_rulesData: Data(rules.utf8))

        // Sanity: a domain that would normally resolve doesn't under this custom set.
        #expect(custom.parse(host: "google.fr")?.registrableDomain == nil)

        #expect(custom.parse(host: "foo.com")?.registrableDomain == "foo.com")
        #expect(custom.parse(host: "foo.bar.jp")?.registrableDomain == "foo.bar.jp")
        #expect(custom.parse(host: "bar.jp")?.registrableDomain == nil)
        #expect(custom.parse(host: "foo.bar.hokkaido.jp")?.registrableDomain == "foo.bar.hokkaido.jp")
        #expect(custom.parse(host: "bar.hokkaido.jp")?.registrableDomain == nil)
        #expect(custom.parse(host: "foo.bar.tokyo.jp")?.registrableDomain == "foo.bar.tokyo.jp")
        #expect(custom.parse(host: "bar.tokyo.jp")?.registrableDomain == nil)
        // Exceptions override the wildcard
        #expect(custom.parse(host: "pref.hokkaido.jp")?.registrableDomain == "pref.hokkaido.jp")
        #expect(custom.parse(host: "metro.tokyo.jp")?.registrableDomain == "metro.tokyo.jp")
    }

    // MARK: - RulesParser accepts raw upstream PSL

    /// `RulesParser` must tolerate raw upstream PSL input: blank lines,
    /// "//"-prefixed comments, and inline trailing whitespace per the spec
    /// (https://publicsuffix.org/list/ - "each line is only read up to the
    /// first whitespace"). The bundled .dat is pre-normalized so the default
    /// path never sees these, but `init(_rulesData:)` and any future direct
    /// caller may pass raw input.
    @Test func rulesParserToleratesRawUpstreamFormat() throws {
        let rawPSL = """
        // ===BEGIN ICANN DOMAINS===

        // example comment line
        com
        co.uk \t<- inline trailing junk per spec
        *.ck
        !www.ck

        // ===END ICANN DOMAINS===
        """
        let parser = try DomainParser(_rulesData: Data(rawPSL.utf8))

        // Comment lines should NOT become basic rules.
        #expect(parser._parsedRules.basicRules == ["com", "co.uk"])

        // Wildcard and exception still classified correctly.
        #expect(parser.parse(host: "example.com")?.registrableDomain == "example.com")
        #expect(parser.parse(host: "a.b.test.ck")?.registrableDomain == "b.test.ck")
        #expect(parser.parse(host: "www.ck")?.registrableDomain == "www.ck")
    }

    // MARK: - BasicDomainParser standalone

    /// BasicDomainParser is publicly constructible and produces the same
    /// answers as DomainParser for plain (non-wildcard, non-exception) hosts.
    @Test func basicDomainParserStandalone() throws {
        let basic = try BasicDomainParser()
        #expect(basic.parse(host: "example.com") ==
                ParsedHost(publicSuffix: "com", registrableDomain:"example.com"))
        #expect(basic.parse(host: "api.example.co.uk") ==
                ParsedHost(publicSuffix: "co.uk", registrableDomain:"example.co.uk"))
        // Basic parser does NOT handle wildcards - "b.test.ck" is unmatched
        // (the wildcard "*.ck" is parsed but not consulted on this code path).
        #expect(basic.parse(host: "b.test.ck") == nil)
    }

    // MARK: - The bundled PSL .dat file is sorted by descending label count

    /// The update script (`swift script/UpdatePSL.swift`) writes the .dat file
    /// with rules sorted by descending label count, so the parser can rely on
    /// "first match wins" semantics. If someone hand-edits the file without
    /// re-running the script, this invariant breaks - and that's a real bug,
    /// since `parseExceptionsAndWildCardRules` returns the first matching rule.
    ///
    /// Fail CI if the bundled file is not sorted.
    @Test func bundledPSLFileIsSortedByDescendingLabelCount() throws {
        let url = try #require(Bundle.module.url(forResource: "public_suffix_list",
                                                 withExtension: "dat"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let labelCounts = text
            .split(separator: "\n")
            .map { $0.split(separator: ".").count }

        for (index, pair) in zip(labelCounts, labelCounts.dropFirst()).enumerated() {
            #expect(pair.0 >= pair.1,
                    "Bundled PSL is not sorted by descending label count: line \(index + 1) has \(pair.0) labels but line \(index + 2) has \(pair.1). Run `swift script/UpdatePSL.swift` to re-normalize.")
        }
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
        for (lastLabel, rules) in parser._parsedRules.wildcardRules {
            #expect(isSortedByDescendingScore(rules),
                    "wildcard rules for \"\(lastLabel)\" are not sorted")
        }
        for (lastLabel, rules) in parser._parsedRules.exceptions {
            #expect(isSortedByDescendingScore(rules),
                    "exception rules for \"\(lastLabel)\" are not sorted")
        }
    }
}
