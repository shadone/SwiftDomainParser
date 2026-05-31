import Foundation
import Testing
@testable import PublicSuffixListKit

@Suite("Conveniences")
struct ConvenienceTests {
    func make() throws -> PublicSuffixList {
        try PublicSuffixList.loading(from: Data("""
        # ===ICANN===
        com
        co.uk
        # ===PRIVATE===
        github.io
        """.utf8))
    }

    @Test func accessors() throws {
        let psl = try make()
        #expect(psl.registrableDomain(of: "api.github.com") == "github.com")
        #expect(psl.publicSuffix(of: "api.github.com") == "com")
        #expect(psl.isPublicSuffix("co.uk"))
        #expect(!psl.isPublicSuffix("example.co.uk"))
    }

    @Test func urlOverload() throws {
        let psl = try make()
        let url = URL(string: "https://api.github.com/x")!
        #expect(psl.lookup(url)?.registrableDomain == "github.com")
        #expect(psl.lookup(URL(string: "file:///tmp/x")!) == nil) // no host
    }

    @Test func sameRegistrableDomain() throws {
        let psl = try make()
        #expect(psl.haveSameRegistrableDomain("a.github.com", "b.github.com"))
        #expect(!psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io"))
        #expect(!psl.haveSameRegistrableDomain("co.uk", "co.uk")) // bare suffix
        #expect(psl.haveSameRegistrableDomain("github.com", "github.com.")) // trailing dot
    }
}
