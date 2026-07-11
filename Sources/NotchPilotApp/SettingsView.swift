import SettingsStore
import SwiftUI

/// Actions the settings UI needs from the app coordinator.
struct SettingsActions {
    var hooksInstalled: () -> Bool
    var installHooks: () -> Void
    var uninstallHooks: () -> Void
    var updatesAvailable: () -> Bool
    var checkForUpdates: () -> Void
}

/// Settings window (design spec §2): launch at login, auto-peek toggle,
/// staleness timeout, hooks management, check for updates.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let actions: SettingsActions

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var hooksInstalled = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                    }
                Toggle("Show Claude usage limits", isOn: $settings.showUsage)
                Stepper(
                    "Remove stale sessions after \(settings.stalenessTimeoutMinutes) min",
                    value: $settings.stalenessTimeoutMinutes,
                    in: 5...240,
                    step: 5
                )
            }

            Section("Claude Code hooks") {
                HStack {
                    Image(systemName: hooksInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hooksInstalled ? .green : .orange)
                    Text(hooksInstalled
                        ? "Hooks installed — full status accuracy"
                        : "Hooks not installed — running in limited mode")
                }
                .font(.callout)
                if hooksInstalled {
                    Button("Remove hooks") {
                        actions.uninstallHooks()
                        refreshStatus()
                    }
                } else {
                    Button("Install hooks") {
                        actions.installHooks()
                        refreshStatus()
                    }
                }
                Text("Hooks are a reversible edit to ~/.claude/settings.json; a timestamped backup is made before every change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if actions.updatesAvailable() {
                Section("Updates") {
                    Button("Check for updates…") {
                        actions.checkForUpdates()
                    }
                }
            }

            Section("About") {
                Text("NotchPilot \(appVersion)")
                    .font(.callout)
                Text("""
                Local processing. Network traffic: the Sparkle update check, \
                and — when usage limits are shown — Anthropic's usage endpoint, \
                queried with Claude Code's own credentials from your Keychain.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshStatus)
    }

    private func refreshStatus() {
        hooksInstalled = actions.hooksInstalled()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
