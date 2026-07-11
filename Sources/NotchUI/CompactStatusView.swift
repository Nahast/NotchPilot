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

    /// At most this many dots; further agents collapse into a "+N" count.
    private static let maxDots = 4

    public init(model: NotchViewModel, side: Side) {
        self.model = model
        self.side = side
    }

    public var body: some View {
        HStack(spacing: 2.5) {
            switch side {
            case .leading:
                let running = model.runningSessions
                if running.isEmpty {
                    // Everything idle (or no sessions yet): single dim glyph.
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.35))
                } else {
                    // Small dots stacked two per column, capped; the rest
                    // collapse into a "+N" count.
                    ForEach(Self.columns(of: Array(running.prefix(Self.maxDots))), id: \.first!.id) { column in
                        VStack(spacing: 2.5) {
                            ForEach(column) { session in
                                AgentDot(
                                    kind: session.agentKind,
                                    pulsing: session.status == .needsAttention
                                )
                            }
                        }
                    }
                    if running.count > Self.maxDots {
                        Text("+\(running.count - Self.maxDots)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .padding(.leading, 1)
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

    /// Chunks sessions into vertical pairs: [a b c d e] → [[a b] [c d] [e]].
    static func columns(of sessions: [AgentSession]) -> [[AgentSession]] {
        stride(from: 0, to: sessions.count, by: 2).map {
            Array(sessions[$0..<min($0 + 2, sessions.count)])
        }
    }
}

/// Brand colors + glyphs per agent product.
enum AgentBrandColor {
    static func color(for kind: AgentKind) -> Color {
        switch kind {
        case .claude: return NotchTheme.accent // orange
        case .codex: return Color(red: 0.36, green: 0.60, blue: 1.0) // blue
        case .cursor: return Color(red: 0.35, green: 0.85, blue: 0.85) // teal
        case .other: return Color.white.opacity(0.6)
        }
    }

    /// SF Symbol evoking each agent's brand (Claude's asterisk logo, etc.).
    static func icon(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "asterisk"
        case .codex: return "hexagon"
        case .cursor: return "cursorarrow"
        case .other: return "circle.dashed"
        }
    }

    static func name(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .other: return "Agent"
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
            .frame(width: 4.5, height: 4.5)
            .opacity(pulsing && dimmed ? 0.25 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
