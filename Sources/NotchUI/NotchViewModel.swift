import AgentCore
import Combine
import Foundation

/// Observable state shared by the compact and expanded notch views.
@MainActor
public final class NotchViewModel: ObservableObject {
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var isLimitedMode = false
    /// Claude rate-limit windows (5h/7d/per-model); nil hides the block.
    @Published public private(set) var usage: UsageSnapshot?
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

    public func update(usage: UsageSnapshot?) {
        self.usage = usage
    }

    /// Panel grouping: main list capped at 5 (actives first, most recent
    /// inactive fill), routines in their own trailing section.
    public var groups: SessionListLayout.Groups {
        SessionListLayout.groups(from: sessions)
    }

    /// Compact-view counts consider active sessions only — a dead process
    /// can't be working or waiting on anyone. All active sessions count,
    /// even those beyond the panel's display cap.
    private var activeSessions: [AgentSession] { sessions.filter(\.isActive) }
    public var workingCount: Int { activeSessions.filter { $0.status == .working }.count }
    public var attentionCount: Int { activeSessions.filter { $0.status == .needsAttention }.count }
    public var idleCount: Int { activeSessions.filter { $0.status == .idle }.count }
}
