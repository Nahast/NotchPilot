import Combine
import Foundation

/// UserDefaults-backed preferences (design spec §3).
public final class SettingsStore: ObservableObject {
    private enum Keys {
        static let stalenessTimeoutMinutes = "stalenessTimeoutMinutes"
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let hooksConsentGranted = "hooksConsentGranted"
        static let demoMode = "demoMode"
        static let showUsage = "showUsage"
        static let claudeEnabled = "agentClaudeEnabled"
        static let codexEnabled = "agentCodexEnabled"
        static let cursorEnabled = "agentCursorEnabled"
    }

    private let defaults: UserDefaults

    /// Sessions without any signal for this long are removed.
    @Published public var stalenessTimeoutMinutes: Int {
        didSet { defaults.set(stalenessTimeoutMinutes, forKey: Keys.stalenessTimeoutMinutes) }
    }

    @Published public var didCompleteOnboarding: Bool {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }

    /// The user consented to installing Claude Code hooks during onboarding.
    @Published public var hooksConsentGranted: Bool {
        didSet { defaults.set(hooksConsentGranted, forKey: Keys.hooksConsentGranted) }
    }

    /// Hidden flag: feed synthetic sessions for screenshots and QA (spec §7).
    @Published public var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Keys.demoMode) }
    }

    /// Show Claude rate-limit usage in the panel (fetched from Anthropic's
    /// usage endpoint using Claude Code's own credentials).
    @Published public var showUsage: Bool {
        didSet { defaults.set(showUsage, forKey: Keys.showUsage) }
    }

    /// Per-agent connections: disconnecting stops monitoring that agent (and
    /// removes its hooks); reconnecting goes through that agent's onboarding.
    @Published public var claudeEnabled: Bool {
        didSet { defaults.set(claudeEnabled, forKey: Keys.claudeEnabled) }
    }

    @Published public var codexEnabled: Bool {
        didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) }
    }

    @Published public var cursorEnabled: Bool {
        didSet { defaults.set(cursorEnabled, forKey: Keys.cursorEnabled) }
    }

    public var stalenessTimeout: TimeInterval {
        TimeInterval(max(1, stalenessTimeoutMinutes)) * 60
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.stalenessTimeoutMinutes: 30,
            Keys.didCompleteOnboarding: false,
            Keys.hooksConsentGranted: false,
            Keys.demoMode: false,
            Keys.showUsage: true,
            Keys.claudeEnabled: true,
            Keys.codexEnabled: true,
            Keys.cursorEnabled: true,
        ])
        stalenessTimeoutMinutes = defaults.integer(forKey: Keys.stalenessTimeoutMinutes)
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        hooksConsentGranted = defaults.bool(forKey: Keys.hooksConsentGranted)
        demoMode = defaults.bool(forKey: Keys.demoMode)
        showUsage = defaults.bool(forKey: Keys.showUsage)
        claudeEnabled = defaults.bool(forKey: Keys.claudeEnabled)
        codexEnabled = defaults.bool(forKey: Keys.codexEnabled)
        cursorEnabled = defaults.bool(forKey: Keys.cursorEnabled)
    }
}
