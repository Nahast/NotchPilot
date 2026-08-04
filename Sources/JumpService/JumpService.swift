import AgentCore
import AppKit
import Foundation
import OSLog

/// Session → focus (design spec §3):
/// - Sessions living in the Claude desktop app: deep-link straight to the
///   conversation (`claude://local_sessions/<id>`) and bring the app forward.
/// - Terminal sessions: AppleScript, find the iTerm2 window/tab whose session
///   path matches the project path; select and activate it.
/// - Fallback: activate whichever host app is running.
public final class JumpService {
    /// This module has no dependency on the app target's Log namespace,
    /// so it carries its own Logger under the shared subsystem.
    private static let logger = Logger(subsystem: "com.rjouffret.NotchPilot", category: "jump")

    public init() {}

    /// Deep link into the Claude desktop app for a specific conversation.
    public static func desktopDeepLink(for session: AgentSession) -> URL? {
        guard let desktopId = session.desktopSessionId, !desktopId.isEmpty else { return nil }
        return URL(string: "claude://local_sessions/\(desktopId)")
    }

    /// Must be called on the main thread (NSAppleScript requirement).
    public func jump(to session: AgentSession) {
        switch session.agentKind {
        case .claude:
            jumpToClaude(session)
        case .codex:
            // Codex runs in VS Code or a terminal.
            jumpToTerminalOrApp(session, appBundleIdPrefixes: ["com.microsoft.VSCode"])
        case .cursor:
            jumpToTerminalOrApp(session, appBundleIdPrefixes: ["com.todesktop.230313mzl4w4u92"])
        case .other:
            jumpToTerminalOrApp(session, appBundleIdPrefixes: [])
        }
    }

    private func jumpToClaude(_ session: AgentSession) {
        if let deepLink = Self.desktopDeepLink(for: session) {
            NSWorkspace.shared.open(deepLink)
            activate(bundleIdentifierPrefix: "com.anthropic.claudefordesktop")
            return
        }
        if isRunning(bundleIdentifierPrefix: "com.googlecode.iterm2") {
            if jumpToITerm2(projectPath: session.projectPath) { return }
        }
        if activateClaudeCodeDesktopApp() { return }
        // Last resort: bring iTerm2 forward even if we couldn't find the tab.
        activate(bundleIdentifierPrefix: "com.googlecode.iterm2")
    }

    private func jumpToTerminalOrApp(_ session: AgentSession, appBundleIdPrefixes: [String]) {
        if isRunning(bundleIdentifierPrefix: "com.googlecode.iterm2") {
            if jumpToITerm2(projectPath: session.projectPath) { return }
        }
        for prefix in appBundleIdPrefixes where activate(bundleIdentifierPrefix: prefix) {
            return
        }
        activate(bundleIdentifierPrefix: "com.googlecode.iterm2")
    }

    // MARK: iTerm2

    /// Returns true when a matching window/tab was found and focused.
    /// The first run triggers the macOS automation permission prompt; a denial
    /// surfaces as an AppleScript error and we fall through to activation.
    private func jumpToITerm2(projectPath: String) -> Bool {
        // A path that can't be represented safely (control characters) skips
        // the script entirely — the caller's activation fallback still runs.
        guard let escapedPath = Self.appleScriptStringLiteral(projectPath) else {
            return false
        }
        let source = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionPath to ""
                        try
                            tell s
                                set sessionPath to (variable named "path")
                            end tell
                        end try
                        if sessionPath is "\(escapedPath)" or sessionPath starts with "\(escapedPath)/" then
                            select s
                            select t
                            select w
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not-found"
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // The AppleScript error dictionary can quote the script source,
            // which embeds the project path — keep the default redaction.
            Self.logger.error("iTerm2 jump failed: \(String(describing: errorInfo))")
            return false
        }
        return result.stringValue == "found"
    }

    /// The path as an AppleScript double-quoted-literal body, or nil when it
    /// contains control characters — those can't be escaped into AppleScript
    /// source (a newline in a filename is legal on macOS, if exotic) and a
    /// broken script string is worse than skipping the tab search.
    static func appleScriptStringLiteral(_ string: String) -> String? {
        guard !string.unicodeScalars.contains(where: {
            $0.value < 0x20 || $0.value == 0x7F
        }) else { return nil }
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: Claude Code desktop app

    private static let claudeCodeBundleIdentifiers = [
        "com.anthropic.claudefordesktop",
        "com.anthropic.claude-code",
        "com.anthropic.claudecode",
    ]

    private func activateClaudeCodeDesktopApp() -> Bool {
        let running = NSWorkspace.shared.runningApplications
        let app = running.first { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return Self.claudeCodeBundleIdentifiers.contains(bundleId)
        } ?? running.first { $0.localizedName == "Claude Code" }
        guard let app else { return false }
        return app.activate(options: [])
    }

    // MARK: Helpers

    private func isRunning(bundleIdentifierPrefix prefix: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.hasPrefix(prefix) == true
        }
    }

    @discardableResult
    private func activate(bundleIdentifierPrefix prefix: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.hasPrefix(prefix) == true
        }) else { return false }
        return app.activate(options: [])
    }
}
