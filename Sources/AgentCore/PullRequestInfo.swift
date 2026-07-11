import Foundation

/// Pull request attached to a session, as known locally (the desktop app
/// persists PR identity and state; live CI check results are not stored).
public struct PullRequestInfo: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case open = "OPEN"
        case merged = "MERGED"
        case closed = "CLOSED"
    }

    public var number: Int
    public var state: State
    public var url: String?

    public init(number: Int, state: State, url: String? = nil) {
        self.number = number
        self.state = state
        self.url = url
    }
}
