import Foundation

/// Manages NotchPilot's entries in Cursor's hooks file (`~/.cursor/hooks.json`).
/// Same safety rules as the Claude installer: parse-validate first, refuse to
/// write malformed files, timestamped backup before every modifying write,
/// never touch foreign hooks.
public struct CursorHooksInstaller {
    public enum InstallerError: Error, LocalizedError, Equatable {
        case malformedHooksFile

        public var errorDescription: String? {
            switch self {
            case .malformedHooksFile:
                return "~/.cursor/hooks.json could not be parsed. NotchPilot will not modify it."
            }
        }
    }

    /// Cursor hook event → the event name our helper stamps on spool files.
    public static let managedEvents: [(cursorEvent: String, spoolName: String)] = [
        ("beforeSubmitPrompt", "CursorPromptSubmit"),
        ("afterFileEdit", "CursorFileEdit"),
        ("stop", "CursorStop"),
    ]

    /// Spool subdirectory (under Application Support/NotchPilot) the Cursor
    /// hook events land in — kept separate from the Claude spool so each
    /// provider consumes only its own files.
    public static let spoolSubdirectory = "cursor-events"

    public let hooksURL: URL
    public let helperPath: String

    public init(hooksURL: URL, helperPath: String) {
        self.hooksURL = hooksURL
        self.helperPath = helperPath
    }

    func command(forSpoolName spoolName: String) -> String {
        "\"\(helperPath)\" \(spoolName) \(Self.spoolSubdirectory)"
    }

    public func isInstalled() -> Bool {
        guard let root = try? readHooksFile(),
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        return Self.managedEvents.allSatisfy { event in
            guard let entries = hooks[event.cursorEvent] as? [[String: Any]] else { return false }
            return entries.contains { ($0["command"] as? String)?.contains(helperPath) == true }
        }
    }

    /// Idempotent merge. Returns the backup URL when the file was modified.
    @discardableResult
    public func install() throws -> URL? {
        var root = try readHooksFile()
        if root["version"] == nil {
            root["version"] = 1
        }

        var hooks: [String: Any]
        switch root["hooks"] {
        case nil:
            hooks = [:]
        case let existing as [String: Any]:
            hooks = existing
        default:
            throw InstallerError.malformedHooksFile
        }

        var changed = false
        for event in Self.managedEvents {
            var entries: [[String: Any]]
            switch hooks[event.cursorEvent] {
            case nil:
                entries = []
            case let existing as [[String: Any]]:
                entries = existing
            default:
                throw InstallerError.malformedHooksFile
            }
            guard !entries.contains(where: { ($0["command"] as? String)?.contains(helperPath) == true })
            else { continue }
            entries.append(["command": command(forSpoolName: event.spoolName)])
            hooks[event.cursorEvent] = entries
            changed = true
        }

        guard changed else { return nil }
        root["hooks"] = hooks
        return try write(root)
    }

    /// Removes only our hooks. Returns the backup URL when modified.
    @discardableResult
    public func uninstall() throws -> URL? {
        var root = try readHooksFile()
        guard var hooks = root["hooks"] as? [String: Any] else { return nil }

        var changed = false
        for event in Self.managedEvents {
            guard let entries = hooks[event.cursorEvent] as? [[String: Any]] else { continue }
            let kept = entries.filter { ($0["command"] as? String)?.contains(helperPath) != true }
            guard kept.count != entries.count else { continue }
            changed = true
            if kept.isEmpty {
                hooks[event.cursorEvent] = nil
            } else {
                hooks[event.cursorEvent] = kept
            }
        }

        guard changed else { return nil }
        if hooks.isEmpty {
            root["hooks"] = nil
        } else {
            root["hooks"] = hooks
        }
        return try write(root)
    }

    // MARK: Internals

    private func readHooksFile() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: hooksURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw InstallerError.malformedHooksFile
        }
        return dictionary
    }

    private func write(_ root: [String: Any]) throws -> URL? {
        var backupURL: URL?
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let directory = hooksURL.deletingLastPathComponent()
            let stem = "\(hooksURL.lastPathComponent).notchpilot-\(formatter.string(from: Date()))"
            var backup = directory.appendingPathComponent("\(stem).bak")
            var counter = 1
            while FileManager.default.fileExists(atPath: backup.path) {
                backup = directory.appendingPathComponent("\(stem)-\(counter).bak")
                counter += 1
            }
            try FileManager.default.copyItem(at: hooksURL, to: backup)
            backupURL = backup
        } else {
            try FileManager.default.createDirectory(
                at: hooksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: hooksURL, options: .atomic)
        return backupURL
    }
}
