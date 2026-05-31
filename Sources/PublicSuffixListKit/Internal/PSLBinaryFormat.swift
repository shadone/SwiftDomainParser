package import Foundation

/// Precompiled binary representation of a parsed Public Suffix List.
///
/// Mirrors `IDNAMapping`'s style: explicit little-endian, hand-rolled byte
/// reader, magic header — portable across the library's Linux/Windows targets.
/// The bundled blob is produced by the `psl-compile` tool (which calls the real
/// `RulesParser`) and decoded once, synchronously, behind `PublicSuffixList.shared`.
///
/// Layout:
/// ```
/// "PSL1"                              4-byte magic
/// formatVersion                      u8
/// sourceDate      u8 len + UTF-8      (len 0 = absent)
/// sourceRevision  u8 len + UTF-8      (len 0 = absent)
/// icannRuleCount                     u32
/// privateRuleCount                   u32
/// ruleCount                          u32
/// × ruleCount:
///    flags       u8     bit0 isException, bit1 section == private
///    labelCount  u8
///    × labelCount:
///       kind u8 (0 literal, 1 wildcard); if literal: u8 len + UTF-8
/// ```
/// v1 stores labels inline. A string-interning table is a noted future lever
/// (PSL's label vocabulary is far smaller than 10K) but is not needed now.
enum PSLBinaryFormat {
    static let magic = Array("PSL1".utf8)
    static let formatVersion: UInt8 = 1

    private enum Flag {
        static let isException: UInt8 = 1 << 0
        static let privateSection: UInt8 = 1 << 1
    }

    private enum LabelKind: UInt8 {
        case literal = 0
        case wildcard = 1
    }

    // MARK: Encode

    /// Serialize a parsed list to the binary blob. Used by the generator target.
    package static func encode(_ parsed: ParsedList) -> Data {
        var out = Data()

        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        func appendString(_ s: String?) {
            let bytes = Array((s ?? "").utf8)
            out.append(UInt8(truncatingIfNeeded: bytes.count))
            out.append(contentsOf: bytes)
        }

        out.append(contentsOf: magic)
        out.append(formatVersion)
        appendString(parsed.metadata.sourceDate)
        appendString(parsed.metadata.sourceRevision)
        appendU32(UInt32(parsed.metadata.icannRuleCount))
        appendU32(UInt32(parsed.metadata.privateRuleCount))
        appendU32(UInt32(parsed.rules.count))

        for rule in parsed.rules {
            var flags: UInt8 = 0
            if rule.isException { flags |= Flag.isException }
            if rule.section == .privateSection { flags |= Flag.privateSection }
            out.append(flags)
            out.append(UInt8(truncatingIfNeeded: rule.labels.count))
            for label in rule.labels {
                switch label {
                case .wildcard:
                    out.append(LabelKind.wildcard.rawValue)
                case .literal(let s):
                    out.append(LabelKind.literal.rawValue)
                    let bytes = Array(s.utf8)
                    out.append(UInt8(truncatingIfNeeded: bytes.count))
                    out.append(contentsOf: bytes)
                }
            }
        }
        return out
    }

    // MARK: Decode

    /// Rebuild a parsed list from the blob. Returns `nil` on any structural
    /// problem (bad magic, truncation, unknown enum tags); `PublicSuffixList.shared`
    /// traps on `nil` since the bundled blob is a build-time artifact we generate.
    static func decode(_ data: Data) -> ParsedList? {
        let bytes = [UInt8](data)
        var p = 0

        func u8() -> UInt8? {
            guard p < bytes.count else { return nil }
            defer { p += 1 }
            return bytes[p]
        }
        func u32() -> UInt32? {
            guard p + 4 <= bytes.count else { return nil }
            let v = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8
                | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
            p += 4
            return v
        }
        func string() -> String? {
            guard let len = u8(), p + Int(len) <= bytes.count else { return nil }
            let s = String(decoding: bytes[p..<(p + Int(len))], as: UTF8.self)
            p += Int(len)
            return s
        }

        guard bytes.count >= magic.count, Array(bytes[0..<magic.count]) == magic else { return nil }
        p = magic.count
        guard let version = u8(), version == formatVersion else { return nil }

        guard let rawDate = string(), let rawRevision = string(),
              let icannRuleCount = u32(), let privateRuleCount = u32(),
              let ruleCount = u32() else { return nil }

        var rules: [Rule] = []
        rules.reserveCapacity(Int(ruleCount))
        for _ in 0..<ruleCount {
            guard let flags = u8(), let labelCount = u8() else { return nil }
            var labels: [RuleLabel] = []
            labels.reserveCapacity(Int(labelCount))
            for _ in 0..<labelCount {
                guard let rawKind = u8(), let kind = LabelKind(rawValue: rawKind) else { return nil }
                switch kind {
                case .wildcard:
                    labels.append(.wildcard)
                case .literal:
                    guard let s = string() else { return nil }
                    labels.append(.literal(s))
                }
            }
            rules.append(Rule(
                labels: labels,
                isException: flags & Flag.isException != 0,
                section: flags & Flag.privateSection != 0 ? .privateSection : .icann))
        }

        let index = RuleIndex(rules: rules)
        let metadata = ListMetadata(
            sourceDate: rawDate.isEmpty ? nil : rawDate,
            sourceRevision: rawRevision.isEmpty ? nil : rawRevision,
            icannRuleCount: Int(icannRuleCount),
            privateRuleCount: Int(privateRuleCount))
        return ParsedList(rules: rules, index: index, metadata: metadata)
    }
}
