import AgentCore
import Combine
import Foundation
import XCTest

/// A throwaway machine: private `~/.claude`, `~/.codex` and spool directories
/// that real providers watch with real FSEvents.
final class Sandbox {
    let root: URL
    let claudeHome: URL
    let codexHome: URL
    let eventsDirectory: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotchPilotE2E-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        claudeHome = root.appendingPathComponent(".claude", isDirectory: true)
        codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        eventsDirectory = root.appendingPathComponent("events", isDirectory: true)
        for directory in [claudeHome, codexHome, eventsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    // MARK: Files

    func append(_ line: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    // MARK: The real hook helper

    /// `notchpilot-hook` as Claude Code would invoke it: hook JSON on stdin,
    /// event name in argv. Built next to the test bundle by SwiftPM.
    static var helperURL: URL {
        Bundle(for: Sandbox.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("notchpilot-hook")
    }

    @discardableResult
    func fireHook(_ event: String, payload: [String: Any]) throws -> Int32 {
        let helper = Self.helperURL
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw NSError(domain: "E2E", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "notchpilot-hook not built at \(helper.path) — run `swift build` first",
            ])
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = [event]
        process.environment = ["NOTCHPILOT_EVENTS_DIR": eventsDirectory.path]
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Subscribes to a provider and keeps every published snapshot, so a test can
/// assert on what the user *saw over time* — not just where things ended up.
final class Recorder {
    private(set) var snapshots: [[AgentSession]] = []
    private var cancellable: AnyCancellable?
    private var waiters: [(predicate: ([AgentSession]) -> Bool, fulfil: () -> Void)] = []

    init(_ publisher: AnyPublisher<[AgentSession], Never>) {
        cancellable = publisher.sink { [weak self] sessions in
            guard let self else { return }
            self.snapshots.append(sessions)
            self.waiters.removeAll { waiter in
                guard waiter.predicate(sessions) else { return false }
                waiter.fulfil()
                return true
            }
        }
    }

    var latest: [AgentSession] { snapshots.last ?? [] }

    /// Blocks (spinning the main run loop, where providers publish) until a
    /// snapshot satisfies `predicate`. Fails the test with the last state seen.
    func wait(
        _ description: String,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line,
        until predicate: @escaping ([AgentSession]) -> Bool
    ) {
        if predicate(latest) { return }
        let expectation = XCTestExpectation(description: description)
        waiters.append((predicate, { expectation.fulfill() }))
        if XCTWaiter().wait(for: [expectation], timeout: timeout) != .completed {
            waiters.removeAll()
            XCTFail(
                "Timed out waiting for: \(description). Last state: "
                    + latest.map { "\($0.agentKind)/\($0.status)/\($0.activity ?? "-")" }.description,
                file: file, line: line
            )
        }
    }

    /// Lets the providers run for `seconds` so a test can prove something
    /// did *not* happen.
    func settle(_ seconds: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { expectation.fulfill() }
        _ = XCTWaiter().wait(for: [expectation], timeout: seconds + 2)
    }
}

enum Stamp {
    static func iso(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
