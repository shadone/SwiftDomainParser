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
    case unexpectedContent(reason: String)
}

/// Section marker the official PSL file contains at the top of the ICANN
/// section. Used as a low-effort sanity check that the download is actually a
/// PSL and not (e.g.) an HTML error page from a CDN or a hijack.
let pslICANNMarker = "===BEGIN ICANN DOMAINS==="

struct PublicSuffixListNormalizer {
    let data: Data
    let sourceDate: String          // ISO-8601, passed in

    private func isComment(_ line: String) -> Bool { line.hasPrefix("//") }

    func normalize() throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PSLUpdateError.notUTF8Convertible
        }

        var icann: [String] = []
        var priv: [String] = []
        var inPrivate = false

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("===BEGIN PRIVATE DOMAINS===") { inPrivate = true; continue }
            if trimmed.contains("===BEGIN ICANN DOMAINS===") { inPrivate = false; continue }
            if trimmed.isEmpty || isComment(trimmed) { continue }
            guard let token = trimmed.components(separatedBy: .whitespaces).first,
                  !token.isEmpty else { continue }
            if inPrivate { priv.append(token) } else { icann.append(token) }
        }

        // Higher-label-count rules first within each section (priority hint).
        let byLabels: (String, String) -> Bool = {
            $0.split(separator: ".").count > $1.split(separator: ".").count
        }
        icann.sort(by: byLabels)
        priv.sort(by: byLabels)

        var out = "# source-date: \(sourceDate)\n"
        out += "# source-revision:\n"          // upstream .dat has no revision; left blank
        out += "# ===ICANN===\n"
        out += icann.joined(separator: "\n")
        out += "\n# ===PRIVATE===\n"
        out += priv.joined(separator: "\n")
        out += "\n"
        return Data(out.utf8)
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

    // Sanity-check before normalizing: if the server returned an HTML error
    // page or something hijacked the response, the official ICANN section
    // marker will be missing. Refuse to overwrite the bundled file in that
    // case rather than silently committing garbage.
    guard let text = String(data: raw, encoding: .utf8) else {
        throw PSLUpdateError.notUTF8Convertible
    }
    guard text.contains(pslICANNMarker) else {
        throw PSLUpdateError.unexpectedContent(
            reason: "downloaded body does not contain \"\(pslICANNMarker)\" - aborting refresh")
    }

    let today = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt,
        formatOptions: [.withFullDate])
    let normalized = try PublicSuffixListNormalizer(data: raw, sourceDate: today).normalize()
    try normalized.write(to: targetURL)
    print("Wrote \(normalized.count) bytes to \(targetURL.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
