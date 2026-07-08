import Foundation

// notchpilot-hook <EventName>
//
// Invoked by Claude Code hooks. Reads the hook JSON from stdin, adds np_*
// metadata, and drops one event file into the NotchPilot spool directory.
// Contract: finish fast, exit 0 no matter what — this process must never
// slow down or break a Claude Code session.

let eventName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Unknown"

// Claude Code hook payloads are small; cap defensively at 1 MB.
let maxInputBytes = 1_048_576
let inputData = FileHandle.standardInput.readDataToEndOfFile()

var payload: [String: Any] = [:]
if !inputData.isEmpty, inputData.count <= maxInputBytes,
   let object = try? JSONSerialization.jsonObject(with: inputData),
   let dictionary = object as? [String: Any] {
    payload = dictionary
}
if payload["hook_event_name"] == nil {
    payload["hook_event_name"] = eventName
}
payload["np_event_name"] = eventName
payload["np_received_at"] = Date().timeIntervalSince1970

let eventsDirectory: URL
if let override = ProcessInfo.processInfo.environment["NOTCHPILOT_EVENTS_DIR"], !override.isEmpty {
    eventsDirectory = URL(fileURLWithPath: override, isDirectory: true)
} else {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    eventsDirectory = base
        .appendingPathComponent("NotchPilot", isDirectory: true)
        .appendingPathComponent("events", isDirectory: true)
}

try? FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)

let filename = String(
    format: "%016.0f-%d-%04x.json",
    Date().timeIntervalSince1970 * 1_000_000,
    ProcessInfo.processInfo.processIdentifier,
    UInt16.random(in: .min ... .max)
)

if let data = try? JSONSerialization.data(withJSONObject: payload) {
    try? data.write(to: eventsDirectory.appendingPathComponent(filename), options: .atomic)
}

exit(0)
