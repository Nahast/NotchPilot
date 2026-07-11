import AgentCore
import AppKit
import ClaudeCodeProvider
import CodexProvider
import Combine
import CursorProvider
import HookInstaller
import JumpService
import NotchUI
import SettingsStore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var provider: AgentProvider?
    private var claudeProvider: ClaudeCodeProvider?
    private var cursorHooksInstaller: CursorHooksInstaller?
    private var helperURL: URL!
    private var demoMode = false
    /// Subscriptions tied to the current provider stack — cleared and
    /// re-created whenever an agent is connected or disconnected.
    private var providerCancellables = Set<AnyCancellable>()
    private var model: NotchViewModel!
    private var presenter: NotchPresenter!
    private var jumpService: JumpService!
    private var updateService: UpdateService!
    private var usageService: UsageService!
    private var hookInstaller: HookInstaller!
    private var cancellables = Set<AnyCancellable>()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings = SettingsStore()
        demoMode = CommandLine.arguments.contains("--demo") || settings.demoMode
        let demoMode = self.demoMode

        // Scriptable setup: `open NotchPilot.app --args --enable-launch-at-login`
        if CommandLine.arguments.contains("--enable-launch-at-login") {
            LaunchAtLogin.setEnabled(true)
            NSLog("NotchPilot: launch at login now %@", LaunchAtLogin.isEnabled ? "enabled" : "NOT enabled")
        }

        helperURL = HelperDeployer.deployIfNeeded() ?? ClaudeCodePaths.defaultHelperInstallURL
        hookInstaller = HookInstaller(
            settingsURL: ClaudeCodePaths.defaultClaudeHome.appendingPathComponent("settings.json"),
            helperPath: helperURL.path
        )
        let cursorHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
        if FileManager.default.fileExists(atPath: cursorHome.path) {
            cursorHooksInstaller = CursorHooksInstaller(
                hooksURL: cursorHome.appendingPathComponent("hooks.json"),
                helperPath: helperURL.path
            )
        }

        model = NotchViewModel()
        jumpService = JumpService()
        updateService = UpdateService()

        model.onJump = { [weak self] session in
            self?.jumpService.jump(to: session)
        }
        model.onOpenSettings = { [weak self] in
            self?.showSettingsWindow()
        }

        configureProviders()

        presenter = DynamicNotchKitPresenter(model: model)

        let settingsStore = settings!
        usageService = UsageService(isEnabled: { settingsStore.showUsage })
        usageService.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.model.update(usage: snapshot)
                }
            }
            .store(in: &cancellables)
        usageService.signedOutPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signedOut in
                Task { @MainActor [weak self] in
                    self?.model.update(usageSignedOut: signedOut)
                }
            }
            .store(in: &cancellables)
        if demoMode {
            model.update(usage: Self.demoUsage())
        } else {
            usageService.start()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presenter.refresh()
            }
        }

        // Providers were already started by configureProviders().
        presenter.show()

        if !settings.didCompleteOnboarding, !demoMode {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        provider?.stop()
        usageService?.stop()
    }

    private static func demoUsage() -> UsageSnapshot {
        UsageSnapshot(
            windows: [
                UsageWindow(key: "five_hour", label: "5-hour limit", usedFraction: 0.16, resetsAt: Date().addingTimeInterval(2.4 * 3600)),
                UsageWindow(key: "seven_day", label: "Weekly · all models", usedFraction: 0.19, resetsAt: Date().addingTimeInterval(4.2 * 86_400)),
                UsageWindow(key: "seven_day_fable", label: "Weekly · Fable", usedFraction: 0.34, resetsAt: Date().addingTimeInterval(4.2 * 86_400)),
            ],
            fetchedAt: Date()
        )
    }

    // MARK: Provider stack (rebuilt when agents connect/disconnect)

    /// Builds and starts the provider stack from the per-agent connection
    /// flags. Called at launch and again whenever a connection flips —
    /// disconnected agents' watchers are fully torn down, not just filtered.
    private func configureProviders() {
        provider?.stop()
        providerCancellables.removeAll()
        claudeProvider = nil

        if demoMode {
            provider = DemoProvider()
        } else {
            let installer = hookInstaller!
            let settingsStore = settings!
            var providers: [AgentProvider] = []

            if settingsStore.claudeEnabled {
                let claude = ClaudeCodeProvider(configuration: .init(
                    stalenessTimeout: { settingsStore.stalenessTimeout },
                    hooksInstalled: { installer.isInstalled() }
                ))
                claudeProvider = claude
                providers.append(claude)
            }

            // Codex (OpenAI): rollout transcripts carry the status events.
            let codexHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
            if settingsStore.codexEnabled, FileManager.default.fileExists(atPath: codexHome.path) {
                providers.append(CodexProvider(configuration: .init(
                    codexHome: codexHome,
                    stalenessTimeout: { settingsStore.stalenessTimeout }
                )))
            }

            // Cursor: hooks.json events spooled by the helper.
            if settingsStore.cursorEnabled, let cursorInstaller = cursorHooksInstaller {
                if settingsStore.hooksConsentGranted {
                    do {
                        try cursorInstaller.install()
                    } catch {
                        NSLog("NotchPilot: Cursor hooks install failed: %@", error.localizedDescription)
                    }
                }
                providers.append(CursorProvider(configuration: .init(
                    eventsDirectory: ClaudeCodePaths.defaultApplicationSupport
                        .appendingPathComponent(CursorHooksInstaller.spoolSubdirectory, isDirectory: true),
                    stalenessTimeout: { settingsStore.stalenessTimeout }
                )))
            }

            switch providers.count {
            case 0: provider = nil
            case 1: provider = providers[0]
            default: provider = CompositeAgentProvider(providers: providers)
            }
        }

        guard let provider else {
            // Everything disconnected: clear the notch state.
            model.update(sessions: [])
            model.update(isLimitedMode: false)
            model.update(tokenTally: nil)
            return
        }

        provider.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                Task { @MainActor [weak self] in
                    self?.model.update(sessions: sessions)
                }
            }
            .store(in: &providerCancellables)
        provider.isLimitedModePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] limited in
                Task { @MainActor [weak self] in
                    self?.model.update(isLimitedMode: limited)
                }
            }
            .store(in: &providerCancellables)
        provider.tokenTallyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tally in
                Task { @MainActor [weak self] in
                    self?.model.update(tokenTally: tally)
                }
            }
            .store(in: &providerCancellables)
        provider.start()
    }

    // MARK: Agent connections

    /// Which supported agents exist on this Mac and whether they're connected.
    func detectAgents() -> [AgentDetection] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func found(_ dir: String) -> Bool {
            FileManager.default.fileExists(atPath: home.appendingPathComponent(dir).path)
        }
        return [
            AgentDetection(kind: .claude, name: "Claude Code", icon: "asterisk",
                           detected: found(".claude"), enabled: settings.claudeEnabled),
            AgentDetection(kind: .codex, name: "Codex", icon: "hexagon",
                           detected: found(".codex"), enabled: settings.codexEnabled),
            AgentDetection(kind: .cursor, name: "Cursor", icon: "cursorarrow",
                           detected: found(".cursor"), enabled: settings.cursorEnabled),
        ]
    }

    /// Reconnect an agent after its per-provider onboarding: re-enable
    /// monitoring and (re)install that agent's hooks.
    func connectAgent(_ kind: AgentKind) {
        switch kind {
        case .claude:
            settings.claudeEnabled = true
            do {
                try hookInstaller.install()
                settings.hooksConsentGranted = true
            } catch {
                NSLog("NotchPilot: Claude hooks install failed: %@", error.localizedDescription)
            }
        case .codex:
            settings.codexEnabled = true // no hooks needed
        case .cursor:
            settings.cursorEnabled = true
            settings.hooksConsentGranted = true
            // configureProviders() performs the actual hooks install.
        case .other:
            break
        }
        configureProviders()
    }

    /// Disconnect an agent: tear down its watchers and remove its hooks.
    /// Fully reversible via Connect (per-provider onboarding).
    func disconnectAgent(_ kind: AgentKind) {
        switch kind {
        case .claude:
            settings.claudeEnabled = false
            do {
                try hookInstaller.uninstall()
            } catch {
                NSLog("NotchPilot: Claude hooks removal failed: %@", error.localizedDescription)
            }
        case .codex:
            settings.codexEnabled = false
        case .cursor:
            settings.cursorEnabled = false
            do {
                try cursorHooksInstaller?.uninstall()
            } catch {
                NSLog("NotchPilot: Cursor hooks removal failed: %@", error.localizedDescription)
            }
        case .other:
            break
        }
        configureProviders()
    }

    private func showOnboarding() {
        let view = OnboardingView(
            agents: detectAgents(),
            onInstallHooks: { [weak self] in self?.finishOnboarding(installHooks: true) },
            onSkip: { [weak self] in self?.finishOnboarding(installHooks: false) }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to NotchPilot"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding(installHooks: Bool) {
        if installHooks {
            installHooksWithFeedback()
        }
        settings.didCompleteOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        claudeProvider?.rescanNow()
    }

    /// Install hooks; on malformed settings.json fall back to limited mode
    /// rather than risk breaking the user's Claude Code setup (spec §5).
    @discardableResult
    private func installHooksWithFeedback() -> Bool {
        do {
            try hookInstaller.install()
            settings.hooksConsentGranted = true
            claudeProvider?.rescanNow()
            // Cursor hooks share the same consent — but respect an explicit
            // per-agent disconnect; reconnecting Cursor is its own flow.
            if settings.cursorEnabled {
                try? cursorHooksInstaller?.install()
            }
            return true
        } catch {
            settings.hooksConsentGranted = false
            let alert = NSAlert()
            alert.messageText = "Could not install Claude Code hooks"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    private func uninstallHooksWithFeedback() {
        do {
            try hookInstaller.uninstall()
            try? cursorHooksInstaller?.uninstall()
            settings.hooksConsentGranted = false
            claudeProvider?.rescanNow()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not remove Claude Code hooks"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: Settings window

    private func showSettingsWindow() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(
            settings: settings,
            actions: SettingsActions(
                hooksInstalled: { [weak self] in self?.hookInstaller.isInstalled() ?? false },
                installHooks: { [weak self] in self?.installHooksWithFeedback() },
                uninstallHooks: { [weak self] in self?.uninstallHooksWithFeedback() },
                updatesAvailable: { [weak self] in self?.updateService.isAvailable ?? false },
                checkForUpdates: { [weak self] in self?.updateService.checkForUpdates() },
                detectedAgents: { [weak self] in self?.detectAgents() ?? [] },
                connectAgent: { [weak self] kind in self?.connectAgent(kind) },
                disconnectAgent: { [weak self] kind in self?.disconnectAgent(kind) }
            )
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "NotchPilot Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
