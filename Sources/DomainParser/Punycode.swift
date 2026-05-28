import Foundation

/// Minimal RFC 3492 Punycode decoder.
///
/// Only the decode direction is implemented - the parser needs it to convert
/// ACE-encoded labels (the part after `xn--`) to their Unicode form so they
/// can be compared against the Unicode-form rules in the bundled PSL.
///
/// Returns `nil` on malformed input (overflow, invalid digit, surrogate
/// codepoint, etc.) so callers can fall back to treating the label opaquely.
enum Punycode {

    // RFC 3492 section 5 - bootstring parameters for Punycode.
    private static let base = 36
    private static let tmin = 1
    private static let tmax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN: UInt32 = 128

    /// Decode a Punycode string (without the `xn--` ACE prefix) to Unicode.
    static func decode(_ encoded: String) -> String? {
        var output: [Unicode.Scalar] = []
        var n: UInt32 = initialN
        var i = 0
        var bias = initialBias

        let scalars = Array(encoded.unicodeScalars)

        // The basic-codepoint section ends at the LAST '-' in the input. If
        // there is no '-', there are no basic codepoints. (RFC 3492 §6.2.)
        var basicCount = 0
        for j in (0..<scalars.count).reversed() where scalars[j].value == 0x2D {
            basicCount = j
            break
        }

        for j in 0..<basicCount {
            let s = scalars[j]
            guard s.value < 0x80 else { return nil }
            output.append(s)
        }

        // If we consumed any basic codepoints, also consume the delimiter.
        var pos = basicCount > 0 ? basicCount + 1 : 0

        while pos < scalars.count {
            let oldi = i
            var w = 1
            var k = base

            // Decode one generalized variable-length integer into `i`.
            while true {
                guard pos < scalars.count else { return nil }
                let c = scalars[pos]
                pos += 1

                guard let digit = digitValue(of: c) else { return nil }

                let (delta, deltaOverflow) = digit.multipliedReportingOverflow(by: w)
                guard !deltaOverflow else { return nil }
                let (newI, addOverflow) = i.addingReportingOverflow(delta)
                guard !addOverflow else { return nil }
                i = newI

                let t: Int
                if k <= bias {
                    t = tmin
                } else if k >= bias + tmax {
                    t = tmax
                } else {
                    t = k - bias
                }

                if digit < t { break }

                let (newW, wOverflow) = w.multipliedReportingOverflow(by: base - t)
                guard !wOverflow else { return nil }
                w = newW

                k += base
            }

            let outLen = output.count + 1
            bias = adapt(delta: i - oldi, numPoints: outLen, firstTime: oldi == 0)

            // n += i / outLen
            let increment = i / outLen
            guard let incrementU32 = UInt32(exactly: increment) else { return nil }
            let (newN, nOverflow) = n.addingReportingOverflow(incrementU32)
            guard !nOverflow else { return nil }
            n = newN

            i = i % outLen

            guard let scalar = Unicode.Scalar(n) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }

        return String(String.UnicodeScalarView(output))
    }

    /// Map a Punycode digit codepoint to its 0–35 numeric value.
    /// 'a'..'z' → 0..25 (case-insensitive), '0'..'9' → 26..35.
    private static func digitValue(of scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x30...0x39: return Int(scalar.value - 0x30) + 26
        case 0x61...0x7A: return Int(scalar.value - 0x61)
        case 0x41...0x5A: return Int(scalar.value - 0x41)
        default:          return nil
        }
    }

    /// RFC 3492 §6.1 bias-adaptation function.
    private static func adapt(delta: Int, numPoints: Int, firstTime: Bool) -> Int {
        var d = firstTime ? delta / damp : delta / 2
        d += d / numPoints
        var k = 0
        let upperBound = ((base - tmin) * tmax) / 2
        while d > upperBound {
            d /= (base - tmin)
            k += base
        }
        return k + (((base - tmin + 1) * d) / (d + skew))
    }
}
