import Darwin
import Foundation

/// One entry from Claude Code's live session registry
/// (`~/.claude/sessions/<pid>.json`).
public struct SessionRegistryEntry: Equatable {
    public var sessionId: String
    public var pid: Int32
    /// "interactive" for user-driven sessions; anything else (scheduled,
    /// headless, …) is treated as a routine/background run.
    public var kind: String?
    public var entrypoint: String?
    /// Human session name ("droplet-a1").
    public var name: String?
    public var cwd: String?

    public var isRoutine: Bool {
        guard let kind else { return false }
        return kind != "interactive"
    }
}

/// Reads the session registry and reports entries whose process is alive.
/// Liveness is injectable for tests.
public struct SessionRegistryReader {
    var directory: URL
    var isProcessAlive: (Int32) -> Bool = SessionRegistryReader.defaultLivenessCheck

    /// `kill(pid, 0)` == 0 means the process exists; EPERM means it exists
    /// but belongs to someone else (still alive).
    public static func defaultLivenessCheck(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Alive entries keyed by session id (later files win on duplicates).
    func aliveEntries() -> [String: SessionRegistryEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [:] }

        var result: [String: SessionRegistryEntry] = [:]
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let sessionId = dictionary["sessionId"] as? String, !sessionId.isEmpty,
                  let pid = dictionary["pid"] as? Int
            else { continue }

            guard isProcessAlive(Int32(pid)) else { continue }

            result[sessionId] = SessionRegistryEntry(
                sessionId: sessionId,
                pid: Int32(pid),
                kind: dictionary["kind"] as? String,
                entrypoint: dictionary["entrypoint"] as? String,
                name: dictionary["name"] as? String,
                cwd: dictionary["cwd"] as? String
            )
        }
        return result
    }
}
