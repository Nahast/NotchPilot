import Foundation

/// Classifies a Claude model id so the notch can hide conversations that
/// aren't real, user-facing model turns:
/// - **synthetic** — client-generated assistant messages (`<synthetic>`):
///   interruptions, API-error placeholders, quota notices. Not completions.
/// - **unlisted** — a concrete model id that maps to no family we recognize.
///
/// Empty/absent ids are neither (a brand-new session hasn't produced a model
/// yet), so they stay visible.
public enum AgentModelClassifier {
    /// Known Claude model families. Extend as new families ship.
    public static let knownFamilies = ["opus", "sonnet", "haiku", "fable"]

    public static func isSynthetic(_ modelId: String?) -> Bool {
        guard let id = normalized(modelId) else { return false }
        return id.contains("synthetic") || (id.hasPrefix("<") && id.hasSuffix(">"))
    }

    /// A recognized model that maps to a known family.
    public static func isListed(_ modelId: String?) -> Bool {
        guard let id = normalized(modelId), !isSynthetic(modelId) else { return false }
        return knownFamilies.contains { id.contains($0) }
    }

    /// True when a model id is present but synthetic or unlisted — i.e. the
    /// conversation should be hidden. Absent/empty ids return false.
    public static func isSyntheticOrUnlisted(_ modelId: String?) -> Bool {
        guard normalized(modelId) != nil else { return false }
        return isSynthetic(modelId) || !isListed(modelId)
    }

    private static func normalized(_ modelId: String?) -> String? {
        guard let id = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !id.isEmpty else { return nil }
        return id
    }
}
