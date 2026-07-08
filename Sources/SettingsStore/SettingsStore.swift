import Combine
import Foundation

/// UserDefaults-backed preferences (design spec §3).
public final class SettingsStore: ObservableObject {
    private enum Keys {
        static let autoPeek = "autoPeek"
        static let stalenessTimeoutMinutes = "stalenessTimeoutMinutes"
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let hooksConsentGranted = "hooksConsentGranted"
        static let demoMode = "demoMode"
    }

    private let defaults: UserDefaults

    /// Auto-peek the panel for a few seconds when a session needs attention.
    @Published public var autoPeek: Bool {
        didSet { defaults.set(autoPeek, forKey: Keys.autoPeek) }
    }

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

    public var stalenessTimeout: TimeInterval {
        TimeInterval(max(1, stalenessTimeoutMinutes)) * 60
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.autoPeek: true,
            Keys.stalenessTimeoutMinutes: 30,
            Keys.didCompleteOnboarding: false,
            Keys.hooksConsentGranted: false,
            Keys.demoMode: false,
        ])
        autoPeek = defaults.bool(forKey: Keys.autoPeek)
        stalenessTimeoutMinutes = defaults.integer(forKey: Keys.stalenessTimeoutMinutes)
        didCompleteOnboarding = defaults.bool(forKey: Keys.didCompleteOnboarding)
        hooksConsentGranted = defaults.bool(forKey: Keys.hooksConsentGranted)
        demoMode = defaults.bool(forKey: Keys.demoMode)
    }
}
