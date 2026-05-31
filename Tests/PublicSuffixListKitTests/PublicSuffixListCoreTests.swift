import Foundation
import Testing
@testable import PublicSuffixListKit

@Suite("PublicSuffixList core")
struct PublicSuffixListCoreTests {
    static let listText = """
    # source-date: 2026-05-28
    # ===ICANN===
    com
    co.uk
    jp
    *.yokohama.jp
    *.ck
    !www.ck
    # ===PRIVATE===
    github.io
    """

    func make() throws -> PublicSuffixList {
        try PublicSuffixList.loading(from: Data(Self.listText.utf8))
    }

    @Test func apexAndSubdomain() throws {
        let psl = try make()
        let info = try #require(psl.lookup("api.github.com"))
        #expect(info.publicSuffix == "com")
        #expect(info.registrableDomain == "github.com")
        #expect(info.subdomain == "api")
        #expect(info.source == .icann)
    }

    @Test func privateRuleIsolatesTenants() throws {
        let psl = try make()
        let a = try #require(psl.lookup("alice.github.io"))
        #expect(a.publicSuffix == "github.io")
        #expect(a.registrableDomain == "alice.github.io")
        #expect(a.source == .privateRule)
    }

    @Test func icannOnlyCollapsesPrivate() throws {
        let psl = try make()
        let a = try #require(psl.lookup("alice.github.io", scope: .icannOnly))
        #expect(a.publicSuffix == "io")
        #expect(a.registrableDomain == "github.io")
        #expect(a.source == .defaultRule)
    }

    @Test func bareSuffixHasNoRegistrableDomain() throws {
        let psl = try make()
        let info = try #require(psl.lookup("co.uk"))
        #expect(info.publicSuffix == "co.uk")
        #expect(info.registrableDomain == nil)
        #expect(info.isPublicSuffix)
    }

    @Test func issue694() throws {
        let psl = try make()
        let info = try #require(psl.lookup("yokohama.jp"))
        #expect(info.publicSuffix == "jp")
        #expect(info.registrableDomain == "yokohama.jp")
        #expect(info.source == .icann)
    }

    @Test func trailingDotPreserved() throws {
        let psl = try make()
        let info = try #require(psl.lookup("api.github.com."))
        #expect(info.publicSuffix == "com.")
        #expect(info.registrableDomain == "github.com.")
        #expect(info.subdomain == "api")
    }

    @Test func nonHostnamesReturnNil() throws {
        let psl = try make()
        #expect(psl.lookup("") == nil)
        #expect(psl.lookup("192.168.0.1") == nil)
        #expect(psl.lookup(".com") == nil)
    }

    @Test func metadataExposed() throws {
        let psl = try make()
        #expect(psl.metadata.sourceDate == "2026-05-28")
        #expect(psl.metadata.privateRuleCount == 1)
    }
}
