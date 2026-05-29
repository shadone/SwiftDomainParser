//
//  UpdateIDNAMapping.swift
//  PublicSuffixListKit
//
//  Fetches unicode.org/Public/idna/latest/IdnaMappingTable.txt and compiles it
//  into a compact binary table bundled at
//  Sources/PublicSuffixListKit/Resources/idna_mapping.bin, used by the UTS-46
//  mapping step.
//
//  Binary format (little-endian):
//      magic        "IM46"           (4 bytes)
//      versionLen   UInt8            length of the Unicode version string
//      version      UTF-8 bytes      e.g. "17.0.0"
//      count        UInt32           number of records
//      records[]    sorted by start ascending:
//          start    UInt32
//          end      UInt32
//          status   UInt8            0 valid, 1 ignored, 2 mapped, 3 deviation,
//                                    4 disallowed, 5 disallowed_STD3_valid,
//                                    6 disallowed_STD3_mapped
//          mapLen   UInt8            number of mapping scalars
//          mapping  UInt32 × mapLen
//
//  Run from anywhere:
//      swift script/UpdateIDNAMapping.swift
//

import Foundation

enum IDNAUpdateError: Error {
    case notUTF8Convertible
    case unexpectedContent(reason: String)
    case badLine(String)
}

let statusCode: [String: UInt8] = [
    "valid": 0, "ignored": 1, "mapped": 2, "deviation": 3,
    "disallowed": 4, "disallowed_STD3_valid": 5, "disallowed_STD3_mapped": 6,
]

struct Record { let start: UInt32; let end: UInt32; let status: UInt8; let mapping: [UInt32] }

func parseHex(_ s: Substring) -> UInt32? { UInt32(s.trimmingCharacters(in: .whitespaces), radix: 16) }

func parse(_ text: String) throws -> (version: String, records: [Record]) {
    var version = "unknown"
    var records: [Record] = []

    for rawLine in text.components(separatedBy: .newlines) {
        if rawLine.hasPrefix("#") {
            if let r = rawLine.range(of: "# Version: ") {
                version = String(rawLine[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            continue
        }
        let body = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }

        let fields = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { throw IDNAUpdateError.badLine(rawLine) }

        // Range: "XXXX" or "XXXX..YYYY".
        let rangeField = fields[0].trimmingCharacters(in: .whitespaces)
        let bounds = rangeField.components(separatedBy: "..")
        guard let start = UInt32(bounds[0], radix: 16),
              let end = UInt32(bounds.count > 1 ? bounds[1] : bounds[0], radix: 16) else {
            throw IDNAUpdateError.badLine(rawLine)
        }

        let statusName = fields[1].trimmingCharacters(in: .whitespaces)
        guard let status = statusCode[statusName] else { throw IDNAUpdateError.badLine(rawLine) }

        var mapping: [UInt32] = []
        if (status == 2 || status == 3 || status == 6), fields.count >= 3 {
            mapping = fields[2].split(separator: " ").compactMap { parseHex($0) }
        }
        records.append(Record(start: start, end: end, status: status, mapping: mapping))
    }
    records.sort { $0.start < $1.start }
    return (version, records)
}

func serialize(version: String, records: [Record]) -> Data {
    var out = Data()
    func appendU32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { out.append(contentsOf: $0) } }

    out.append(contentsOf: Array("IM46".utf8))
    let ver = Array(version.utf8)
    out.append(UInt8(ver.count))
    out.append(contentsOf: ver)
    appendU32(UInt32(records.count))
    for r in records {
        appendU32(r.start)
        appendU32(r.end)
        out.append(r.status)
        out.append(UInt8(r.mapping.count))
        for m in r.mapping { appendU32(m) }
    }
    return out
}

let sourceURL = URL(string: "https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt")!

let targetURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()    // script/
    .deletingLastPathComponent()    // repo root
    .appendingPathComponent("Sources/PublicSuffixListKit/Resources/idna_mapping.bin")
    .standardizedFileURL

do {
    let (raw, _) = try await URLSession.shared.data(from: sourceURL)
    guard let text = String(data: raw, encoding: .utf8) else {
        throw IDNAUpdateError.notUTF8Convertible
    }
    guard text.contains("# IdnaMappingTable.txt") else {
        throw IDNAUpdateError.unexpectedContent(
            reason: "downloaded body is not IdnaMappingTable.txt - aborting")
    }

    let (version, records) = try parse(text)
    guard records.count > 1000 else {
        throw IDNAUpdateError.unexpectedContent(reason: "only \(records.count) records parsed")
    }
    let data = serialize(version: version, records: records)
    try data.write(to: targetURL)
    print("Unicode \(version): wrote \(records.count) records, \(data.count) bytes to \(targetURL.lastPathComponent)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
