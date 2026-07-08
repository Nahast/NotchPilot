import AgentCore
import Combine
import Foundation

/// Observable state shared by the compact and expanded notch views.
@MainActor
public final class NotchViewModel: ObservableObject {
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var isLimitedMode = false
    /// Mirrored from the presenter's hover tracking.
    @Published public var isHovering = false
    /// True while an auto-peek is holding the panel open.
    @Published public var isPeeking = false
    /// True on displays without a physical notch: the expanded window is the
    /// only state DynamicNotchKit supports there, so the content itself
    /// renders as a small pill until hovered (design spec §2).
    @Published public var showsAsFloatingPill = false

    /// Click a row → jump to the session.
    public var onJump: ((AgentSession) -> Void)?
    /// Gear icon → open Settings.
    public var onOpenSettings: (() -> Void)?

    public init() {}

    public func update(sessions: [AgentSession]) {
        self.sessions = sessions
    }

    public func update(isLimitedMode: Bool) {
        self.isLimitedMode = isLimitedMode
    }

    public var workingCount: Int { sessions.filter { $0.status == .working }.count }
    public var attentionCount: Int { sessions.filter { $0.status == .needsAttention }.count }
    public var idleCount: Int { sessions.filter { $0.status == .idle }.count }
}
