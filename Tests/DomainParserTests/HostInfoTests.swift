import Testing
@testable import DomainParser

@Suite("HostInfo")
struct HostInfoTests {
    @Test func barePublicSuffixFlags() {
        let info = HostInfo(publicSuffix: "co.uk", registrableDomain: nil,
                            subdomain: nil, source: .icann)
        #expect(info.isPublicSuffix)
        #expect(!info.isRegistrableDomain)
    }

    @Test func apexDomainFlags() {
        let info = HostInfo(publicSuffix: "com", registrableDomain: "github.com",
                            subdomain: nil, source: .icann)
        #expect(!info.isPublicSuffix)
        #expect(info.isRegistrableDomain)
    }

    @Test func subdomainIsNotRegistrableDomain() {
        let info = HostInfo(publicSuffix: "com", registrableDomain: "github.com",
                            subdomain: "api", source: .icann)
        #expect(!info.isRegistrableDomain)
    }
}
