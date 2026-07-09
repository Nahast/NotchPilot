import AgentCore
import Combine
import Foundation

/// Hidden demo mode (design spec §7): feeds synthetic sessions for
/// screenshots and QA. Activated with `--demo` or the `demoMode` default.
final class DemoProvider: AgentProvider {
    let providerName = "Demo"

    private let sessionsSubject = CurrentValueSubject<[AgentSession], Never>([])
    private let limitedSubject = CurrentValueSubject<Bool, Never>(false)
    private var timer: Timer?
    private var tick = 0

    var sessionsPublisher: AnyPublisher<[AgentSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    var isLimitedModePublisher: AnyPublisher<Bool, Never> {
        limitedSubject.eraseToAnyPublisher()
    }

    func start() {
        guard timer == nil else { return }
        emit()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.emit()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        sessionsSubject.send(Self.scenario(tick: tick, now: Date()))
    }

    static func scenario(tick: Int, now: Date) -> [AgentSession] {
        let activities = [
            "Editing NotchPresenter.swift…",
            "Running: swift test",
            "Searching \"AgentStatus\"…",
            "Reading Package.swift…",
        ]
        var sessions = [
            AgentSession(
                id: "demo-routine",
                projectPath: "/Users/romain/Projects/warp-api",
                status: .working,
                activity: "Running: /backlog-tick",
                contextUsedTokens: 48_000,
                contextWindowTokens: 200_000,
                stateChangedAt: now.addingTimeInterval(-95),
                lastActivityAt: now,
                name: "backlog-tick",
                isRoutine: true
            ),
            AgentSession(
                id: "demo-api",
                projectPath: "/Users/romain/Projects/warp-api",
                status: .working,
                activity: activities[tick % activities.count],
                contextUsedTokens: min(30_000 + tick * 9_000, 190_000),
                contextWindowTokens: 200_000,
                stateChangedAt: now.addingTimeInterval(-Double(40 + tick * 6)),
                lastActivityAt: now,
                name: "warp-api-3f"
            ),
            AgentSession(
                id: "demo-web",
                projectPath: "/Users/romain/Projects/webapp",
                status: tick % 3 == 0 ? .working : .needsAttention,
                activity: tick % 3 == 0
                    ? "Running: npm run build"
                    : "Claude needs your permission to use Bash",
                contextUsedTokens: 152_000,
                contextWindowTokens: 200_000,
                stateChangedAt: now.addingTimeInterval(-Double(170 + (tick % 3) * 30)),
                lastActivityAt: now,
                name: "Fix login flow",
                pullRequest: PullRequestInfo(number: 42, state: .open)
            ),
            AgentSession(
                id: "demo-docs",
                projectPath: "/Users/romain/Projects/docs-site",
                status: .idle,
                activity: "Done",
                contextUsedTokens: 61_000,
                contextWindowTokens: 200_000,
                stateChangedAt: now.addingTimeInterval(-540),
                lastActivityAt: now.addingTimeInterval(-540),
                name: "Docs site polish",
                isActive: false,
                pullRequest: PullRequestInfo(number: 41, state: .merged)
            ),
        ]
        // Mirror the provider's sort: regular sessions before routines,
        // active first, then attention, working, idle.
        sessions.sort { lhs, rhs in
            func rank(_ status: AgentStatus) -> Int {
                switch status {
                case .needsAttention: return 0
                case .working: return 1
                case .idle: return 2
                }
            }
            if lhs.isRoutine != rhs.isRoutine { return !lhs.isRoutine }
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return rank(lhs.status) < rank(rhs.status)
        }
        return sessions
    }
}
