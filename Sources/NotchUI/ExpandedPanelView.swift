import AgentCore
import SwiftUI

/// Content of the expanded notch window. On non-notched displays this same
/// view doubles as the always-visible floating pill: it renders the compact
/// signal until the user hovers (DynamicNotchKit has no compact state for the
/// `.floating` style).
public struct ExpandedPanelView: View {
    @ObservedObject private var model: NotchViewModel

    public init(model: NotchViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.showsAsFloatingPill, !model.isHovering, !model.isPeeking {
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

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
                .overlay(Color.white.opacity(0.15))
            if model.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("NotchPilot")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if model.isLimitedMode {
                Text("limited mode")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                    .foregroundStyle(.orange)
                    .help("Hooks are not installed — statuses are heuristics from transcript activity only.")
            }
            Spacer()
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("NotchPilot Settings")
        }
    }

    private var emptyState: some View {
        Text("No active Claude Code sessions")
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    /// Many sessions → cap height and scroll (design spec §5).
    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(model.sessions) { session in
                    SessionRowView(session: session) { tapped in
                        model.onJump?(tapped)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }
}
