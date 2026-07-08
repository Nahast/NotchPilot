import Foundation

/// One event file written by the notchpilot-hook micro-helper into the spool
/// directory. The helper stores Claude Code's hook stdin JSON as-is, adding
/// `np_event_name` (from argv) and `np_received_at` (epoch seconds).
public struct HookEvent: Equatable {
    public enum Name: String, Equatable {
        case sessionStart = "SessionStart"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"
    }

    public var name: Name
    public var sessionId: String
    public var cwd: String?
    public var transcriptPath: String?
    /// Human-facing message for Notification events
    /// ("Claude needs your permission to use Bash").
    public var message: String?
    public var receivedAt: Date

    public init(
        name: Name,
        sessionId: String,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        message: String? = nil,
        receivedAt: Date
    ) {
        self.name = name
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.message = message
        self.receivedAt = receivedAt
    }

    /// Tolerant decode; returns nil for unknown event names or missing session id.
    public static func decode(from data: Data) -> HookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }

        let rawName = (dictionary["hook_event_name"] as? String)
            ?? (dictionary["np_event_name"] as? String)
        guard let rawName, let name = Name(rawValue: rawName),
              let sessionId = dictionary["session_id"] as? String, !sessionId.isEmpty
        else { return nil }

        let receivedAt: Date
        if let epoch = dictionary["np_received_at"] as? Double {
            receivedAt = Date(timeIntervalSince1970: epoch)
        } else {
            receivedAt = Date()
        }

        return HookEvent(
            name: name,
            sessionId: sessionId,
            cwd: dictionary["cwd"] as? String,
            transcriptPath: dictionary["transcript_path"] as? String,
            message: dictionary["message"] as? String,
            receivedAt: receivedAt
        )
    }
}
