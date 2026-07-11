import Foundation

/// Tokens consumed today across all sessions (input + cache-creation +
/// output; cache reads excluded). Computed locally from transcripts.
public struct TokenTally: Equatable, Sendable {
    public var tokens: Int
    /// True when backfill was truncated (very large pre-existing transcripts)
    /// and the number is a lower bound.
    public var isApproximate: Bool

    public init(tokens: Int, isApproximate: Bool = false) {
        self.tokens = tokens
        self.isApproximate = isApproximate
    }

    /// "215k", "1.2M", "950" — with "≈" prefix when approximate.
    public var formatted: String {
        let number: String
        switch tokens {
        case ..<1_000:
            number = "\(tokens)"
        case ..<1_000_000:
            number = "\(tokens / 1_000)k"
        default:
            number = String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        return isApproximate ? "≈\(number)" : number
    }
}
