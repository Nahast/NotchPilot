import AgentCore
import AppKit
import Foundation

/// Session → focus (design spec §3):
/// - iTerm2: AppleScript, find the window/tab whose session path matches the
///   project path; select and activate it.
/// - Claude Code desktop app: activate the app (best effort).
/// - Fallback: activate whichever of the two is running.
public final class JumpService {
    public init() {}

    /// Must be called on the main thread (NSAppleScript requirement).
    public func jump(to session: AgentSession) {
        let projectPath = session.projectPath
        if isRunning(bundleIdentifierPrefix: "com.googlecode.iterm2") {
            if jumpToITerm2(projectPath: projectPath) { return }
        }
        if activateClaudeCodeDesktopApp() { return }
        // Last resort: bring iTerm2 forward even if we couldn't find the tab.
        activate(bundleIdentifierPrefix: "com.googlecode.iterm2")
    }

    // MARK: iTerm2

    /// Returns true when a matching window/tab was found and focused.
    /// The first run triggers the macOS automation permission prompt; a denial
    /// surfaces as an AppleScript error and we fall through to activation.
    private func jumpToITerm2(projectPath: String) -> Bool {
        let escapedPath = projectPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
            NSLog("NotchPilot: iTerm2 jump failed: %@", errorInfo)
            return false
        }
        return result.stringValue == "found"
    }

    // MARK: Claude Code desktop app

    private static let claudeCodeBundleIdentifiers = [
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
