import Combine
import Foundation

/// Merges several `AgentProvider`s (Claude, Codex, Cursor, …) into one:
/// session lists are concatenated and re-sorted with the canonical ordering,
/// limited-mode flags are OR-ed, and token tallies are summed.
public final class CompositeAgentProvider: AgentProvider {
    public let providerName = "All agents"

    private let providers: [AgentProvider]

    public init(providers: [AgentProvider]) {
        precondition(!providers.isEmpty, "CompositeAgentProvider needs at least one provider")
        self.providers = providers
    }

    public var sessionsPublisher: AnyPublisher<[AgentSession], Never> {
        Self.combineLatest(providers.map(\.sessionsPublisher))
            .map { AgentSessionOrdering.standardSort($0.flatMap { $0 }) }
            .eraseToAnyPublisher()
    }

    public var isLimitedModePublisher: AnyPublisher<Bool, Never> {
        Self.combineLatest(providers.map(\.isLimitedModePublisher))
            .map { $0.contains(true) }
            .eraseToAnyPublisher()
    }

    public var tokenTallyPublisher: AnyPublisher<TokenTally?, Never> {
        Self.combineLatest(providers.map(\.tokenTallyPublisher))
            .map { tallies in
                let present = tallies.compactMap { $0 }
                guard !present.isEmpty else { return nil }
                return TokenTally(
                    tokens: present.map(\.tokens).reduce(0, +),
                    isApproximate: present.contains(where: \.isApproximate)
                )
            }
            .eraseToAnyPublisher()
    }

    public func start() {
        providers.forEach { $0.start() }
    }

    public func stop() {
        providers.forEach { $0.stop() }
    }

    /// combineLatest over an arbitrary number of publishers.
    private static func combineLatest<T>(
        _ publishers: [AnyPublisher<T, Never>]
    ) -> AnyPublisher<[T], Never> {
        guard let first = publishers.first else {
            return Just([]).eraseToAnyPublisher()
        }
        var combined: AnyPublisher<[T], Never> = first
            .map { [$0] }
            .eraseToAnyPublisher()
        for publisher in publishers.dropFirst() {
            combined = combined
                .combineLatest(publisher) { $0 + [$1] }
                .eraseToAnyPublisher()
        }
        return combined
    }
}
