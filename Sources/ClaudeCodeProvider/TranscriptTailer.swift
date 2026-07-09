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

    /// Result of a read: the complete appended lines, plus whether history
    /// was skipped when first picking up a large file.
    struct ReadResult {
        var lines: [Data]
        var skippedHistory: Bool
    }

    /// Reads complete lines appended since the last call. On first sight of a
    /// file, starts at most `initialWindow` bytes from the end (skipping the
    /// first partial line when starting mid-file).
    func readNewLines(
        at path: String,
        initialWindow: UInt64 = TranscriptTailer.initialReadWindow
    ) -> ReadResult {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return ReadResult(lines: [], skippedHistory: false)
        }
        defer { try? handle.close() }

        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch {
            return ReadResult(lines: [], skippedHistory: false)
        }

        var offset: UInt64
        var skipFirstLine = false
        var skippedHistory = false
        if let known = offsets[path] {
            offset = known
            if size < known {
                // File truncated/rewritten — start over.
                offset = 0
                remainders[path] = nil
            }
        } else if size > initialWindow {
            offset = size - initialWindow
            skipFirstLine = true // we're mid-line; drop the partial first line
            skippedHistory = true
        } else {
            offset = 0
        }

        guard size > offset else {
            offsets[path] = size
            return ReadResult(lines: [], skippedHistory: skippedHistory)
        }

        do {
            try handle.seek(toOffset: offset)
        } catch {
            return ReadResult(lines: [], skippedHistory: skippedHistory)
        }
        guard let newData = try? handle.readToEnd(), !newData.isEmpty else {
            offsets[path] = size
            return ReadResult(lines: [], skippedHistory: skippedHistory)
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
        return ReadResult(lines: lines, skippedHistory: skippedHistory)
    }
}
