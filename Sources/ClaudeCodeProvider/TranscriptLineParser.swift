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
        /// Claude Code named the conversation — the same string it pushes to
        /// the terminal tab, and so the only name the user recognises.
        case title(String)
        /// Line parsed but is not interesting for status (summaries, system, …).
        case uninteresting
    }

    public var sessionId: String?
    public var cwd: String?
    public var kind: Kind
    /// The line's own timestamp — real event time, not parse time. Keeps
    /// statuses and "waiting 3m" correct when parsing pre-existing
    /// transcripts at app launch.
    public var timestamp: Date?
    /// Git branch recorded on the line.
    public var gitBranch: String?

    public init(
        sessionId: String?,
        cwd: String?,
        kind: Kind,
        timestamp: Date? = nil,
        gitBranch: String? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.kind = kind
        self.timestamp = timestamp
        self.gitBranch = gitBranch
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
    /// API message id — used to dedupe token tallies across resumed sessions.
    public var messageId: String?
    /// Newly consumed tokens for this message: input + cache-creation +
    /// output (cache reads excluded).
    public var newTokens: Int?

    public init(
        model: String? = nil,
        contextUsedTokens: Int? = nil,
        activityDescription: String? = nil,
        issuedToolUse: Bool = false,
        messageId: String? = nil,
        newTokens: Int? = nil
    ) {
        self.model = model
        self.contextUsedTokens = contextUsedTokens
        self.activityDescription = activityDescription
        self.issuedToolUse = issuedToolUse
        self.messageId = messageId
        self.newTokens = newTokens
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

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterPlain = ISO8601DateFormatter()

    static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return isoFormatterFractional.date(from: string)
            ?? isoFormatterPlain.date(from: string)
    }

    static func parse(_ dictionary: [String: Any]) -> TranscriptEvent? {
        let sessionId = dictionary["sessionId"] as? String
        let cwd = dictionary["cwd"] as? String
        let type = dictionary["type"] as? String
        let timestamp = parseTimestamp(dictionary["timestamp"])
        let gitBranch = dictionary["gitBranch"] as? String

        func event(_ kind: TranscriptEvent.Kind) -> TranscriptEvent {
            TranscriptEvent(
                sessionId: sessionId,
                cwd: cwd,
                kind: kind,
                timestamp: timestamp,
                gitBranch: gitBranch
            )
        }

        // Subagent (sidechain) activity is out of scope for v1 — it would make
        // the parent session's activity line flicker between agents.
        if dictionary["isSidechain"] as? Bool == true {
            return event(.uninteresting)
        }

        switch type {
        case "assistant":
            guard let message = dictionary["message"] as? [String: Any] else {
                return event(.uninteresting)
            }
            return event(.assistantActivity(parseAssistantMessage(message)))
        case "user":
            return event(isToolResult(dictionary["message"]) ? .toolResult : .userPrompt)
        case "ai-title":
            // {"type":"ai-title","aiTitle":"Fix the flaky login test","sessionId":…}
            // Rewritten as the conversation moves on, so the last one wins.
            guard let title = (dictionary["aiTitle"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else { return event(.uninteresting) }
            return event(.title(title))
        default:
            // summary lines, system lines, future line types…
            return event(.uninteresting)
        }
    }

    private static func parseAssistantMessage(_ message: [String: Any]) -> AssistantActivity {
        var activity = AssistantActivity()
        activity.model = message["model"] as? String
        activity.messageId = message["id"] as? String

        if let usage = message["usage"] as? [String: Any] {
            let contextKeys = [
                "input_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
                "output_tokens",
            ]
            let contextValues = contextKeys.compactMap { usage[$0] as? Int }
            if !contextValues.isEmpty {
                activity.contextUsedTokens = contextValues.reduce(0, +)
            }
            // Fresh work only — cache reads are re-reads, not consumption.
            let newKeys = ["input_tokens", "cache_creation_input_tokens", "output_tokens"]
            let newValues = newKeys.compactMap { usage[$0] as? Int }
            if !newValues.isEmpty {
                activity.newTokens = newValues.reduce(0, +)
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
