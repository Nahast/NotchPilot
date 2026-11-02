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
    /// Why a Notification fired: "permission_prompt", "idle_prompt", … Absent
    /// on older Claude Code versions.
    public var notificationType: String?
    public var receivedAt: Date

    public init(
        name: Name,
        sessionId: String,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        receivedAt: Date
    ) {
        self.name = name
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.message = message
        self.notificationType = notificationType
        self.receivedAt = receivedAt
    }

    /// The reminder Claude Code sends after a finished turn has sat unanswered
    /// ("Claude is waiting for your input"). It says the session is done, not
    /// that it is blocked.
    public var isIdleReminder: Bool {
        guard name == .notification else { return false }
        if let notificationType { return notificationType == "idle_prompt" }
        return message?.localizedCaseInsensitiveContains("waiting for your input") == true
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
            notificationType: dictionary["notification_type"] as? String,
            receivedAt: receivedAt
        )
    }
}
