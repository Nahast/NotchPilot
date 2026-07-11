import AgentCore
import Combine
import XCTest

private final class StubProvider: AgentProvider {
    let providerName: String
    let sessions: CurrentValueSubject<[AgentSession], Never>
    let limited: CurrentValueSubject<Bool, Never>
    let tally: CurrentValueSubject<TokenTally?, Never>
    var started = false

    init(name: String, sessions: [AgentSession], limited: Bool = false, tally: TokenTally? = nil) {
        providerName = name
        self.sessions = CurrentValueSubject(sessions)
        self.limited = CurrentValueSubject(limited)
        self.tally = CurrentValueSubject(tally)
    }

    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { sessions.eraseToAnyPublisher() }
    var isLimitedModePublisher: AnyPublisher<Bool, Never> { limited.eraseToAnyPublisher() }
    var tokenTallyPublisher: AnyPublisher<TokenTally?, Never> { tally.eraseToAnyPublisher() }
    func start() { started = true }
    func stop() { started = false }
}

final class CompositeAgentProviderTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    private func session(
        _ id: String,
        kind: AgentKind,
        status: AgentStatus = .working,
        isActive: Bool = true
    ) -> AgentSession {
        AgentSession(
            id: id,
            projectPath: "/p/\(id)",
            status: status,
            stateChangedAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0),
            isActive: isActive,
            agentKind: kind
        )
    }

    func testMergesAndSortsAcrossProviders() {
        let claude = StubProvider(name: "Claude", sessions: [
            session("c-idle", kind: .claude, status: .idle),
            session("c-attention", kind: .claude, status: .needsAttention),
        ])
        let codex = StubProvider(name: "Codex", sessions: [
            session("x-working", kind: .codex, status: .working),
        ])
        let composite = CompositeAgentProvider(providers: [claude, codex])

        var received: [AgentSession] = []
        composite.sessionsPublisher
            .sink { received = $0 }
            .store(in: &cancellables)

        XCTAssertEqual(received.map(\.id), ["c-attention", "x-working", "c-idle"])
    }

    func testLimitedModeIsORed() {
        let a = StubProvider(name: "A", sessions: [], limited: false)
        let b = StubProvider(name: "B", sessions: [], limited: true)
        let composite = CompositeAgentProvider(providers: [a, b])

        var limited = false
        composite.isLimitedModePublisher
            .sink { limited = $0 }
            .store(in: &cancellables)
        XCTAssertTrue(limited)
    }

    func testTokenTalliesSum() {
        let a = StubProvider(name: "A", sessions: [], tally: TokenTally(tokens: 100_000))
        let b = StubProvider(name: "B", sessions: [], tally: TokenTally(tokens: 50_000, isApproximate: true))
        let c = StubProvider(name: "C", sessions: [], tally: nil)
        let composite = CompositeAgentProvider(providers: [a, b, c])

        var tally: TokenTally?
        composite.tokenTallyPublisher
            .sink { tally = $0 }
            .store(in: &cancellables)
        XCTAssertEqual(tally, TokenTally(tokens: 150_000, isApproximate: true))
    }

    func testStartStopForwarded() {
        let a = StubProvider(name: "A", sessions: [])
        let b = StubProvider(name: "B", sessions: [])
        let composite = CompositeAgentProvider(providers: [a, b])
        composite.start()
        XCTAssertTrue(a.started)
        XCTAssertTrue(b.started)
        composite.stop()
        XCTAssertFalse(a.started)
        XCTAssertFalse(b.started)
    }
}
