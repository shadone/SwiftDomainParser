import Foundation
let t0 = nowNanos()
let index = buildRichIndex()
let buildNs = nowNanos() - t0
let (ns, cs) = runLookups(index, iterations: 1000)
report(variant: "C_single_literal", buildNs: buildNs, lookupNs: ns, checksum: cs)
