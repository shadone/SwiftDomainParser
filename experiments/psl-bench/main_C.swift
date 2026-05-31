import Foundation
let iters = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 3000
let t0 = nowNanos()
let index = buildRichIndexChunked()
let buildNs = nowNanos() - t0
let (ns, cs) = runLookups(index, iterations: iters)
report(variant: "C_rich_literal", buildNs: buildNs, lookupNs: ns, checksum: cs)
