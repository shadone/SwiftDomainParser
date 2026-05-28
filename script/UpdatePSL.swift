//
//  UpdatePSL.swift
//  DomainParser
//
//  Fetches publicsuffix.org/list/public_suffix_list.dat, normalizes it
//  (strips comments / whitespace, sorts by descending label count so
//  highest-priority rules come first), and writes the result over the
//  bundled copy at Sources/DomainParser/Resources/public_suffix_list.dat.
//
//  Run from anywhere:
//      swift script/UpdatePSL.swift
//

import Foundation

enum PSLUpdateError: Error {
    case notUTF8Convertible
}

struct PublicSuffixListNormalizer {
    let data: Data

    /// A valid line is a non-empty, non-comment line.
    private func isLineValid(_ line: String) -> Bool {
        !line.isEmpty && !line.starts(with: "//")
    }

    func normalize() throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PSLUpdateError.notUTF8Convertible
        }

        // From publicsuffix.org/list/: each line is only read up to the first
        // whitespace; entire lines can also be commented using //.
        var validLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { $0.components(separatedBy: .whitespaces).first }
            .filter(isLineValid)

        // Rules with more labels are higher priority; put them first.
        validLines.sort { $0.split(separator: ".").count > $1.split(separator: ".").count }

        return Data(validLines.joined(separator: "\n").utf8)
    }
}

let sourceURL = URL(string: "https://publicsuffix.org/list/public_suffix_list.dat")!

// Target resolved relative to this script, not the current working directory,
// so the script can be invoked from anywhere.
let targetURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()    // script/
    .deletingLastPathComponent()    // repo root
    .appendingPathComponent("Sources/DomainParser/Resources/public_suffix_list.dat")
    .standardizedFileURL

do {
    let (raw, _) = try await URLSession.shared.data(from: sourceURL)
    let normalized = try PublicSuffixListNormalizer(data: raw).normalize()
    try normalized.write(to: targetURL)
    print("Wrote \(normalized.count) bytes to \(targetURL.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
