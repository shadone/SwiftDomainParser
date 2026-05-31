import Foundation
let iters = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 3000
let blobPath = CommandLine.arguments[1]
let t0 = nowNanos()
let bytes = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: blobPath)))
let index = RuleIndex(rules: BinaryFormat.decode(bytes))
let buildNs = nowNanos() - t0
let (ns, cs) = runLookups(index, iterations: iters)
report(variant: "A_bin_resource", buildNs: buildNs, lookupNs: ns, checksum: cs)
