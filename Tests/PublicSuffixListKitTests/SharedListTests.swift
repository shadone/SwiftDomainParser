import Testing
@testable import PublicSuffixListKit

@Suite("shared")
struct SharedListTests {
    /// `shared` is a value type decoded from the bundled blob; there is no
    /// actor identity to assert anymore. Just sanity-check it loaded a real
    /// list and answers lookups.
    @Test func sharedLoadsBundledList() {
        let psl = PublicSuffixList.shared
        #expect(psl.metadata.icannRuleCount > 1000)
        #expect(psl.metadata.privateRuleCount > 0)
        #expect(psl.lookup("api.github.com")?.registrableDomain == "github.com")
    }
}
