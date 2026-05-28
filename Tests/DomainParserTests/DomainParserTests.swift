//
//  DomainParserTests.swift
//  DomainParserTests
//
//  XCTest performance measurements. Behavioural tests live in PSLTests.swift
//  (Swift Testing); these stay XCTest because `measure {}` has no Swift
//  Testing equivalent yet.
//

import XCTest
@testable import DomainParser

class DomainParserPerformanceTests: XCTestCase {

    func testMeasureSetupTime() {
        measure {
            _ = try! DomainParser()
        }
    }

    /// Per-call parse throughput on the real bundled PSL. Measures the cost
    /// of parser.parse(host:) across a mix of common host shapes, excluding
    /// init cost (built once outside the measure block).
    func testMeasureParseThroughputOnRealPSL() {
        let parser = try! DomainParser()
        let hosts: [String] = [
            "www.example.com",
            "api.example.co.uk",
            "deep.subdomain.example.gov.uk",
            "shishi.公司.cn",
            "shishi.xn--55qx5d.cn",
            "metro.tokyo.jp",
            "b.test.ck",
            "host.with.no.matching.suffix.zzz",  // miss
            "github.com",
            "amazon.co.uk",
        ]
        measure {
            for _ in 0..<1000 {
                for h in hosts { _ = parser.parse(host: h) }
            }
        }
    }

    func testMeasureParseManyWildcardAndExceptionRules() {
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        var rulesArray: [String] = []

        // Generate a lot of wildcard and exception rules to stress the
        // by-last-label dictionary lookup.
        for letter1 in alphabet {
            for letter2 in alphabet {
                rulesArray.append("*.\(letter1)\(letter2)")
                rulesArray.append("!except.\(letter1)\(letter2)")
            }
        }

        let rulesData = Data(rulesArray.joined(separator: "\n").utf8)
        let customDomainParser = try! DomainParser(_rulesData: rulesData)

        // Sanity: a normally-valid host is not valid under this custom rule set.
        XCTAssertNil(customDomainParser.parse(host: "google.fr")?.registrableDomain)

        measure {
            for _ in 0...10 {
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.ky")?.registrableDomain, "domain.any.ky")
                XCTAssertEqual(customDomainParser.parse(host: "except.ky")?.registrableDomain, "except.ky")
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.tz")?.registrableDomain, "domain.any.tz")
                XCTAssertEqual(customDomainParser.parse(host: "except.tz")?.registrableDomain, "except.tz")
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.nf")?.registrableDomain, "domain.any.nf")
                XCTAssertEqual(customDomainParser.parse(host: "except.nf")?.registrableDomain, "except.nf")
            }
        }
    }
}
