import Testing
@testable import PublicSuffixListKit

@Suite("shared()")
struct SharedListTests {
    @Test func returnsSameUnderlyingListTwice() async throws {
        let a = try await PublicSuffixList.shared()
        let b = try await PublicSuffixList.shared()
        #expect(a.metadata == b.metadata)
        #expect(a.lookup("api.github.com")?.registrableDomain
                == b.lookup("api.github.com")?.registrableDomain)
    }
}
