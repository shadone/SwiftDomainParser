import Foundation
let iters = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 3000
let t0 = nowNanos()
let s = pslBase64.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
let bytes = [UInt8](Data(base64Encoded: s)!)
let index = RuleIndex(rules: BinaryFormat.decode(bytes))
let buildNs = nowNanos() - t0
let (ns, cs) = runLookups(index, iterations: iters)
report(variant: "B_staticstring_b64", buildNs: buildNs, lookupNs: ns, checksum: cs)
