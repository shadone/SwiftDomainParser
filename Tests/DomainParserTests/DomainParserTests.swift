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
        let customDomainParser = try! DomainParser(rulesData: rulesData)

        // Sanity: a normally-valid host is not valid under this custom rule set.
        XCTAssertNil(customDomainParser.parse(host: "google.fr")?.domain)

        measure {
            for _ in 0...10 {
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.ky")?.domain, "domain.any.ky")
                XCTAssertEqual(customDomainParser.parse(host: "except.ky")?.domain, "except.ky")
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.tz")?.domain, "domain.any.tz")
                XCTAssertEqual(customDomainParser.parse(host: "except.tz")?.domain, "except.tz")
                XCTAssertEqual(customDomainParser.parse(host: "domain.any.nf")?.domain, "domain.any.nf")
                XCTAssertEqual(customDomainParser.parse(host: "except.nf")?.domain, "except.nf")
            }
        }
    }
}
