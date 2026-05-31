// Generator: reads the real .dat and emits every variant's artifact.
//   swiftc -O core.swift gen.swift -o build/gen && build/gen <dat> <outdir>

import Foundation

let datPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let text = try! String(contentsOfFile: datPath, encoding: .utf8)
let (rules, date, rev) = parseDat(text)
FileHandle.standardError.write(Data("parsed \(rules.count) rules\n".utf8))

func write(_ name: String, _ s: String) {
    try! s.write(toFile: "\(outDir)/\(name)", atomically: true, encoding: .utf8)
}
func writeBytes(_ name: String, _ b: [UInt8]) {
    try! Data(b).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

// --- A / B source: the flat binary blob ---
let blob = BinaryFormat.encode(rules, date: date, rev: rev)
writeBytes("blob.bin", blob)

// --- B: base64 StaticString embedded in source ---
let b64 = Data(blob).base64EncodedString()
write("gen_B.swift", "let pslBase64: StaticString = \"\(b64)\"\n")

// --- group rules by lastLabel for the rich-literal variants ---
var buckets: [String: [Rule]] = [:]
for r in rules where !r.lastLabel.isEmpty { buckets[r.lastLabel, default: []].append(r) }

func ruleLit(_ r: Rule) -> String {
    let ls = r.labels.map { l -> String in
        switch l { case .wildcard: return ".wildcard"; case .literal(let s): return ".literal(\"\(s)\")" }
    }.joined(separator: ", ")
    let sec = r.section == .icann ? ".icann" : ".privateSection"
    return "Rule(labels: [\(ls)], isException: \(r.isException), section: \(sec), lastLabel: \"\(r.lastLabel)\")"
}

// --- C single: one giant [String:[Rule]] literal (compile-pathology test) ---
do {
    var s = "let richBuckets: [String: [Rule]] = [\n"
    for (k, rs) in buckets {
        s += "  \"\(k)\": [\(rs.map(ruleLit).joined(separator: ", "))],\n"
    }
    s += "]\nfunc buildRichIndex() -> RuleIndex { RuleIndex(buckets: richBuckets) }\n"
    write("gen_C_single.swift", s)
}

// --- C chunked: same data split across functions so it actually compiles ---
do {
    let keys = Array(buckets.keys)
    let perChunk = 64
    var s = ""
    var chunkIdx = 0
    var i = 0
    var calls: [String] = []
    while i < keys.count {
        s += "private func c\(chunkIdx)(_ d: inout [String: [Rule]]) {\n"
        for k in keys[i..<min(i + perChunk, keys.count)] {
            s += "  d[\"\(k)\"] = [\(buckets[k]!.map(ruleLit).joined(separator: ", "))]\n"
        }
        s += "}\n"
        calls.append("c\(chunkIdx)(&d)")
        chunkIdx += 1
        i += perChunk
    }
    s += "func buildRichIndexChunked() -> RuleIndex {\n  var d: [String: [Rule]] = [:]; d.reserveCapacity(2048)\n"
    s += calls.map { "  \($0)" }.joined(separator: "\n")
    s += "\n  return RuleIndex(buckets: d)\n}\n"
    write("gen_C_chunked.swift", s)
}

// --- D: flat primitive arrays (tokens as Strings, reparsed at first use) ---
do {
    let icann = rules.filter { $0.section == .icann }
    let priv = rules.filter { $0.section == .privateSection }
    func tok(_ r: Rule) -> String {
        let body = r.labels.map { l -> String in
            switch l { case .wildcard: return "*"; case .literal(let s): return s }
        }.joined(separator: ".")
        return (r.isException ? "!" : "") + body
    }
    let all = icann + priv
    var s = "let flatICANNCount = \(icann.count)\n"
    s += "let flatTokens: [String] = [\n"
    s += all.map { "  \"\(tok($0))\"" }.joined(separator: ",\n")
    s += "\n]\n"
    s += """
    func buildFlatIndex() -> RuleIndex {
      var rules: [Rule] = []; rules.reserveCapacity(flatTokens.count)
      for (i, t) in flatTokens.enumerated() {
        rules.append(Rule(token: Substring(t), section: i < flatICANNCount ? .icann : .privateSection))
      }
      return RuleIndex(rules: rules)
    }

    """
    write("gen_D.swift", s)
}

// --- E: sorted, range-indexed blob for direct byte queries (no RuleIndex) ---
do {
    // directory sorted by lastLabel; rules packed in a separate region.
    let sortedKeys = buckets.keys.sorted()
    var rulesRegion: [UInt8] = []
    var dir: [(label: String, off: UInt32, count: UInt16)] = []
    for k in sortedKeys {
        let rs = buckets[k]!
        let off = UInt32(rulesRegion.count)
        for r in rs {
            var flags: UInt8 = 0
            if r.isException { flags |= 1 }
            if r.section == .privateSection { flags |= 2 }
            rulesRegion.append(flags)
            rulesRegion.append(UInt8(r.labels.count))
            for l in r.labels {
                switch l {
                case .wildcard: rulesRegion.append(1)
                case .literal(let s):
                    rulesRegion.append(0)
                    let b = Array(s.utf8); rulesRegion.append(UInt8(b.count)); rulesRegion.append(contentsOf: b)
                }
            }
        }
        dir.append((k, off, UInt16(rs.count)))
    }
    // Build the directory-entries region first so we can compute an offset
    // table (enables in-place binary search with zero upfront build).
    var entries: [UInt8] = []
    var entryOffsets: [UInt32] = []
    for e in dir {
        entryOffsets.append(UInt32(entries.count))
        let lb = Array(e.label.utf8)
        entries.append(UInt8(lb.count)); entries.append(contentsOf: lb)
        appendU32(&entries, e.off)
        entries.append(UInt8(e.count & 0xff)); entries.append(UInt8((e.count >> 8) & 0xff))
    }
    var out: [UInt8] = []
    out.append(contentsOf: Array("PSLD".utf8))
    out.append(1)
    appendU32(&out, UInt32(dir.count))
    for o in entryOffsets { appendU32(&out, o) }   // u32[dirCount] offset table
    appendU32(&out, UInt32(entries.count))
    out.append(contentsOf: entries)
    appendU32(&out, UInt32(rulesRegion.count))
    out.append(contentsOf: rulesRegion)
    writeBytes("blob_direct.bin", out)
}

FileHandle.standardError.write(Data("wrote artifacts to \(outDir)\n".utf8))
