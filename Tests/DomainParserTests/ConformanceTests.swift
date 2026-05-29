import Foundation
import Testing
@testable import DomainParser

@Suite("Official PSL conformance")
struct ConformanceTests {
    struct Case: Sendable { let host: String; let expected: String? }

    static let cases: [Case] = {
        guard let url = Bundle.module.url(forResource: "test_psl", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Case] = []
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("checkPublicSuffix(") else { continue }
            let inner = t.dropFirst("checkPublicSuffix(".count).dropLast(2)
            let args = inner.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            func unquote(_ s: String) -> String? {
                if s == "null" { return nil }
                return String(s.dropFirst().dropLast())
            }
            guard args.count == 2, let host = unquote(args[0]) else { continue }
            out.append(Case(host: host, expected: unquote(args[1])))
        }
        return out
    }()

    @Test func suiteIsLoaded() {
        #expect(Self.cases.count > 50)
    }

    @Test func conformance() async throws {
        let psl = try await PublicSuffixList.bundled()
        for c in Self.cases {
            let got = psl.lookup(c.host)?.registrableDomain
            #expect(got == c.expected, "host \(c.host): got \(String(describing: got)), expected \(String(describing: c.expected))")
        }
    }
}
