/// Errors thrown while loading a custom Public Suffix List via
/// ``PublicSuffixList/loading(from:)``. Queries never throw, and the bundled
/// ``PublicSuffixList/shared`` list never throws (a corrupt bundled blob is a
/// package defect and traps instead).
public enum PublicSuffixListError: Error {
    /// The list bytes were not valid UTF-8, or a rule had an unsupported shape.
    case ruleParsingError(message: String)
}
