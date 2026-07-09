import Foundation

/// A live AI coding agent session as displayed in the notch.
public struct AgentSession: Identifiable, Equatable, Sendable {
    /// Stable session identifier (Claude Code session UUID).
    public var id: String
    /// Absolute path of the session's working directory.
    public var projectPath: String
    /// Current status class.
    public var status: AgentStatus
    /// One-line description of the current activity ("Editing main.swift…").
    public var activity: String?
    /// Tokens currently occupying the model's context window, if known.
    public var contextUsedTokens: Int?
    /// Size of the model's context window in tokens, if known.
    public var contextWindowTokens: Int?
    /// When `status` last changed — drives "waiting 3m".
    public var stateChangedAt: Date
    /// Last time any signal (hook event or transcript write) arrived.
    public var lastActivityAt: Date
    /// True when the status was derived from transcript heuristics only (no hooks).
    public var isLimitedMode: Bool
    /// Human session name from the provider's session registry ("droplet-a1").
    public var name: String?
    /// True while the session's process is alive (or its activity is very
    /// recent when no registry entry exists). Drives Active/Inactive grouping.
    public var isActive: Bool
    /// True for scheduled/background runs (routines) — pinned to the top.
    public var isRoutine: Bool

    public init(
        id: String,
        projectPath: String,
        status: AgentStatus,
        activity: String? = nil,
        contextUsedTokens: Int? = nil,
        contextWindowTokens: Int? = nil,
        stateChangedAt: Date,
        lastActivityAt: Date,
        isLimitedMode: Bool = false,
        name: String? = nil,
        isActive: Bool = true,
        isRoutine: Bool = false
    ) {
        self.id = id
        self.projectPath = projectPath
        self.status = status
        self.activity = activity
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
        self.stateChangedAt = stateChangedAt
        self.lastActivityAt = lastActivityAt
        self.isLimitedMode = isLimitedMode
        self.name = name
        self.isActive = isActive
        self.isRoutine = isRoutine
    }

    /// Folder name of the working directory.
    public var projectName: String {
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty ? projectPath : name
    }

    /// Row title: the session's own name when known, else the folder name.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return projectName
    }

    /// Fraction (0...1) of the context window consumed, if both numbers are known.
    public var contextUsageFraction: Double? {
        guard let used = contextUsedTokens,
              let window = contextWindowTokens,
              window > 0
        else { return nil }
        return min(1.0, max(0.0, Double(used) / Double(window)))
    }
}
