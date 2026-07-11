import AgentCore
import SwiftUI

/// One supported agent: whether its home directory was found and whether
/// the user currently has it connected (monitored).
struct AgentDetection: Identifiable {
    let kind: AgentKind
    let name: String
    let icon: String
    let detected: Bool
    var enabled: Bool = true
    var id: String { name }
}

/// First-run window (design spec §2): explains the app, shows which agents
/// were detected, asks consent for the one setup step (Claude Code + Cursor
/// hooks), and warns about the iTerm2 automation prompt.
struct OnboardingView: View {
    let agents: [AgentDetection]
    let onInstallHooks: () -> Void
    let onSkip: () -> Void

    private var anyDetected: Bool { agents.contains(where: \.detected) }
    private var cursorDetected: Bool {
        agents.contains { $0.name == "Cursor" && $0.detected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            detectionList
            if anyDetected {
                consentContent
            } else {
                notDetectedContent
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to NotchPilot")
                .font(.title2.bold())
            Text("""
            NotchPilot lives in your notch and shows the live status of your \
            AI coding agents — Claude Code, Codex, and Cursor: what each one \
            is doing, when one is waiting on you, and how much context it has \
            used. Click a session to jump to its window.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detectionList: some View {
        HStack(spacing: 14) {
            ForEach(agents) { agent in
                HStack(spacing: 5) {
                    Image(systemName: agent.detected ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(agent.detected ? .green : .secondary)
                    Text(agent.name)
                        .font(.callout)
                        .foregroundStyle(agent.detected ? .primary : .secondary)
                }
                .help(agent.detected
                    ? "\(agent.name) detected — sessions will appear in the notch"
                    : "\(agent.name) not found on this Mac")
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var consentContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("One setup step", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                    Text("""
                    For reliable status updates, NotchPilot registers Claude Code \
                    hooks — a safe, reversible edit to ~/.claude/settings.json. \
                    A timestamped backup is made first, your existing hooks are \
                    untouched, and you can remove them anytime from Settings.\
                    \(cursorDetected ? " Cursor hooks (~/.cursor/hooks.json) are managed the same way." : "")
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("""
                    If you skip this, NotchPilot runs in limited mode: statuses \
                    are estimated from transcript activity only.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            Label {
                Text("""
                Heads-up: the first time you click a session to jump to iTerm2, \
                macOS will ask to allow NotchPilot to control iTerm2.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.orange)
            }

            Text("NotchPilot is 100% local. The only network traffic is the update check.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Skip — limited mode", action: onSkip)
                Button("Install hooks", action: onInstallHooks)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var notDetectedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No agents detected", systemImage: "questionmark.folder")
                        .font(.headline)
                    Text("""
                    NotchPilot could not find Claude Code (~/.claude), Codex \
                    (~/.codex), or Cursor (~/.cursor) on this Mac. Install and \
                    run one of them at least once, then reopen NotchPilot — it \
                    will offer to finish setup.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Link(
                        "Get Claude Code",
                        destination: URL(string: "https://claude.com/claude-code")!
                    )
                    .font(.caption)
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Continue anyway", action: onSkip)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
