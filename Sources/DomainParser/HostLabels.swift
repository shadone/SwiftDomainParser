import Foundation

/// A host split into labels in two parallel forms:
///
/// - `original`  — lowercased, original ACE/Unicode form. Used to construct
///   the output so callers get back the suffix and registrable domain in
///   the same form they passed in.
/// - `normalized` — lowercased, with any `xn--`-prefixed labels Punycode-
///   decoded to their Unicode form. Used to match against the bundled PSL
///   rules, which are themselves in Unicode form.
///
/// Following the PSL test-suite convention, case is normalized but the
/// ACE-vs-Unicode form of each label is preserved in the output:
/// `xn--85x722f.com.cn` → registrableDomain `xn--85x722f.com.cn`,
/// `食狮.com.cn` → registrableDomain `食狮.com.cn`.
struct HostLabels {
    let original: [String]
    let normalized: [String]

    init(host: String) {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        self.original = parts
        self.normalized = parts.map { label in
            guard label.hasPrefix("xn--"),
                  let decoded = Punycode.decode(String(label.dropFirst(4))) else {
                return label
            }
            return decoded
        }
    }

    var isEmpty: Bool { original.isEmpty }
}
