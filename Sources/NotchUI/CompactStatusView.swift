import AgentCore
import SwiftUI

/// The minimum useful signal, hugging the notch: one dot per running agent,
/// colored by agent product (Claude orange, Codex blue, …). Agents waiting on
/// the user pulse their dot. All idle → a single dim glyph. No numbers.
public struct CompactStatusView: View {
    public enum Side {
        case leading
        case trailing
    }

    @ObservedObject private var model: NotchViewModel
    private let side: Side

    /// The compact area is small; beyond this many dots the tail is dropped.
    private static let maxDots = 8

    public init(model: NotchViewModel, side: Side) {
        self.model = model
        self.side = side
    }

    public var body: some View {
        HStack(spacing: 3.5) {
            switch side {
            case .leading:
                let running = model.runningSessions
                if running.isEmpty {
                    // Everything idle (or no sessions yet): single dim glyph.
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.35))
                } else {
                    ForEach(running.prefix(Self.maxDots)) { session in
                        AgentDot(
                            kind: session.agentKind,
                            pulsing: session.status == .needsAttention
                        )
                    }
                }
            case .trailing:
                // All signal lives on the leading side now.
                EmptyView()
            }
        }
        .padding(.horizontal, 2)
        .environment(\.colorScheme, .dark)
    }
}

/// Brand colors per agent product.
enum AgentBrandColor {
    static func color(for kind: AgentKind) -> Color {
        switch kind {
        case .claude: return NotchTheme.accent // orange
        case .codex: return Color(red: 0.36, green: 0.60, blue: 1.0) // blue
        case .cursor: return Color(red: 0.35, green: 0.85, blue: 0.85) // teal
        case .other: return Color.white.opacity(0.6)
        }
    }
}

/// One running agent; pulses when that agent is waiting on the user.
struct AgentDot: View {
    let kind: AgentKind
    var pulsing = false
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(AgentBrandColor.color(for: kind))
            .frame(width: 6.5, height: 6.5)
            .opacity(pulsing && dimmed ? 0.25 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
