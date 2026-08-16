import Foundation

/// Plain-text diagnostics for "Copy diagnostics" in Settings. Pure formatting
/// over an input snapshot so the privacy guarantee is testable: sessions come
/// in whole, but only aggregate counts ever reach the output — this function
/// is the single choke point where names, paths, and titles are dropped.
///
/// The report never leaves the Mac on its own; the user pastes it into a bug
/// report themselves (PRODUCT.md: no telemetry, ever).
public enum DiagnosticsReport {
    /// One monitored agent's connection toggle, by display name.
    public struct AgentFlag {
        public var name: String
        public var enabled: Bool

        public init(name: String, enabled: Bool) {
            self.name = name
            self.enabled = enabled
        }
    }

    /// Everything the report needs, gathered by the caller (AppKit-side)
    /// so rendering stays a pure function.
    public struct Input {
        public var appVersion: String
        public var appBuild: String
        public var macOSVersion: String
        public var hooksInstalled: Bool
        public var helperPresent: Bool
        /// The helper's fixed install location — the one path the report is
        /// allowed to contain, and only once `homeDirectory` has been folded
        /// back to `~`, because the username is the sole varying part of it.
        public var helperInstallPath: String
        /// The user's home directory, used solely to redact it out of
        /// `helperInstallPath`. A macOS short name is very often the user's
        /// real name, so emitting it would break the report's own header.
        public var homeDirectory: String
        public var agents: [AgentFlag]
        public var sessions: [AgentSession]
        public var isLimitedMode: Bool
        /// Active setup problems, keyed by source (mirrors AppDelegate).
        /// Values are already user-facing sentences, so they are safe to emit.
        public var degradations: [String: String]
        public var usageEnabled: Bool
        public var usageSignedOut: Bool

        public init(
            appVersion: String,
            appBuild: String,
            macOSVersion: String,
            hooksInstalled: Bool,
            helperPresent: Bool,
            helperInstallPath: String,
            homeDirectory: String,
            agents: [AgentFlag],
            sessions: [AgentSession],
            isLimitedMode: Bool,
            degradations: [String: String],
            usageEnabled: Bool,
            usageSignedOut: Bool
        ) {
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.macOSVersion = macOSVersion
            self.hooksInstalled = hooksInstalled
            self.helperPresent = helperPresent
            self.helperInstallPath = helperInstallPath
            self.homeDirectory = homeDirectory
            self.agents = agents
            self.sessions = sessions
            self.isLimitedMode = isLimitedMode
            self.degradations = degradations
            self.usageEnabled = usageEnabled
            self.usageSignedOut = usageSignedOut
        }
    }

    public static func render(_ input: Input) -> String {
        var lines: [String] = []
        // The disclaimer leads so whoever receives a pasted report sees the
        // scope before any data.
        lines.append("NotchPilot diagnostics")
        lines.append("This report contains no personal data: no file contents, no session")
        lines.append("titles, no project paths, no tokens. It is generated locally and")
        lines.append("stays on this Mac unless you paste it somewhere yourself.")
        lines.append("")
        lines.append("App: NotchPilot \(input.appVersion) (build \(input.appBuild))")
        lines.append("macOS: \(input.macOSVersion)")
        lines.append("Hooks installed: \(yesNo(input.hooksInstalled))")
        let helperPath = redactingHome(input.helperInstallPath, home: input.homeDirectory)
        lines.append("Helper: \(input.helperPresent ? "present" : "MISSING") at \(helperPath)")
        lines.append("Agents:")
        for agent in input.agents {
            lines.append("  \(agent.name): \(agent.enabled ? "connected" : "disconnected")")
        }
        lines.append(contentsOf: sessionLines(input.sessions))
        lines.append("Limited mode: \(yesNo(input.isLimitedMode))")
        if input.degradations.isEmpty {
            lines.append("Degradations: none")
        } else {
            lines.append("Degradations:")
            // Sorted keys make two reports diffable against each other.
            for key in input.degradations.keys.sorted() {
                lines.append("  \(key): \(input.degradations[key]!)")
            }
        }
        if input.usageEnabled {
            lines.append("Usage gauge: enabled, signed \(input.usageSignedOut ? "out" : "in")")
        } else {
            lines.append("Usage gauge: disabled")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Aggregate counts only — never a session's name, path, or activity.
    private static func sessionLines(_ sessions: [AgentSession]) -> [String] {
        guard !sessions.isEmpty else { return ["Sessions: none"] }
        var lines = ["Sessions: \(sessions.count)"]
        // Kinds without sessions stay out — zero rows would bury the signal.
        for kind in AgentKind.allCases {
            let ofKind = sessions.filter { $0.agentKind == kind }
            guard !ofKind.isEmpty else { continue }
            func count(_ status: AgentStatus) -> Int {
                ofKind.filter { $0.status == status }.count
            }
            lines.append("  \(kind.rawValue): \(ofKind.count) (working \(count(.working)), "
                + "needs-attention \(count(.needsAttention)), idle \(count(.idle)))")
        }
        return lines
    }

    /// Folds the home directory back to `~`. Paths elsewhere carry no
    /// username and are left alone — the location is the diagnostic value.
    private static func redactingHome(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
