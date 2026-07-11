import SwiftUI

/// First-run window (design spec §2): explains the app, asks consent for the
/// one setup step (Claude Code hooks), and warns about the iTerm2 automation
/// prompt. If `~/.claude` is missing, shows "Claude Code not detected".
struct OnboardingView: View {
    let claudeDetected: Bool
    let onInstallHooks: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if claudeDetected {
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
            Claude Code sessions: what each agent is doing, when one is waiting \
            on you, and how much of its context window is used. Click a session \
            to jump to its terminal.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
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
                    untouched, and you can remove them anytime from Settings.
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
                    Label("Claude Code not detected", systemImage: "questionmark.folder")
                        .font(.headline)
                    Text("""
                    NotchPilot could not find ~/.claude on this Mac. Install and \
                    run Claude Code at least once, then reopen NotchPilot — it \
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
