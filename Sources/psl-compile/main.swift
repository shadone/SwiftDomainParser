//
//  psl-compile
//  PublicSuffixListKit
//
//  Compiles the bundled public_suffix_list.dat into the precompiled binary
//  blob public_suffix_list.bin that PublicSuffixList.shared decodes at runtime.
//
//  Reuses the library's real RulesParser, so the bytes are produced by the
//  exact code that interprets .dat everywhere else — drift is impossible by
//  construction.
//
//  Run from anywhere:
//      swift run psl-compile
//

import Foundation
import PublicSuffixListKit

// Resolve paths relative to this source file, not the working directory, so the
// tool can be invoked from anywhere.
let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()    // Sources/psl-compile/
    .deletingLastPathComponent()    // Sources/
    .deletingLastPathComponent()    // repo root
    .appendingPathComponent("Sources/PublicSuffixListKit/Resources")
    .standardizedFileURL
let datURL = resources.appendingPathComponent("public_suffix_list.dat")
let binURL = resources.appendingPathComponent("public_suffix_list.bin")

do {
    let data = try Data(contentsOf: datURL)
    let parsed = try RulesParser.parse(data)
    let blob = PSLBinaryFormat.encode(parsed)
    try blob.write(to: binURL)
    print("""
        psl-compile: \(parsed.rules.count) rules \
        (\(parsed.metadata.icannRuleCount) ICANN + \(parsed.metadata.privateRuleCount) private) \
        -> \(blob.count) bytes at \(binURL.lastPathComponent)
        """)
} catch {
    FileHandle.standardError.write(Data("psl-compile error: \(error)\n".utf8))
    exit(1)
}
