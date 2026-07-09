import AgentCore
import Foundation

/// Per-session metadata from the Claude desktop app's local store.
struct DesktopSessionInfo: Equatable {
    /// Sidebar title ("Automated development workflows").
    var title: String?
    /// Set when the session was launched by a scheduled task ("backlog-tick")
    /// — the ground-truth routine marker.
    var scheduledTaskId: String?
    /// Attached pull request identity + state (no live CI data is stored).
    var pullRequest: PullRequestInfo?
    /// Working branch recorded by the desktop app.
    var branch: String?
    /// The desktop app's own session id ("local_<uuid>") — deep-link target.
    var localSessionId: String?
}

/// Reads the Claude desktop app's session metadata
/// (`~/Library/Application Support/Claude/claude-code-sessions/<org>/<ws>/*.json`)
/// keyed by CLI session id. Files are re-read only when their mtime changes;
/// when several files reference the same CLI session (resumes, new tabs),
/// the most recently active one wins.
final class DesktopSessionMetadataReader {
    private struct CachedFile {
        var mtime: Date
        var cliSessionId: String?
        var info: DesktopSessionInfo
        /// Epoch millis of the file's own activity stamp, for dedup.
        var recency: Double
    }

    let directory: URL
    private var cache: [String: CachedFile] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// CLI session id → desktop metadata.
    func infoBySessionId() -> [String: DesktopSessionInfo] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var best: [String: (recency: Double, info: DesktopSessionInfo)] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "json" else { continue }
            let path = url.path
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            let entry: CachedFile
            if let cached = cache[path], cached.mtime == mtime {
                entry = cached
            } else {
                entry = Self.read(url: url, mtime: mtime)
                cache[path] = entry
            }

            guard let sessionId = entry.cliSessionId, !sessionId.isEmpty,
                  entry.info != DesktopSessionInfo()
            else { continue }
            if let existing = best[sessionId], existing.recency >= entry.recency { continue }
            best[sessionId] = (entry.recency, entry.info)
        }
        return best.mapValues(\.info)
    }

    private static func read(url: URL, mtime: Date) -> CachedFile {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return CachedFile(mtime: mtime, cliSessionId: nil, info: DesktopSessionInfo(), recency: 0)
        }
        let recency = (dictionary["lastActivityAt"] as? Double)
            ?? (dictionary["lastFocusedAt"] as? Double)
            ?? (dictionary["createdAt"] as? Double)
            ?? 0
        return CachedFile(
            mtime: mtime,
            cliSessionId: dictionary["cliSessionId"] as? String,
            info: DesktopSessionInfo(
                title: nonEmpty(dictionary["title"] as? String),
                scheduledTaskId: nonEmpty(dictionary["scheduledTaskId"] as? String),
                pullRequest: parsePullRequest(dictionary),
                branch: nonEmpty(dictionary["branch"] as? String),
                localSessionId: nonEmpty(dictionary["sessionId"] as? String)
            ),
            recency: recency
        )
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    /// Top-level prNumber/prState/prUrl describe the session's current PR;
    /// fall back to the last entry of the `prs` array.
    private static func parsePullRequest(_ dictionary: [String: Any]) -> PullRequestInfo? {
        if let number = dictionary["prNumber"] as? Int,
           let state = (dictionary["prState"] as? String).flatMap(PullRequestInfo.State.init(rawValue:)) {
            return PullRequestInfo(number: number, state: state, url: dictionary["prUrl"] as? String)
        }
        if let prs = dictionary["prs"] as? [[String: Any]],
           let last = prs.last,
           let number = last["prNumber"] as? Int,
           let state = (last["state"] as? String).flatMap(PullRequestInfo.State.init(rawValue:)) {
            return PullRequestInfo(number: number, state: state, url: last["url"] as? String)
        }
        return nil
    }
}
