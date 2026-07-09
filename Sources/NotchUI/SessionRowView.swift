import AgentCore
import SwiftUI

/// One row per session: status dot, session name + branch, one-line activity,
/// then a chip row (status, model, context %). Needs-attention rows get an
/// orange leading edge.
struct SessionRowView: View {
    let session: AgentSession
    var onJump: (AgentSession) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            StatusDotView(status: session.status, isActive: session.isActive)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                titleLine
                Text(activityText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                chipLine
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .opacity(session.isActive ? 1 : 0.55)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onJump(session) }
        .help(helpText)
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "asterisk")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NotchTheme.accent)
            Text(session.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let branch = session.gitBranch, !branch.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white.opacity(0.4))
            }
            if session.isRoutine {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .help("Routine (scheduled run)")
            }
            Spacer(minLength: 4)
            if let pullRequest = session.pullRequest {
                PullRequestDot(pullRequest: pullRequest)
            }
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(Self.stateDurationText(for: session, now: context.date))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private var chipLine: some View {
        HStack(spacing: 6) {
            statusChip
            if let model = ModelDisplayName.displayName(for: session.model) {
                ChipView(text: model, icon: "cpu")
            }
            if let fraction = session.contextUsageFraction {
                ChipView(
                    text: "\(Int((fraction * 100).rounded()))%",
                    icon: "speedometer",
                    color: contextColor(fraction)
                )
                .help("Context window used")
            }
        }
    }

    private var statusChip: some View {
        switch session.status {
        case .needsAttention:
            return ChipView(
                text: "NEEDS YOU",
                icon: "exclamationmark.triangle",
                color: NotchTheme.accent,
                emphasized: true
            )
        case .working:
            return ChipView(
                text: "WORKING",
                icon: "bolt",
                color: NotchTheme.working,
                emphasized: true
            )
        case .idle:
            return ChipView(
                text: session.isActive ? "IDLE" : "CLOSED",
                color: Color.white.opacity(0.45)
            )
        }
    }

    private func contextColor(_ fraction: Double) -> Color {
        if fraction < 0.7 { return Color.white.opacity(0.6) }
        if fraction < 0.9 { return .orange }
        return .red
    }

    @ViewBuilder
    private var rowBackground: some View {
        let needsAttention = session.status == .needsAttention
        RoundedRectangle(cornerRadius: 9)
            .fill(
                needsAttention
                    ? NotchTheme.accent.opacity(hovering ? 0.14 : 0.09)
                    : Color.white.opacity(hovering ? 0.08 : 0.0)
            )
            .overlay(alignment: .leading) {
                if needsAttention {
                    Capsule()
                        .fill(NotchTheme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
    }

    private var activityText: String {
        if let activity = session.activity, !activity.isEmpty {
            return activity
        }
        switch session.status {
        case .working: return "Working…"
        case .needsAttention: return "Waiting for your approval"
        case .idle: return session.isActive ? "Idle" : "Closed"
        }
    }

    private var helpText: String {
        var text = "Click to jump to this session — \(session.projectPath)"
        if let fraction = session.contextUsageFraction {
            text += " · context \(Int((fraction * 100).rounded()))%"
        }
        return text
    }

    /// "waiting 3m" / "done 12m" / "45s" (design spec §2).
    static func stateDurationText(for session: AgentSession, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(session.stateChangedAt)))
        let duration: String
        if seconds < 60 {
            duration = "\(seconds)s"
        } else if seconds < 3600 {
            duration = "\(seconds / 60)m"
        } else {
            duration = "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        switch session.status {
        case .needsAttention: return "waiting \(duration)"
        case .idle: return "done \(duration)"
        case .working: return duration
        }
    }
}

/// Leading status dot: green working, orange (pulsing) attention, dim idle.
struct StatusDotView: View {
    let status: AgentStatus
    let isActive: Bool
    @State private var dimmed = false

    var body: some View {
        Group {
            switch status {
            case .working:
                Circle().fill(NotchTheme.working)
            case .needsAttention:
                Circle()
                    .fill(NotchTheme.accent)
                    .opacity(dimmed ? 0.35 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            dimmed = true
                        }
                    }
            case .idle:
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            }
        }
        .frame(width: 9, height: 9)
    }
}

/// Dot for sessions with an attached pull request, in GitHub state colors.
/// (Live CI check results are not stored locally, so PR state is the signal.)
struct PullRequestDot: View {
    let pullRequest: PullRequestInfo

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help("PR #\(pullRequest.number) · \(pullRequest.state.rawValue.lowercased())")
    }

    private var color: Color {
        switch pullRequest.state {
        case .open: return .green
        case .merged: return .purple
        case .closed: return .red
        }
    }
}
