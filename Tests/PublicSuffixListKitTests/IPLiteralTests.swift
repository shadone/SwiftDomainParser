import Testing
@testable import PublicSuffixListKit

@Suite("IPLiteral")
struct IPLiteralTests {
    @Test(arguments: [
        "192.168.0.1", "8.8.8.8", "0.0.0.0", "255.255.255.255",
        "::1", "fe80::1", "2001:db8::ff00:42:8329",
        "[::1]", "[fe80::1]",
    ])
    func detectsIPLiterals(_ s: String) {
        #expect(IPLiteral.isIPLiteral(s))
    }

    @Test(arguments: [
        "example.com", "co.uk", "a.b.c", "1.2.3", // 3 octets: not IPv4
        "999.1.1.1",                              // out of range
        "localhost", "xn--85x722f.com.cn",
    ])
    func rejectsHostnames(_ s: String) {
        #expect(!IPLiteral.isIPLiteral(s))
    }
}
