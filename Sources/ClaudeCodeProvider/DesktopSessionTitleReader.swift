import Foundation

/// Reads the Claude desktop app's session metadata
/// (`~/Library/Application Support/Claude/claude-code-sessions/<org>/<ws>/*.json`)
/// and maps CLI session ids to the human titles shown in the app's sidebar
/// ("Automated development workflows"). Files are re-read only when their
/// mtime changes; when several files reference the same CLI session (resumes,
/// new tabs), the most recently active one wins.
final class DesktopSessionTitleReader {
    private struct CachedFile {
        var mtime: Date
        var cliSessionId: String?
        var title: String?
        /// Epoch millis of the file's own activity stamp, for dedup.
        var recency: Double
    }

    let directory: URL
    private var cache: [String: CachedFile] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// CLI session id → sidebar title.
    func titlesBySessionId() -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var best: [String: (recency: Double, title: String)] = [:]
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
                  let title = entry.title, !title.isEmpty
            else { continue }
            if let existing = best[sessionId], existing.recency >= entry.recency { continue }
            best[sessionId] = (entry.recency, title)
        }
        return best.mapValues(\.title)
    }

    private static func read(url: URL, mtime: Date) -> CachedFile {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return CachedFile(mtime: mtime, cliSessionId: nil, title: nil, recency: 0)
        }
        let recency = (dictionary["lastActivityAt"] as? Double)
            ?? (dictionary["lastFocusedAt"] as? Double)
            ?? (dictionary["createdAt"] as? Double)
            ?? 0
        return CachedFile(
            mtime: mtime,
            cliSessionId: dictionary["cliSessionId"] as? String,
            title: dictionary["title"] as? String,
            recency: recency
        )
    }
}
