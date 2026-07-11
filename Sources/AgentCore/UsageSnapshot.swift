import Foundation

/// One rate-limit window from Anthropic's usage endpoint
/// (5-hour session window, 7-day all-models, 7-day per-model, …).
public struct UsageWindow: Identifiable, Equatable, Sendable {
    /// Raw key from the API ("five_hour", "seven_day", "seven_day_opus").
    public var key: String
    /// Short display label ("5h", "7d", "7d Opus").
    public var label: String
    /// Fraction of the window consumed (0…1).
    public var usedFraction: Double
    /// When the window resets.
    public var resetsAt: Date?

    public var id: String { key }

    public var remainingFraction: Double {
        min(1, max(0, 1 - usedFraction))
    }

    public init(key: String, label: String, usedFraction: Double, resetsAt: Date?) {
        self.key = key
        self.label = label
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
    }
}

/// Parsed usage response. The endpoint's shape has grown keys over time
/// (per-model windows like "seven_day_opus"), so parsing is dynamic: any
/// top-level object carrying a numeric `utilization` is a window.
public struct UsageSnapshot: Equatable, Sendable {
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(windows: [UsageWindow], fetchedAt: Date) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public static func parse(from data: Data, fetchedAt: Date = Date()) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }

        var windows: [UsageWindow] = []
        for (key, value) in dictionary {
            guard let window = value as? [String: Any],
                  let utilization = window["utilization"] as? Double
            else { continue }
            // Windows the API itself marks disabled are not real limits.
            if window["is_enabled"] as? Bool == false { continue }
            // Extra-usage / credit entries only matter once something is
            // actually consumed — an untouched "extra usage: 100% left" row
            // is noise for users who haven't bought or used credits.
            let isExtraUsage = key.contains("extra") || key.contains("credit") || key.contains("overage")
            if isExtraUsage, utilization <= 0 { continue }
            let resetsAt = (window["resets_at"] as? String).flatMap(parseDate)
            windows.append(UsageWindow(
                key: key,
                label: label(forKey: key),
                usedFraction: min(1, max(0, utilization / 100.0)),
                resetsAt: resetsAt
            ))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { rank($0.key) < rank($1.key) }
        return UsageSnapshot(windows: windows, fetchedAt: fetchedAt)
    }

    /// "five_hour" → "5-hour limit", "seven_day" → "Weekly · all models",
    /// "seven_day_opus" → "Weekly · Opus"; unknown keys degrade to a
    /// readable form instead of disappearing.
    public static func label(forKey key: String) -> String {
        func titled(_ rest: some StringProtocol) -> String {
            rest.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        if key == "five_hour" { return "5-hour limit" }
        if key == "seven_day" { return "Weekly · all models" }
        if key.hasPrefix("seven_day_") {
            return "Weekly · \(titled(key.dropFirst("seven_day_".count)))"
        }
        if key.hasPrefix("five_hour_") {
            return "5-hour · \(titled(key.dropFirst("five_hour_".count)))"
        }
        let readable = titled(key)
        return readable.isEmpty ? key : readable
    }

    private static func rank(_ key: String) -> String {
        // five_hour first, then seven_day, then per-model windows.
        if key == "five_hour" { return "0" }
        if key == "seven_day" { return "1" }
        return "2\(key)"
    }

    private static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
