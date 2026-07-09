import Foundation

/// Reads `~/.codex/session_index.jsonl` — one line per session:
/// {"id": "<uuid>", "thread_name": "Fix the tests", "updated_at": "…"}.
/// Re-read only when the file's mtime changes; later lines win.
final class CodexSessionIndex {
    private let url: URL
    private var lastModified: Date?
    private var names: [String: String] = [:]

    init(url: URL) {
        self.url = url
    }

    func threadNames() -> [String: String] {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        guard modified != lastModified else { return names }
        lastModified = modified

        guard let data = try? Data(contentsOf: url) else {
            names = [:]
            return names
        }
        var result: [String: String] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = object as? [String: Any],
                  let id = dictionary["id"] as? String,
                  let name = dictionary["thread_name"] as? String, !name.isEmpty
            else { continue }
            result[id] = name
        }
        names = result
        return names
    }
}
