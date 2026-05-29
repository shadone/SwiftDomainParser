import Foundation

/// Errors thrown while loading a Public Suffix List. Queries never throw.
public enum PublicSuffixListError: Error {
    /// The list bytes were not valid UTF-8, or a rule had an unsupported shape.
    case ruleParsingError(message: String)
    /// The bundled `public_suffix_list.dat` resource was not found in
    /// `Bundle.module`. In a shipping build this is a packaging bug.
    case missingBundledResource
    /// Reading the bundled resource off disk failed (wrapped Foundation error).
    case bundleLoadFailed(underlying: any Error)
}
