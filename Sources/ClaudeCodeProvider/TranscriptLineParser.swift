import Foundation

/// What one parsed transcript line means for a session.
public struct TranscriptEvent: Equatable {
    public enum Kind: Equatable {
        /// Assistant message appended — carries model/usage/tool activity.
        case assistantActivity(AssistantActivity)
        /// The human typed a new prompt (starts a new turn).
        case userPrompt
        /// A tool_result came back (the turn is moving again).
        case toolResult
        /// Line parsed but is not interesting for status (summaries, system, …).
        case uninteresting
    }

    public var sessionId: String?
    public var cwd: String?
    public var kind: Kind

    public init(sessionId: String?, cwd: String?, kind: Kind) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.kind = kind
    }
}

public struct AssistantActivity: Equatable {
    /// Model id from the message ("claude-sonnet-4-5"), if present.
    public var model: String?
    /// Total tokens occupying the context window after this message, if usage present.
    public var contextUsedTokens: Int?
    /// Human-readable description of the last tool_use in the message, if any.
    public var activityDescription: String?
    /// True when the message contains at least one tool_use block
    /// (the turn now waits on a tool result).
    public var issuedToolUse: Bool

    public init(
        model: String? = nil,
        contextUsedTokens: Int? = nil,
        activityDescription: String? = nil,
        issuedToolUse: Bool = false
    ) {
        self.model = model
        self.contextUsedTokens = contextUsedTokens
        self.activityDescription = activityDescription
        self.issuedToolUse = issuedToolUse
    }
}

/// Tolerant parser for Claude Code JSONL transcript lines.
/// Unknown or malformed shapes yield `nil` / `.uninteresting` — format drift
/// must degrade gracefully, never crash (design spec §4).
public enum TranscriptLineParser {
    public static func parse(_ lineData: Data) -> TranscriptEvent? {
        guard !lineData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: lineData),
              let dictionary = object as? [String: Any]
        else { return nil }
        return parse(dictionary)
    }

    public static func parse(_ line: String) -> TranscriptEvent? {
        parse(Data(line.utf8))
    }

    static func parse(_ dictionary: [String: Any]) -> TranscriptEvent? {
        let sessionId = dictionary["sessionId"] as? String
        let cwd = dictionary["cwd"] as? String
        let type = dictionary["type"] as? String

        // Subagent (sidechain) activity is out of scope for v1 — it would make
        // the parent session's activity line flicker between agents.
        if dictionary["isSidechain"] as? Bool == true {
            return TranscriptEvent(sessionId: sessionId, cwd: cwd, kind: .uninteresting)
        }

        switch type {
        case "assistant":
            guard let message = dictionary["message"] as? [String: Any] else {
                return TranscriptEvent(sessionId: sessionId, cwd: cwd, kind: .uninteresting)
            }
            return TranscriptEvent(
                sessionId: sessionId,
                cwd: cwd,
                kind: .assistantActivity(parseAssistantMessage(message))
            )
        case "user":
            let kind: TranscriptEvent.Kind = isToolResult(dictionary["message"]) ? .toolResult : .userPrompt
            return TranscriptEvent(sessionId: sessionId, cwd: cwd, kind: kind)
        default:
            // summary lines, system lines, future line types…
            return TranscriptEvent(sessionId: sessionId, cwd: cwd, kind: .uninteresting)
        }
    }

    private static func parseAssistantMessage(_ message: [String: Any]) -> AssistantActivity {
        var activity = AssistantActivity()
        activity.model = message["model"] as? String

        if let usage = message["usage"] as? [String: Any] {
            let keys = [
                "input_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
                "output_tokens",
            ]
            let values = keys.compactMap { usage[$0] as? Int }
            if !values.isEmpty {
                activity.contextUsedTokens = values.reduce(0, +)
            }
        }

        if let content = message["content"] as? [[String: Any]] {
            // Use the LAST tool_use block: it is the most recent action.
            for block in content.reversed() {
                guard block["type"] as? String == "tool_use",
                      let name = block["name"] as? String
                else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                activity.activityDescription = ActivityFormatter.describe(toolName: name, input: input)
                activity.issuedToolUse = true
                break
            }
        }
        return activity
    }

    private static func isToolResult(_ message: Any?) -> Bool {
        guard let message = message as? [String: Any] else { return false }
        if let content = message["content"] as? [[String: Any]] {
            return content.contains { $0["type"] as? String == "tool_result" }
        }
        return false
    }
}
