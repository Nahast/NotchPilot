import AgentCore
import SwiftUI

/// Content of the expanded notch window. On non-notched displays this same
/// view doubles as the always-visible floating pill: it renders the compact
/// signal until the user hovers (DynamicNotchKit has no compact state for the
/// `.floating` style).
public struct ExpandedPanelView: View {
    @ObservedObject private var model: NotchViewModel
    @State private var listContentHeight: CGFloat = 0

    public init(model: NotchViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.showsAsFloatingPill, !model.isHovering {
                pill
            } else {
                panel
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Floating pill (compact signal on non-notched displays)

    private var pill: some View {
        HStack(spacing: 8) {
            CompactStatusView(model: model, side: .leading)
            CompactStatusView(model: model, side: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Full panel

    /// Fixed width of the expanded card.
    private static let panelWidth: CGFloat = 560
    /// Transparent breathing room between text and the window border. At least
    /// 2% of the window width on every side, plus a little extra so text also
    /// clears the notch shape's rounded corners (which curve inward past a
    /// straight inset). 2% of 560 ≈ 11pt; 18pt keeps a comfortable margin.
    private static let edgeInset: CGFloat = max(18, panelWidth * 0.02)

    /// "2 working · 1 waiting" — quick glance under the agent count.
    private var headerSummary: String? {
        var parts: [String] = []
        if model.workingCount > 0 { parts.append("\(model.workingCount) working") }
        if model.attentionCount > 0 { parts.append("\(model.attentionCount) waiting") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let usage = model.usage, !usage.windows.isEmpty {
                UsageBlockView(usage: usage)
            } else if model.usageSignedOut {
                usageSignedOutHint
            }
            if model.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(Self.edgeInset)
        .frame(width: Self.panelWidth)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.11, blue: 0.06),
                    Color(red: 0.08, green: 0.05, blue: 0.03),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        // DynamicNotchKit reserves ~30pt (safe-area + corner padding) of its
        // black shape around the expanded content; pull the card outward so
        // only a hairline black rim remains. Floating style lays out
        // differently and keeps its normal margins.
        .padding(.horizontal, model.showsAsFloatingPill ? 0 : -26)
        // Fully cancel the kit's 15pt bottom safe-area: the card runs flush
        // to the shape's bottom edge and its corners are rounded by the
        // notch shape's own mask — no black bar.
        .padding(.bottom, model.showsAsFloatingPill ? 0 : -15)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "asterisk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchTheme.accent)
            Text("\(model.groups.active.count) agent\(model.groups.active.count == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            if let summary = headerSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if model.isLimitedMode {
                ChipView(text: "LIMITED", color: Color.white.opacity(0.5))
                    .help("Hooks are not installed — statuses are heuristics from transcript activity only.")
            }
            Spacer()
            if let tally = model.tokenTally, tally.tokens > 0 {
                ChipView(text: "\(tally.formatted) today", icon: "bolt.fill")
                    .help("Tokens consumed today across all sessions (input + output, cache reads excluded)")
            }
            if model.attentionCount > 0 {
                ChipView(
                    text: "\(model.attentionCount) needs you",
                    color: NotchTheme.accent,
                    emphasized: true
                )
            }
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("NotchPilot Settings")
        }
    }

    /// Shown when usage is enabled but Claude Code has no stored credentials.
    private var usageSignedOutHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 10))
            Text("Sign in to Claude Code (`claude login`) to see usage limits")
                .font(.system(size: 10))
        }
        .foregroundStyle(Color.white.opacity(0.4))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No agent sessions yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Claude Code, Codex, and Cursor sessions appear here automatically.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    /// Many sessions → cap height and scroll (design spec §5). Overflowing
    /// content fades out at the bottom instead of hitting a hard edge.
    /// Main list is capped at 5 rows (actives first, most recent inactive
    /// fill); routines get their own section at the end.
    private static let listMaxHeight: CGFloat = 250

    private var sessionList: some View {
        let groups = model.groups
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                rows(groups.active)
                if !groups.inactive.isEmpty {
                    sectionHeader("Recent")
                        .padding(.top, groups.active.isEmpty ? 0 : 6)
                    rows(groups.inactive)
                }
                if !groups.routines.isEmpty {
                    sectionHeader("Routines")
                        .padding(.top, groups.active.isEmpty && groups.inactive.isEmpty ? 0 : 6)
                    rows(groups.routines)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { listContentHeight = $0 }
        }
        .frame(maxHeight: Self.listMaxHeight)
        .mask(alignment: .top) {
            if listContentHeight > Self.listMaxHeight {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 64)
                }
            } else {
                Rectangle()
            }
        }
    }

    private func rows(_ sessions: [AgentSession]) -> some View {
        ForEach(sessions) { session in
            SessionRowView(session: session) { tapped in
                model.onJump?(tapped)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .kerning(0.8)
            .foregroundStyle(Color.white.opacity(0.35))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }
}

/// Shared warm accent palette.
enum NotchTheme {
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.21) // warm orange
    static let working = Color(red: 0.29, green: 0.87, blue: 0.50)
}

/// Small bordered mono-font chip ("NEEDS YOU", "Opus 4.8", "22%").
struct ChipView: View {
    let text: String
    var icon: String?
    var color: Color = Color.white.opacity(0.6)
    var emphasized = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(emphasized ? 0.14 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(emphasized ? 0.7 : 0.35), lineWidth: 1)
        )
    }
}

/// Claude rate-limit windows: one bar per window (5h, 7d, per-model).
struct UsageBlockView: View {
    let usage: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "asterisk")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.accent)
                Text("Claude")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            ForEach(usage.windows) { window in
                UsageWindowRow(window: window)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 124, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(3, geometry.size.width * window.remainingFraction))
                }
            }
            .frame(width: 72, height: 5)
            Text("\(Int((window.remainingFraction * 100).rounded()))% left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if let resetsAt = window.resetsAt {
                Text("· resets \(Self.resetText(resetsAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
    }

    private var barColor: Color {
        if window.remainingFraction > 0.5 { return NotchTheme.working }
        if window.remainingFraction > 0.2 { return .orange }
        return .red
    }

    static func resetText(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return formatter.string(from: date)
    }
}
