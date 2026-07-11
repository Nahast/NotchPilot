import AgentCore
import Combine
@testable import CursorProvider
import XCTest

final class CursorProviderIntegrationTests: XCTestCase {
    private var eventsDir: URL!
    private var provider: CursorProvider!
    private var cancellables: Set<AnyCancellable> = []
    private let conversationId = "conv-1234"

    override func setUpWithError() throws {
        try super.setUpWithError()
        eventsDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CursorProviderTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        provider = CursorProvider(configuration: .init(
            eventsDirectory: eventsDir,
            stalenessTimeout: { 30 * 60 },
            pollInterval: 0.15,
            fsEventsLatency: 0.05
        ))
    }

    override func tearDownWithError() throws {
        provider.stop()
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: eventsDir)
        try super.tearDownWithError()
    }

    private func spoolEvent(_ name: String, extra: [String: Any] = [:]) throws {
        var payload: [String: Any] = [
            "np_event_name": name,
            "np_received_at": Date().timeIntervalSince1970,
            "conversation_id": conversationId,
            "workspace_roots": ["/Users/romain/Projects/webapp"],
        ]
        payload.merge(extra) { _, new in new }
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: eventsDir.appendingPathComponent("\(UUID().uuidString).json"))
    }

    private func waitForSessions(
        timeout: TimeInterval = 5,
        description: String,
        where predicate: @escaping ([AgentSession]) -> Bool
    ) {
        let expectation = expectation(description: description)
        expectation.assertForOverFulfill = false
        provider.sessionsPublisher
            .filter(predicate)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        provider.rescanNow()
        wait(for: [expectation], timeout: timeout)
    }

    func testPromptEditStopLifecycle() throws {
        provider.start()

        try spoolEvent("CursorPromptSubmit")
        waitForSessions(description: "working after prompt") { sessions in
            sessions.count == 1
                && sessions[0].agentKind == .cursor
                && sessions[0].status == .working
                && sessions[0].projectName == "webapp"
        }

        try spoolEvent("CursorFileEdit", extra: ["file_path": "/Users/romain/Projects/webapp/src/App.tsx"])
        waitForSessions(description: "editing activity") { sessions in
            sessions.first?.activity == "Editing App.tsx…"
        }

        try spoolEvent("CursorStop")
        waitForSessions(description: "idle after stop") { sessions in
            sessions.first?.status == .idle
        }
    }

    func testSpoolFilesAreConsumedAndForeignEventsIgnored() throws {
        provider.start()
        try spoolEvent("CursorPromptSubmit")
        // A Claude-style event accidentally landing here must be ignored.
        try JSONSerialization.data(withJSONObject: [
            "np_event_name": "SessionStart",
            "session_id": "claude-1",
            "np_received_at": Date().timeIntervalSince1970,
        ]).write(to: eventsDir.appendingPathComponent("\(UUID().uuidString).json"))

        waitForSessions(description: "only cursor session") { sessions in
            sessions.count == 1 && sessions[0].id == self.conversationId
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: eventsDir.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertTrue(leftovers.isEmpty)
    }
}
