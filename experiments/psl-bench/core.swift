// Shared core for the PSL load-strategy benchmark.
// Compiled into every variant binary so the in-memory structure + lookup are
// identical across variants; only the *source of bytes* and *build strategy*
// differ.

import Foundation

// MARK: - Model (ported from the library, trimmed for the bench)

enum Section: UInt8 { case icann = 0, privateSection = 1 }

enum RuleLabel: Equatable {
    case literal(String)
    case wildcard
}

struct Rule {
    let labels: [RuleLabel]
    let isException: Bool
    let section: Section
    let lastLabel: String

    init(labels: [RuleLabel], isException: Bool, section: Section, lastLabel: String) {
        self.labels = labels
        self.isException = isException
        self.section = section
        self.lastLabel = lastLabel
    }

    /// Parse one normalized rule token, e.g. "co.uk", "*.ck", "!www.ck".
    init(token: Substring, section: Section) {
        let isException = token.first == "!"
        let body = isException ? token.dropFirst() : token
        let parts = body.split(separator: ".").map { p -> RuleLabel in
            p == "*" ? .wildcard : .literal(String(p))
        }
        self.labels = parts
        self.isException = isException
        self.section = section
        if case .literal(let s)? = parts.last { self.lastLabel = s } else { self.lastLabel = "" }
    }

    var labelCount: Int { labels.count }
    var isWildcard: Bool { labels.contains(.wildcard) }

    func matches(_ host: [String]) -> Bool {
        guard host.count >= labels.count else { return false }
        for off in 1...labels.count {
            switch labels[labels.count - off] {
            case .wildcard: continue
            case .literal(let s): if s != host[host.count - off] { return false }
            }
        }
        return true
    }
}

struct RuleIndex {
    let rulesByLastLabel: [String: [Rule]]

    init(rules: [Rule]) {
        var byLast: [String: [Rule]] = [:]
        byLast.reserveCapacity(2048)
        for r in rules where !r.lastLabel.isEmpty {
            byLast[r.lastLabel, default: []].append(r)
        }
        self.rulesByLastLabel = byLast
    }

    init(buckets: [String: [Rule]]) { self.rulesByLastLabel = buckets }

    /// Registrable-domain label count for a host (the bench "answer"), or nil.
    func registrableLabelCount(for host: [String]) -> Int? {
        guard let last = host.last, let bucket = rulesByLastLabel[last] else {
            return defaultAnswer(host)
        }
        var best: Rule?
        for r in bucket where r.matches(host) {
            if isHigher(r, than: best) { best = r }
        }
        guard let w = best else { return defaultAnswer(host) }
        let suffix = w.isException ? w.labelCount - 1 : w.labelCount
        guard suffix >= 1, suffix <= host.count else { return nil }
        return suffix + 1 <= host.count ? suffix + 1 : nil
    }

    private func defaultAnswer(_ host: [String]) -> Int? {
        // implicit "*": suffix = 1 label
        host.count >= 2 ? 2 : nil
    }

    private func isHigher(_ c: Rule, than cur: Rule?) -> Bool {
        guard let cur else { return true }
        if c.isException != cur.isException { return c.isException }
        return c.labelCount > cur.labelCount
    }
}

// MARK: - .dat parsing (shared by the generator)

func parseDat(_ text: String) -> (rules: [Rule], date: String, rev: String) {
    var date = "", rev = ""
    var section: Section = .icann
    var rules: [Rule] = []
    rules.reserveCapacity(11000)
    for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = raw.drop(while: \.isWhitespace)
        if line.isEmpty { continue }
        if line.hasPrefix("#") {
            let h = line.dropFirst().drop(while: { $0 == " " })
            if h.hasPrefix("===ICANN===") { section = .icann }
            else if h.hasPrefix("===PRIVATE===") { section = .privateSection }
            else if h.hasPrefix("source-date:") { date = String(h.dropFirst("source-date:".count).trimmingCharacters(in: .whitespaces)) }
            else if h.hasPrefix("source-revision:") { rev = String(h.dropFirst("source-revision:".count).trimmingCharacters(in: .whitespaces)) }
            continue
        }
        if line.hasPrefix("//") { continue }
        let token = line.prefix { !$0.isWhitespace }
        if token.isEmpty { continue }
        rules.append(Rule(token: token, section: section))
    }
    return (rules, date, rev)
}

// MARK: - Binary format (variant A resource, variant B in-binary base64)

enum BinaryFormat {
    static func encode(_ rules: [Rule], date: String, rev: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(160_000)
        out.append(contentsOf: Array("PSL1".utf8))
        out.append(1) // format version
        appendStr(&out, date); appendStr(&out, rev)
        let icann = rules.filter { $0.section == .icann }.count
        appendU32(&out, UInt32(icann))
        appendU32(&out, UInt32(rules.count - icann))
        appendU32(&out, UInt32(rules.count))
        for r in rules {
            var flags: UInt8 = 0
            if r.isException { flags |= 1 }
            if r.section == .privateSection { flags |= 2 }
            out.append(flags)
            out.append(UInt8(r.labels.count))
            for l in r.labels {
                switch l {
                case .wildcard: out.append(1)
                case .literal(let s):
                    out.append(0)
                    let b = Array(s.utf8); out.append(UInt8(b.count)); out.append(contentsOf: b)
                }
            }
        }
        return out
    }

    static func decode(_ bytes: [UInt8]) -> [Rule] {
        var p = 0
        func u8() -> UInt8 { defer { p += 1 }; return bytes[p] }
        func u32() -> UInt32 {
            let v = UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24
            p += 4; return v
        }
        func str() -> String { let n = Int(u8()); let s = String(decoding: bytes[p..<p+n], as: UTF8.self); p += n; return s }
        p = 4 // magic
        _ = u8() // version
        _ = str(); _ = str() // date, rev
        _ = u32(); _ = u32() // counts
        let count = Int(u32())
        var rules: [Rule] = []; rules.reserveCapacity(count)
        for _ in 0..<count {
            let flags = u8()
            let lc = Int(u8())
            var labels: [RuleLabel] = []; labels.reserveCapacity(lc)
            var last = ""
            for _ in 0..<lc {
                if u8() == 1 { labels.append(.wildcard) }
                else { let s = str(); labels.append(.literal(s)); last = s }
            }
            rules.append(Rule(labels: labels, isException: flags & 1 != 0,
                              section: flags & 2 != 0 ? .privateSection : .icann, lastLabel: last))
        }
        return rules
    }
}

func appendU32(_ a: inout [UInt8], _ v: UInt32) {
    a.append(UInt8(v & 0xff)); a.append(UInt8((v >> 8) & 0xff))
    a.append(UInt8((v >> 16) & 0xff)); a.append(UInt8((v >> 24) & 0xff))
}
func appendStr(_ a: inout [UInt8], _ s: String) { let b = Array(s.utf8); a.append(UInt8(b.count)); a.append(contentsOf: b) }

// MARK: - Bench harness

@inline(never)
func nowNanos() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

/// Representative host set (already lowercased + label-split).
let benchHosts: [[String]] = {
    let raw = [
        "app.alice.github.io", "auth.example.com", "sub.example.co.uk",
        "foo.bbc.co.uk", "www.ck", "sub.example.gov.ck", "a.b.c.example.com",
        "mail.google.com", "login.live.com", "shop.amazon.co.jp",
        "x.y.z.co", "deep.sub.domain.example.org", "test.nhs.uk",
        "node.nt.edu.au", "user.gitlab.io", "api.example.io",
        "cdn.jsdelivr.net", "raw.githubusercontent.com", "host.example.museum",
        "a.example.pvt.k12.ma.us",
    ]
    return raw.map { $0.split(separator: ".").map(String.init) }
}()

func runLookups(_ index: RuleIndex, iterations: Int) -> (ns: Double, checksum: Int) {
    var checksum = 0
    let t0 = nowNanos()
    for _ in 0..<iterations {
        for h in benchHosts { checksum &+= index.registrableLabelCount(for: h) ?? 0 }
    }
    let dt = Double(nowNanos() - t0)
    let total = iterations * benchHosts.count
    return (dt / Double(total), checksum)
}

func report(variant: String, buildNs: UInt64, lookupNs: Double, checksum: Int) {
    let line = String(format: "RESULT\t%@\tbuild_ms=%.3f\tlookup_ns=%.1f\tchecksum=%d",
                      variant, Double(buildNs) / 1_000_000, lookupNs, checksum)
    print(line)
}
