import Foundation

/// "claude-opus-4-8" → "Opus 4.8", "claude-fable-5" → "Fable 5",
/// "claude-sonnet-4-5[1m]" → "Sonnet 4.5 1M".
public enum ModelDisplayName {
    public static func displayName(for modelId: String?) -> String? {
        guard var id = modelId?.lowercased(), !id.isEmpty else { return nil }

        var suffix = ""
        if id.hasSuffix("[1m]") {
            suffix = " 1M"
            id = String(id.dropLast(4))
        }
        if id.hasPrefix("claude-") {
            id = String(id.dropFirst("claude-".count))
        }

        var parts = id.split(separator: "-").map(String.init)
        // Drop a trailing date stamp ("20250514").
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        // Legacy ids lead with the version ("3-5-haiku"): move name first.
        if let nameIndex = parts.firstIndex(where: { $0.first?.isLetter == true }), nameIndex > 0 {
            let name = parts.remove(at: nameIndex)
            parts.insert(name, at: 0)
        }
        guard let name = parts.first else { return nil }

        let version = parts.dropFirst().joined(separator: ".")
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        return (version.isEmpty ? capitalized : "\(capitalized) \(version)") + suffix
    }
}
