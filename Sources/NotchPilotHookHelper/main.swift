import Foundation

// notchpilot-hook <EventName> [<spool-subdirectory>]
//
// Invoked by agent hooks (Claude Code settings.json, Cursor hooks.json).
// Reads the hook JSON from stdin, adds np_* metadata, and drops one event
// file into the NotchPilot spool. The optional second argument selects a
// spool subdirectory (default "events") so each provider consumes only its
// own files. Contract: finish fast, exit 0 no matter what — this process
// must never slow down or break an agent session.

let eventName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Unknown"
let requestedSubdirectory = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "events"
// Sanitize: the subdirectory travels through third-party hook configs.
let spoolSubdirectory = requestedSubdirectory.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    && !requestedSubdirectory.isEmpty
    ? requestedSubdirectory
    : "events"

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
    // Test hook: the override is the spool BASE when a subdirectory was
    // requested, or the events directory itself otherwise.
    let base = URL(fileURLWithPath: override, isDirectory: true)
    eventsDirectory = CommandLine.arguments.count > 2
        ? base.appendingPathComponent(spoolSubdirectory, isDirectory: true)
        : base
} else {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    eventsDirectory = base
        .appendingPathComponent("NotchPilot", isDirectory: true)
        .appendingPathComponent(spoolSubdirectory, isDirectory: true)
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
