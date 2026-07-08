import Foundation

/// Turns a Claude Code tool_use (name + input) into the one-line activity
/// string shown in the expanded panel ("Editing main.swift…").
public enum ActivityFormatter {
    public static func describe(toolName: String, input: [String: Any]) -> String {
        func basename(_ key: String) -> String? {
            (input[key] as? String).map { ($0 as NSString).lastPathComponent }
        }
        func truncated(_ string: String, to limit: Int = 48) -> String {
            let collapsed = string
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard collapsed.count > limit else { return collapsed }
            return String(collapsed.prefix(limit)) + "…"
        }

        switch toolName {
        case "Edit", "MultiEdit", "NotebookEdit":
            if let file = basename("file_path") ?? basename("notebook_path") {
                return "Editing \(file)…"
            }
            return "Editing files…"
        case "Write":
            if let file = basename("file_path") { return "Writing \(file)…" }
            return "Writing files…"
        case "Read":
            if let file = basename("file_path") { return "Reading \(file)…" }
            return "Reading files…"
        case "Bash":
            if let description = input["description"] as? String, !description.isEmpty {
                return truncated(description)
            }
            if let command = input["command"] as? String, !command.isEmpty {
                return "Running: \(truncated(command, to: 40))"
            }
            return "Running a command…"
        case "Grep", "Glob":
            if let pattern = input["pattern"] as? String, !pattern.isEmpty {
                return "Searching \"\(truncated(pattern, to: 32))\"…"
            }
            return "Searching…"
        case "Task", "Agent":
            if let description = input["description"] as? String, !description.isEmpty {
                return "Delegating: \(truncated(description, to: 36))"
            }
            return "Delegating to a subagent…"
        case "WebFetch":
            return "Fetching a web page…"
        case "WebSearch":
            return "Searching the web…"
        case "TodoWrite", "TaskCreate", "TaskUpdate":
            return "Updating the plan…"
        case "AskUserQuestion":
            return "Asking you a question…"
        default:
            return "\(toolName)…"
        }
    }
}
