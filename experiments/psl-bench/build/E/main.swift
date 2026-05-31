import Foundation

/// Queries the sorted/range-indexed blob directly. No RuleIndex, no [Rule].
struct DirectDB {
    let b: [UInt8]
    let dirCount: Int
    let tableBase: Int     // start of u32[dirCount] offset table
    let entriesBase: Int
    let rulesBase: Int

    init(_ bytes: [UInt8]) {
        b = bytes
        dirCount = Int(DirectDB.u32(b, 5))
        tableBase = 9
        let entriesLenPos = tableBase + dirCount * 4
        entriesBase = entriesLenPos + 4
        let entriesLen = Int(DirectDB.u32(b, entriesLenPos))
        let rulesLenPos = entriesBase + entriesLen
        rulesBase = rulesLenPos + 4
    }

    static func u32(_ b: [UInt8], _ p: Int) -> UInt32 {
        UInt32(b[p]) | UInt32(b[p+1]) << 8 | UInt32(b[p+2]) << 16 | UInt32(b[p+3]) << 24
    }
    static func u16(_ b: [UInt8], _ p: Int) -> Int { Int(b[p]) | Int(b[p+1]) << 8 }

    /// Compare the label at entry `i` against `key` (UTF-8 bytes). -1/0/1.
    private func cmpEntryLabel(_ i: Int, _ key: [UInt8]) -> Int {
        let entryOff = entriesBase + Int(DirectDB.u32(b, tableBase + i * 4))
        let len = Int(b[entryOff])
        let start = entryOff + 1
        let n = min(len, key.count)
        var j = 0
        while j < n {
            let x = b[start + j], y = key[j]
            if x != y { return x < y ? -1 : 1 }
            j += 1
        }
        if len == key.count { return 0 }
        return len < key.count ? -1 : 1
    }

    private func bucket(for key: [UInt8]) -> (off: Int, count: Int)? {
        var lo = 0, hi = dirCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let c = cmpEntryLabel(mid, key)
            if c == 0 {
                let entryOff = entriesBase + Int(DirectDB.u32(b, tableBase + mid * 4))
                let len = Int(b[entryOff])
                let rulesOff = Int(DirectDB.u32(b, entryOff + 1 + len))
                let cnt = DirectDB.u16(b, entryOff + 1 + len + 4)
                return (rulesBase + rulesOff, cnt)
            }
            if c < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    func registrableLabelCount(for host: [String]) -> Int? {
        guard let last = host.last else { return nil }
        guard let bk = bucket(for: Array(last.utf8)) else { return host.count >= 2 ? 2 : nil }
        var p = bk.off
        var bestLabels = -1, bestException = false, found = false
        for _ in 0..<bk.count {
            let flags = b[p]; p += 1
            let lc = Int(b[p]); p += 1
            // parse + match from the right without building Strings
            var ruleBytes: [(wild: Bool, s: Int, n: Int)] = []
            ruleBytes.reserveCapacity(lc)
            for _ in 0..<lc {
                if b[p] == 1 { p += 1; ruleBytes.append((true, 0, 0)) }
                else { let n = Int(b[p+1]); ruleBytes.append((false, p+2, n)); p += 2 + n }
            }
            // matches?
            var ok = host.count >= lc
            if ok {
                for off in 1...lc {
                    let rl = ruleBytes[lc - off]
                    if rl.wild { continue }
                    let hb = Array(host[host.count - off].utf8)
                    if hb.count != rl.n { ok = false; break }
                    var k = 0
                    while k < rl.n { if b[rl.s + k] != hb[k] { ok = false; break }; k += 1 }
                    if !ok { break }
                }
            }
            if ok {
                let exc = flags & 1 != 0
                let higher: Bool
                if !found { higher = true }
                else if exc != bestException { higher = exc }
                else { higher = lc > bestLabels }
                if higher { bestLabels = lc; bestException = exc; found = true }
            }
        }
        guard found else { return host.count >= 2 ? 2 : nil }
        let suffix = bestException ? bestLabels - 1 : bestLabels
        guard suffix >= 1, suffix <= host.count else { return nil }
        return suffix + 1 <= host.count ? suffix + 1 : nil
    }
}

let iters = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 3000
let blobPath = CommandLine.arguments[1]
let t0 = nowNanos()
let bytes = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: blobPath)))
let db = DirectDB(bytes)
let buildNs = nowNanos() - t0
var checksum = 0
let l0 = nowNanos()
for _ in 0..<iters { for h in benchHosts { checksum &+= db.registrableLabelCount(for: h) ?? 0 } }
let lookupNs = Double(nowNanos() - l0) / Double(iters * benchHosts.count)
report(variant: "E_bytes_direct", buildNs: buildNs, lookupNs: lookupNs, checksum: checksum)
