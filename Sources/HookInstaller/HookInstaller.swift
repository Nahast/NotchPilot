import Foundation

/// Manages NotchPilot's Claude Code hooks in `~/.claude/settings.json`.
///
/// Safety rules (design spec §5):
/// - parse-validate first; if the file is malformed, refuse to write
/// - timestamped backup before every modifying write
/// - merge without touching existing hooks; uninstall removes only ours
public struct HookInstaller {
    public enum InstallerError: Error, LocalizedError, Equatable {
        /// settings.json exists but is not valid JSON / not the expected shape.
        /// We refuse to write rather than risk breaking the user's setup.
        case malformedSettings

        public var errorDescription: String? {
            switch self {
            case .malformedSettings:
                return "~/.claude/settings.json could not be parsed. NotchPilot will not modify it; running in limited mode instead."
            }
        }
    }

    /// The four lifecycle events NotchPilot registers (design spec §4).
    public static let managedEvents = ["SessionStart", "Notification", "Stop", "SessionEnd"]

    public let settingsURL: URL
    /// Absolute path of the installed notchpilot-hook helper binary.
    public let helperPath: String

    public init(settingsURL: URL, helperPath: String) {
        self.settingsURL = settingsURL
        self.helperPath = helperPath
    }

    // MARK: Public API

    /// True when every managed event already invokes our helper.
    public func isInstalled() -> Bool {
        guard let settings = try? readSettings() else { return false }
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return Self.managedEvents.allSatisfy { event in
            containsOurCommand(hooks[event])
        }
    }

    /// Idempotently merges our hooks. Returns the backup URL when the file
    /// was modified (nil when nothing needed to change).
    @discardableResult
    public func install() throws -> URL? {
        var settings = try readSettings()

        var hooks: [String: Any]
        switch settings["hooks"] {
        case nil:
            hooks = [:]
        case let existing as [String: Any]:
            hooks = existing
        default:
            throw InstallerError.malformedSettings
        }

        var changed = false
        for event in Self.managedEvents {
            var entries: [[String: Any]]
            switch hooks[event] {
            case nil:
                entries = []
            case let existing as [[String: Any]]:
                entries = existing
            default:
                throw InstallerError.malformedSettings
            }

            guard !containsOurCommand(entries) else { continue }
            entries.append([
                "hooks": [
                    ["type": "command", "command": command(for: event)]
                ]
            ])
            hooks[event] = entries
            changed = true
        }

        guard changed else { return nil }
        settings["hooks"] = hooks
        return try write(settings)
    }

    /// Removes only our hooks; existing user hooks are preserved untouched.
    /// Returns the backup URL when the file was modified.
    @discardableResult
    public func uninstall() throws -> URL? {
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return nil }

        var changed = false
        for event in Self.managedEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }

            let cleaned: [[String: Any]] = entries.compactMap { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
                let kept = inner.filter { !isOurCommand($0) }
                if kept.count == inner.count { return entry }
                changed = true
                guard !kept.isEmpty else { return nil } // entry was entirely ours
                var updated = entry
                updated["hooks"] = kept
                return updated
            }
            entries = cleaned

            if entries.isEmpty {
                hooks[event] = nil
            } else {
                hooks[event] = entries
            }
        }

        guard changed else { return nil }
        if hooks.isEmpty {
            settings["hooks"] = nil
        } else {
            settings["hooks"] = hooks
        }
        return try write(settings)
    }

    // MARK: Internals

    func command(for event: String) -> String {
        "\(Self.shellSingleQuoted(helperPath)) \(event)"
    }

    /// A POSIX single-quoted word: the only quoting that suppresses every
    /// expansion (`$…`, backticks, globs). An embedded quote cannot be
    /// escaped inside single quotes, so it is broken out and re-quoted.
    ///
    /// The command this builds is run by a shell inside Claude Code, which
    /// makes it the one value NotchPilot writes that another process
    /// executes. `helperPath` comes from `FileManager`'s home directory and a
    /// macOS short name cannot contain a metacharacter today — this is here so
    /// that convention stops being the only thing enforcing it.
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private func isOurCommand(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        // The bare path also matches hooks written by versions that used
        // double quotes, so an upgrade still recognises and cleans them up.
        return command.contains(Self.shellSingleQuoted(helperPath))
            || command.contains(helperPath)
    }

    private func containsOurCommand(_ entries: Any?) -> Bool {
        guard let entries = entries as? [[String: Any]] else { return false }
        return entries.contains { entry in
            guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { isOurCommand($0) }
        }
    }

    /// Missing file reads as an empty settings dictionary (we may create it).
    /// Unparseable content throws — never overwritten.
    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw InstallerError.malformedSettings
        }
        return dictionary
    }

    /// Backs up the existing file (timestamped), then writes atomically.
    private func write(_ settings: [String: Any]) throws -> URL? {
        var backupURL: URL?
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let directory = settingsURL.deletingLastPathComponent()
            let stem = "\(settingsURL.lastPathComponent).notchpilot-\(formatter.string(from: Date()))"
            var backup = directory.appendingPathComponent("\(stem).bak")
            var counter = 1
            while FileManager.default.fileExists(atPath: backup.path) {
                backup = directory.appendingPathComponent("\(stem)-\(counter).bak")
                counter += 1
            }
            try FileManager.default.copyItem(at: settingsURL, to: backup)
            backupURL = backup
        } else {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
        return backupURL
    }
}
