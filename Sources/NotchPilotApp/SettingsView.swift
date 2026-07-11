import AgentCore
import SettingsStore
import SwiftUI

/// Actions the settings UI needs from the app coordinator.
struct SettingsActions {
    var hooksInstalled: () -> Bool
    var installHooks: () -> Void
    var uninstallHooks: () -> Void
    var updatesAvailable: () -> Bool
    var checkForUpdates: () -> Void
    var detectedAgents: () -> [AgentDetection]
    var connectAgent: (AgentKind) -> Void
    var disconnectAgent: (AgentKind) -> Void
}

/// Settings window (design spec §2): launch at login, auto-peek toggle,
/// staleness timeout, hooks management, check for updates.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let actions: SettingsActions

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var hooksInstalled = false
    @State private var agents: [AgentDetection] = []
    /// Agent whose per-provider onboarding sheet is showing.
    @State private var connectTarget: AgentDetection?

    var body: some View {
        // Two columns so the window stays short: controls on the left,
        // hooks/usage/about on the right.
        HStack(alignment: .top, spacing: 0) {
            Form {
                generalSection
                connectedAgentsSection
            }
            .formStyle(.grouped)
            .frame(width: 380)

            Form {
                hooksSection
                usageDataSection
                if actions.updatesAvailable() {
                    updatesSection
                }
                aboutSection
            }
            .formStyle(.grouped)
            .frame(width: 380)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshStatus)
        .sheet(item: $connectTarget) { agent in
            AgentConnectView(
                agent: agent,
                onConnect: {
                    actions.connectAgent(agent.kind)
                    connectTarget = nil
                    refreshStatus()
                },
                onCancel: { connectTarget = nil }
            )
        }
    }

    // MARK: Left column

    private var generalSection: some View {
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
    }

    private var connectedAgentsSection: some View {
        Section("Connected agents") {
            ForEach(agents) { agent in
                agentRow(agent)
            }
            Text("Disconnecting stops all monitoring for that agent and removes its hooks. Reconnect anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Right column

    private var hooksSection: some View {
        Section("Agent hooks") {
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
            Text("""
            Hooks are reversible edits to ~/.claude/settings.json and — when \
            Cursor is installed — ~/.cursor/hooks.json; a timestamped backup \
            is made before every change. Codex needs no hooks: its \
            transcripts carry status events natively.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var usageDataSection: some View {
        Section("Usage data") {
            Label {
                Text("""
                To show Claude rate-limit usage in the notch window, you \
                must be signed in to Claude Code in the terminal — run \
                `claude login` if the usage bars don't appear. NotchPilot \
                reads the credentials Claude Code stores in your Keychain; \
                macOS asks for permission once.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var updatesSection: some View {
        Section("Updates") {
            Button("Check for updates…") {
                actions.checkForUpdates()
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack(spacing: 8) {
                Text("NotchPilot \(appVersion)")
                    .font(.callout)
                Text("BETA")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.55), lineWidth: 1))
                    .help("NotchPilot is a beta — expect rough edges; feedback welcome")
            }
            Text("""
            Local processing. Network traffic: the Sparkle update check, \
            and — when usage limits are shown — Anthropic's usage endpoint, \
            queried with Claude Code's own credentials from your Keychain.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Questions or feedback?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("rjouffret@warp-lab.ai",
                     destination: URL(string: "mailto:rjouffret@warp-lab.ai")!)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentDetection) -> some View {
        HStack {
            Image(systemName: statusIcon(for: agent))
                .foregroundStyle(statusColor(for: agent))
            Text(agent.name)
            Spacer()
            if !agent.detected {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if agent.enabled {
                Text("Monitoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Disconnect") {
                    actions.disconnectAgent(agent.kind)
                    refreshStatus()
                }
            } else {
                Text("Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Connect…") {
                    connectTarget = agent
                }
            }
        }
        .font(.callout)
    }

    private func statusIcon(for agent: AgentDetection) -> String {
        if !agent.detected { return "circle.dashed" }
        return agent.enabled ? "checkmark.circle.fill" : "pause.circle"
    }

    private func statusColor(for agent: AgentDetection) -> Color {
        if !agent.detected { return .secondary }
        return agent.enabled ? .green : .orange
    }

    private func refreshStatus() {
        hooksInstalled = actions.hooksInstalled()
        launchAtLogin = LaunchAtLogin.isEnabled
        agents = actions.detectedAgents()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
