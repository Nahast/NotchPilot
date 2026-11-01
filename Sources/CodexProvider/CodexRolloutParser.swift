import Foundation

/// One parsed line from a Codex rollout transcript
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`).
public struct CodexEvent: Equatable {
    public enum Kind: Equatable {
        /// First line of a rollout: carries the working directory, and — for
        /// sub-threads (guardian approval reviews, spawned subagents) — the
        /// thread that owns them.
        case sessionMeta(cwd: String?, parentThreadId: String? = nil)
        /// Written at the start of every turn; the only place the working
        /// directory survives when the head of a long rollout was skipped.
        case turnContext(cwd: String?)
        case taskStarted
        case taskComplete
        /// The user interrupted the turn; no `task_complete` follows.
        case turnAborted
        case userMessage
        /// The agent invoked a tool (function_call / custom_tool_call). The
        /// call id pairs it with the output that closes it.
        case agentActivity(description: String, callId: String? = nil)
        /// A tool call finished (function_call_output / custom_tool_call_output).
        case toolOutput(callId: String?)
        /// The agent is waiting for the user to approve something.
        case approvalRequest
        /// Cumulative usage + the model's context window.
        case tokenCount(usedTokens: Int?, contextWindow: Int?)
        case uninteresting
    }

    public var kind: Kind
    public var timestamp: Date?

    public init(kind: Kind, timestamp: Date? = nil) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// Tolerant parser for Codex rollout lines — unknown shapes degrade to
/// `.uninteresting`, never crash.
public enum CodexRolloutParser {
    public static func parse(_ data: Data) -> CodexEvent? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }

        let timestamp = parseTimestamp(dictionary["timestamp"])
        let topType = dictionary["type"] as? String
        let payload = dictionary["payload"] as? [String: Any] ?? [:]
        let payloadType = payload["type"] as? String

        if topType == "session_meta" {
            return CodexEvent(
                kind: .sessionMeta(
                    cwd: payload["cwd"] as? String,
                    parentThreadId: nonEmpty(payload["parent_thread_id"] as? String)
                ),
                timestamp: timestamp
            )
        }
        if topType == "turn_context" {
            return CodexEvent(kind: .turnContext(cwd: payload["cwd"] as? String), timestamp: timestamp)
        }

        switch payloadType {
        case "task_started":
            return CodexEvent(kind: .taskStarted, timestamp: timestamp)
        case "task_complete":
            return CodexEvent(kind: .taskComplete, timestamp: timestamp)
        case "turn_aborted":
            return CodexEvent(kind: .turnAborted, timestamp: timestamp)
        case "user_message":
            return CodexEvent(kind: .userMessage, timestamp: timestamp)
        // Current Codex issues most tools as custom_tool_call (exec,
        // apply_patch, …) with a free-form `input`; older builds use
        // function_call with JSON `arguments`.
        case "function_call", "custom_tool_call":
            let name = payload["name"] as? String ?? "tool"
            let description = describeFunctionCall(
                name: name,
                arguments: (payload["arguments"] as? String) ?? (payload["input"] as? String)
            )
            return CodexEvent(
                kind: .agentActivity(description: description, callId: nonEmpty(payload["call_id"] as? String)),
                timestamp: timestamp
            )
        case "function_call_output", "custom_tool_call_output":
            return CodexEvent(
                kind: .toolOutput(callId: nonEmpty(payload["call_id"] as? String)),
                timestamp: timestamp
            )
        case "token_count":
            let info = payload["info"] as? [String: Any]
            // The last request's usage is what currently fills the context
            // window; the session total only ever grows, so it would peg the
            // gauge at 100% long before the context is actually full.
            let last = (info?["last_token_usage"] as? [String: Any])?["total_tokens"] as? Int
            let total = (info?["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int
            let window = info?["model_context_window"] as? Int
            return CodexEvent(kind: .tokenCount(usedTokens: last ?? total, contextWindow: window), timestamp: timestamp)
        default:
            // Approval requests vary by codex version (exec_approval_request,
            // apply_patch_approval_request, …) — match by substring.
            if let payloadType, payloadType.contains("approval") {
                return CodexEvent(kind: .approvalRequest, timestamp: timestamp)
            }
            return CodexEvent(kind: .uninteresting, timestamp: timestamp)
        }
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    /// "shell" {"command": ["bash","-lc","swift test"]} → "Running: swift test"
    static func describeFunctionCall(name: String, arguments: String?) -> String {
        func truncated(_ string: String, to limit: Int = 44) -> String {
            let collapsed = string
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard collapsed.count > limit else { return collapsed }
            return String(collapsed.prefix(limit)) + "…"
        }

        switch name {
        case "shell", "local_shell", "exec_command":
            if let arguments,
               let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)),
               let dictionary = object as? [String: Any] {
                if let parts = dictionary["command"] as? [String] {
                    // Drop the "bash -lc" wrapper when present.
                    let command = parts.count >= 3 && parts[1].hasPrefix("-l")
                        ? parts.dropFirst(2).joined(separator: " ")
                        : parts.joined(separator: " ")
                    return "Running: \(truncated(command))"
                }
                // `exec_command` spells the command string `cmd`.
                if let command = (dictionary["command"] as? String) ?? (dictionary["cmd"] as? String) {
                    return "Running: \(truncated(command))"
                }
            }
            return "Running a command…"
        case "exec", "wait":
            // Code-mode: the input is a script, not a command line.
            return "Running a command…"
        case "apply_patch":
            return "Editing files…"
        case "update_plan":
            return "Updating the plan…"
        case "web_search":
            return "Searching the web…"
        default:
            return "\(name)…"
        }
    }

    /// Reads the first line of a rollout — `session_meta`, which carries the
    /// working directory and parent thread. It embeds the full system prompt,
    /// so it can be tens of KB; the tailer's tail window would skip it on any
    /// long rollout, hence this separate bounded read.
    public static func readHead(atPath path: String, limit: Int = 1_048_576) -> CodexEvent? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        while buffer.count < limit {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return parse(buffer[buffer.startIndex..<newline])
            }
        }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()

    static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    /// "rollout-2026-03-19T21-25-35-<uuid>.jsonl" → the uuid.
    public static func sessionId(fromFilename filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.hasPrefix("rollout-"), stem.count > 36 else { return nil }
        let candidate = String(stem.suffix(36))
        // Loose UUID shape check (8-4-4-4-12).
        let parts = candidate.split(separator: "-")
        guard parts.count == 5, parts.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        return candidate
    }
}
