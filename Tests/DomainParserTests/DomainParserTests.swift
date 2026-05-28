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
