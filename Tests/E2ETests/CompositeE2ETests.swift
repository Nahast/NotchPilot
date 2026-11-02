import AgentCore
import ClaudeCodeProvider
import CodexProvider
import XCTest

/// Both agents at once through the same composite the app wires up.
final class CompositeE2ETests: XCTestCase {
    func testClaudeAndCodexShareOneList() throws {
        let sandbox = try Sandbox()
        let claudeId = UUID().uuidString.lowercased()
        let codexId = UUID().uuidString.lowercased()

        let claude = ClaudeCodeProvider(configuration: .init(
            claudeHome: sandbox.claudeHome,
            eventsDirectory: sandbox.eventsDirectory,
            pollInterval: 0.2,
            fsEventsLatency: 0.05,
            hooksInstalled: { true },
            desktopSessionsDirectory: nil
        ))
        let codex = CodexProvider(configuration: .init(
            codexHome: sandbox.codexHome, pollInterval: 0.2, fsEventsLatency: 0.05
        ))
        let composite = CompositeAgentProvider(providers: [claude, codex])
        let recorder = Recorder(composite.sessionsPublisher)
        composite.start()
        defer { composite.stop() }

        try sandbox.fireHook("SessionStart", payload: ["session_id": claudeId, "cwd": "/Users/romain/Projects/web"])
        let rollout = sandbox.codexHome
            .appendingPathComponent("sessions/2026/10/30/rollout-2026-10-30T10-00-00-\(codexId).jsonl")
        try sandbox.append(
            #"{"timestamp":"\#(Stamp.iso())","type":"session_meta","payload":{"id":"\#(codexId)","cwd":"/Users/romain/Projects/api"}}"#,
            to: rollout
        )
        try sandbox.append(
            #"{"timestamp":"\#(Stamp.iso())","type":"event_msg","payload":{"type":"task_started"}}"#,
            to: rollout
        )

        recorder.wait("one working row per agent") { sessions in
            let kinds = Set(sessions.map(\.agentKind))
            let allWorking = sessions.allSatisfy { $0.status == .working }
            return kinds == [AgentKind.claude, AgentKind.codex] && allWorking
        }
        XCTAssertEqual(Set(recorder.latest.map(\.projectName)), ["web", "api"])
    }
}
