import Foundation

/// One parsed line from a Codex rollout transcript
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`).
public struct CodexEvent: Equatable {
    public enum Kind: Equatable {
        /// First line of a rollout: carries the working directory.
        case sessionMeta(cwd: String?)
        case taskStarted
        case taskComplete
        case userMessage
        /// The agent invoked a tool (function_call).
        case agentActivity(description: String)
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
            return CodexEvent(kind: .sessionMeta(cwd: payload["cwd"] as? String), timestamp: timestamp)
        }

        switch payloadType {
        case "task_started":
            return CodexEvent(kind: .taskStarted, timestamp: timestamp)
        case "task_complete":
            return CodexEvent(kind: .taskComplete, timestamp: timestamp)
        case "user_message":
            return CodexEvent(kind: .userMessage, timestamp: timestamp)
        case "function_call":
            let name = payload["name"] as? String ?? "tool"
            let description = describeFunctionCall(
                name: name,
                arguments: payload["arguments"] as? String
            )
            return CodexEvent(kind: .agentActivity(description: description), timestamp: timestamp)
        case "token_count":
            let info = payload["info"] as? [String: Any]
            let total = (info?["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int
            let window = info?["model_context_window"] as? Int
            return CodexEvent(kind: .tokenCount(usedTokens: total, contextWindow: window), timestamp: timestamp)
        default:
            // Approval requests vary by codex version (exec_approval_request,
            // apply_patch_approval_request, …) — match by substring.
            if let payloadType, payloadType.contains("approval") {
                return CodexEvent(kind: .approvalRequest, timestamp: timestamp)
            }
            return CodexEvent(kind: .uninteresting, timestamp: timestamp)
        }
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
                if let command = dictionary["command"] as? String {
                    return "Running: \(truncated(command))"
                }
            }
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
