import AgentCore
import SwiftUI

/// One row per session: status icon, project name, one-line activity,
/// context gauge, time in current state (design spec §2).
struct SessionRowView: View {
    let session: AgentSession
    var onJump: (AgentSession) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIconView(status: session.status)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if session.isRoutine {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .help("Routine (scheduled run)")
                    }
                    Text(session.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.name != nil, session.projectName != session.displayName {
                        Text(session.projectName)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 10)) { context in
                        Text(Self.stateDurationText(for: session, now: context.date))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    if let pullRequest = session.pullRequest {
                        PullRequestDot(pullRequest: pullRequest)
                    }
                }
                Text(activityText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .opacity(session.isActive ? 1 : 0.55)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.white.opacity(0.09) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onJump(session) }
        .help(helpText)
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

/// Status icon: working = animated spinner, needs attention = orange,
/// idle/done = dim check (design spec §2).
struct StatusIconView: View {
    let status: AgentStatus
    @State private var spinning = false

    var body: some View {
        Group {
            switch status {
            case .working:
                Circle()
                    .trim(from: 0.18, to: 1)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            spinning = true
                        }
                    }
            case .needsAttention:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// Dot at the end of the title line for sessions with an attached pull
/// request, in GitHub state colors. (Live CI check results are not stored
/// locally, so PR state is the signal shown.)
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
