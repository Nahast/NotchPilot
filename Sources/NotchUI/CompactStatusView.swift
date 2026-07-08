import SwiftUI

/// The minimum useful signal, hugging the notch: a dot + count per status
/// class. All idle → a single dim glyph (design spec §2).
public struct CompactStatusView: View {
    public enum Side {
        case leading
        case trailing
    }

    @ObservedObject private var model: NotchViewModel
    private let side: Side

    public init(model: NotchViewModel, side: Side) {
        self.model = model
        self.side = side
    }

    public var body: some View {
        HStack(spacing: 4) {
            switch side {
            case .leading:
                if model.workingCount > 0 {
                    StatusDot(color: .green)
                    countText(model.workingCount)
                } else if model.attentionCount == 0 {
                    // Everything idle (or no sessions yet): single dim glyph.
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            case .trailing:
                if model.attentionCount > 0 {
                    StatusDot(color: .orange, pulsing: true)
                    countText(model.attentionCount)
                }
            }
        }
        .padding(.horizontal, 2)
        .environment(\.colorScheme, .dark)
    }

    private func countText(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

/// Small colored status dot; pulses when `pulsing` (needs-attention alert).
struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(pulsing && dimmed ? 0.3 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
