import Foundation

/// Maps Claude model identifiers to context-window sizes (tokens).
/// Unknown models assume 200k per the design spec, so format drift degrades
/// to a slightly-wrong gauge instead of no gauge.
public enum ModelContextTable {
    public static let defaultContextWindow = 200_000

    /// Prefix-matched overrides for models whose window differs from the default.
    /// Checked before the default; longest prefix wins.
    private static let overrides: [(prefix: String, window: Int)] = [
        // 1M-context beta variants are marked with a [1m] suffix in model ids;
        // handled separately below. Explicit prefixes here for models with
        // non-200k windows:
        ("claude-3-haiku", 200_000),
        ("claude-3-opus", 200_000),
        ("claude-3-5", 200_000),
        ("claude-3-7", 200_000),
    ]

    public static func contextWindow(for model: String?) -> Int {
        guard let model, !model.isEmpty else { return defaultContextWindow }
        let normalized = model.lowercased()
        // Long-context variants ("[1m]" suffix or explicit -1m marker).
        if normalized.contains("[1m]") || normalized.hasSuffix("-1m") {
            return 1_000_000
        }
        var best: (length: Int, window: Int)?
        for (prefix, window) in overrides where normalized.hasPrefix(prefix) {
            if best == nil || prefix.count > best!.length {
                best = (prefix.count, window)
            }
        }
        return best?.window ?? defaultContextWindow
    }

    /// Evidence-corrected window: a session cannot hold more tokens than its
    /// window, so observed usage beyond the assumed size proves a 1M-context
    /// session whose transcript id doesn't carry the [1m] marker (Claude Code
    /// records e.g. "claude-fable-5" for 1M sessions too). Without this, such
    /// sessions clamp to a misleading red 100%.
    public static func contextWindow(for model: String?, observedUsedTokens: Int?) -> Int {
        let assumed = contextWindow(for: model)
        if let used = observedUsedTokens, used > assumed {
            return 1_000_000
        }
        return assumed
    }
}
