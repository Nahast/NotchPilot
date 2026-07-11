import AgentCore
import SwiftUI

/// Per-provider onboarding shown when reconnecting an agent from Settings —
/// the same consent flow as first-run, scoped to one agent.
struct AgentConnectView: View {
    let agent: AgentDetection
    let onConnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect \(agent.name)")
                .font(.title3.bold())
            Text(introText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label(setupTitle, systemImage: setupIcon)
                        .font(.headline)
                    Text(setupText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            Text("NotchPilot only reads local files; nothing leaves your Mac.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(confirmTitle, action: onConnect)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var introText: String {
        "Sessions from \(agent.name) will reappear in the notch: live status, "
            + "activity, and click-to-jump."
    }

    private var setupTitle: String {
        switch agent.kind {
        case .claude, .cursor: return "One setup step"
        default: return "No setup needed"
        }
    }

    private var setupIcon: String {
        switch agent.kind {
        case .claude, .cursor: return "wrench.and.screwdriver"
        default: return "checkmark.seal"
        }
    }

    private var setupText: String {
        switch agent.kind {
        case .claude:
            return "Reconnecting re-registers Claude Code hooks — a safe, "
                + "reversible edit to ~/.claude/settings.json with a timestamped "
                + "backup made first. Your own hooks are untouched."
        case .cursor:
            return "Reconnecting re-registers Cursor hooks — a safe, reversible "
                + "edit to ~/.cursor/hooks.json with a timestamped backup made "
                + "first. Your own hooks are untouched."
        default:
            return "Codex transcripts carry status events natively, so NotchPilot "
                + "just resumes reading ~/.codex/sessions. No files are modified."
        }
    }

    private var confirmTitle: String {
        switch agent.kind {
        case .claude, .cursor: return "Install hooks & connect"
        default: return "Connect"
        }
    }
}
