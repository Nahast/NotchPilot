import OSLog

/// One Logger per functional area, all under the app's subsystem so
/// `log stream --predicate 'subsystem == "com.rjouffret.NotchPilot"'` shows
/// everything at once. Dynamic strings stay redacted in release builds by
/// default; only values needed for self-diagnosis and safe to expose (error
/// descriptions, OSStatus codes, counts) are marked `.public`. Paths, session
/// names, and anything credential-adjacent keep the default redaction.
enum Log {
    static let subsystem = "com.rjouffret.NotchPilot"

    /// App lifecycle and setup (helper deploy, launch-at-login, Sparkle).
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Hook install/uninstall for Claude Code and Cursor.
    static let hooks = Logger(subsystem: subsystem, category: "hooks")
    /// Rate-limit usage fetching (Keychain read, HTTP fetch, backoff).
    static let usage = Logger(subsystem: subsystem, category: "usage")
}
