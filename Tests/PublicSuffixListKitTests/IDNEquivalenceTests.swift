import Testing
@testable import PublicSuffixListKit

/// A domain must look up and compare identically regardless of whether it is
/// expressed as an A-label (xn--) or a U-label (Unicode), or a mix of the two.
@Suite("IDN A-label / U-label equivalence")
struct IDNEquivalenceTests {
    // 食狮 == xn--85x722f, 公司 == xn--55qx5d (see PunycodeTests / test_psl.txt).

    @Test func sameRegistrableDomainAcrossForms() async throws {
        let psl = try await PublicSuffixList.bundled()
        #expect(psl.haveSameRegistrableDomain("食狮.公司.cn",
                                              "xn--85x722f.xn--55qx5d.cn"))
        // Mixed forms, and a differing subdomain that must not affect equality.
        #expect(psl.haveSameRegistrableDomain("www.食狮.公司.cn",
                                              "食狮.xn--55qx5d.cn"))
    }

    @Test func differentDomainsStayDistinctAcrossForms() async throws {
        let psl = try await PublicSuffixList.bundled()
        #expect(!psl.haveSameRegistrableDomain("食狮.公司.cn",
                                               "xn--85x722f.com.cn"))
    }

    @Test func canonicalFieldsAgreeButDisplayPreservesInput() async throws {
        let psl = try await PublicSuffixList.bundled()
        let u = try #require(psl.lookup("食狮.公司.cn"))
        let a = try #require(psl.lookup("xn--85x722f.xn--55qx5d.cn"))

        #expect(u.canonicalRegistrableDomain == a.canonicalRegistrableDomain)
        #expect(u.canonicalRegistrableDomain == "食狮.公司.cn")
        #expect(u.canonicalPublicSuffix == a.canonicalPublicSuffix)
        #expect(u.canonicalPublicSuffix == "公司.cn")

        // Display output still round-trips the caller's form.
        #expect(u.registrableDomain == "食狮.公司.cn")
        #expect(a.registrableDomain == "xn--85x722f.xn--55qx5d.cn")
    }

    @Test func canonicalDropsTrailingDot() async throws {
        let psl = try await PublicSuffixList.bundled()
        let info = try #require(psl.lookup("食狮.公司.cn."))
        #expect(info.canonicalRegistrableDomain == "食狮.公司.cn")
    }

    @Test func uts46MappedFormsMatch() async throws {
        let psl = try await PublicSuffixList.bundled()
        // FULLWIDTH "ＥＸＡＭＰＬＥ" maps to "example"; soft hyphen is ignored.
        #expect(psl.haveSameRegistrableDomain(
            "\u{FF25}\u{FF38}\u{FF21}\u{FF2D}\u{FF30}\u{FF2C}\u{FF25}.com",
            "exa\u{00AD}mple.com"))
        #expect(psl.registrableDomain(of: "\u{FF21}\u{FF22}.com",
                                      scope: .all)?.isEmpty == false)
    }
}
