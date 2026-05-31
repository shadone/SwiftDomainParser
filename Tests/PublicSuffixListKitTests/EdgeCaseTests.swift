import Foundation
import Testing
@testable import PublicSuffixListKit

@Suite("Edge cases")
struct EdgeCaseTests {
    func psl() -> PublicSuffixList { PublicSuffixList.shared }

    @Test func issue694_yokohamaAndKobe() throws {
        let psl = psl()
        // Literal-algorithm reading: too-short host under *.yokohama.jp falls
        // back to base rule jp.
        #expect(psl.lookup("yokohama.jp")?.registrableDomain == "yokohama.jp")
        #expect(psl.lookup("yokohama.jp")?.publicSuffix == "jp")
        #expect(psl.lookup("kobe.jp")?.registrableDomain == "kobe.jp")
    }

    @Test func wildcardFamily_mm() throws {
        let psl = psl()  // *.mm is a real rule
        #expect(psl.lookup("mm")?.registrableDomain == nil)
        #expect(psl.lookup("c.mm")?.registrableDomain == nil)
        #expect(psl.lookup("b.c.mm")?.registrableDomain == "b.c.mm")
    }

    @Test func privateTenantsAreDistinct() throws {
        let psl = psl()  // github.io is a real PRIVATE rule
        #expect(!psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io"))
        // ICANN-only collapses them under the io registry.
        #expect(psl.haveSameRegistrableDomain("alice.github.io", "bob.github.io",
                                              scope: .icannOnly))
    }

    @Test func defaultRuleForUnlistedTLD() throws {
        let psl = psl()
        // Use a guaranteed-unlisted TLD so this never collides with a real PSL entry.
        let info = try #require(psl.lookup("app.mycorp.invalidtldxyz"))
        #expect(info.publicSuffix == "invalidtldxyz")
        #expect(info.registrableDomain == "mycorp.invalidtldxyz")
        #expect(info.source == .defaultRule)
    }

    @Test func trailingDotPreservedAndCanonicalizedForComparison() throws {
        let psl = psl()
        #expect(psl.lookup("github.com.")?.registrableDomain == "github.com.")
        #expect(psl.haveSameRegistrableDomain("github.com", "github.com."))
    }

    @Test(arguments: ["", ".", ".com", "foo..com", "192.168.0.1", "[::1]"])
    func nonHostnames(_ s: String) throws {
        let psl = psl()
        #expect(psl.lookup(s) == nil)
    }
}
