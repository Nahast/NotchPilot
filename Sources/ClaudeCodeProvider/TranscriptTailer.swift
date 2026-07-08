import Foundation

/// Incremental tail-reader for JSONL transcripts: tracks a byte offset per
/// file and returns only complete lines appended since the previous read.
final class TranscriptTailer {
    private var offsets: [String: UInt64] = [:]
    private var remainders: [String: Data] = [:]

    /// How much of a newly-discovered file to read initially. Reading the
    /// whole file at startup would be wasteful for long-lived transcripts;
    /// the latest ~256 KB always contains the current activity and usage.
    static let initialReadWindow: UInt64 = 256 * 1024

    /// True if the tailer has never seen this file before.
    func isKnown(_ path: String) -> Bool {
        offsets[path] != nil
    }

    func forget(_ path: String) {
        offsets[path] = nil
        remainders[path] = nil
    }

    /// Reads complete lines appended since the last call. On first sight of a
    /// file, starts at most `initialReadWindow` bytes from the end (skipping
    /// the first partial line when starting mid-file).
    func readNewLines(at path: String) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch {
            return []
        }

        var offset: UInt64
        var skipFirstLine = false
        if let known = offsets[path] {
            offset = known
            if size < known {
                // File truncated/rewritten — start over.
                offset = 0
                remainders[path] = nil
            }
        } else if size > Self.initialReadWindow {
            offset = size - Self.initialReadWindow
            skipFirstLine = true // we're mid-line; drop the partial first line
        } else {
            offset = 0
        }

        guard size > offset else {
            offsets[path] = size
            return []
        }

        do {
            try handle.seek(toOffset: offset)
        } catch {
            return []
        }
        guard let newData = try? handle.readToEnd(), !newData.isEmpty else {
            offsets[path] = size
            return []
        }

        var buffer = (remainders[path] ?? Data()) + newData
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newlineIndex]
            if skipFirstLine {
                skipFirstLine = false
            } else if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer = buffer[buffer.index(after: newlineIndex)...]
        }
        remainders[path] = buffer.isEmpty ? nil : Data(buffer)
        offsets[path] = size
        return lines
    }
}
