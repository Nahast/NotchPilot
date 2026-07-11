import AgentCore
import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

/// Window-layer abstraction (design spec §3): everything above talks to this
/// protocol, so DynamicNotchKit can be swapped or forked without touching
/// other modules.
@MainActor
public protocol NotchPresenter: AnyObject {
    /// Present the compact notch (or floating pill) on the main display.
    func show()
    /// Remove the notch window entirely.
    func dismiss()
    /// Re-evaluate screen geometry (display changes / sleep-wake / fullscreen).
    func refresh()
}

/// DynamicNotchKit-backed presenter.
///
/// Notched displays: compact state hugging the notch; hover expands.
/// Non-notched displays: DynamicNotchKit's `.floating` style has no compact
/// state, so the window stays "expanded" and `ExpandedPanelView` renders a
/// small pill until hovered (`NotchViewModel.showsAsFloatingPill`).
@MainActor
public final class DynamicNotchKitPresenter: NotchPresenter {
    private typealias Notch = DynamicNotch<ExpandedPanelView, CompactStatusView, CompactStatusView>

    private let model: NotchViewModel
    private var notch: Notch?
    private var hoverCancellable: AnyCancellable?
    private var hoverIntentTask: Task<Void, Never>?

    /// The mouse must dwell this long on the notch before the panel opens —
    /// prevents accidental re-opens when the cursor merely passes the notch
    /// (e.g. moving up to the menu bar right after leaving the panel).
    private let hoverExpandDelay: TimeInterval = 0.35

    /// The expanded panel is semi-transparent so the desktop shows through.
    /// DynamicNotchKit paints an opaque black notch shape internally, so the
    /// translucency is applied at the window level; the compact state stays
    /// fully opaque to keep blending with the physical notch.
    private let expandedWindowAlpha: CGFloat = 0.93

    private func applyWindowAlpha(_ alpha: CGFloat) {
        notch?.windowController?.window?.alphaValue = alpha
    }

    public init(model: NotchViewModel) {
        self.model = model
        // The notch never opens on its own — no auto-peek. When a session
        // needs attention the compact view pulses (view-level); the panel
        // opens only when the user hovers.
    }

    // MARK: NotchPresenter

    public func show() {
        guard notch == nil, let screen = targetScreen else { return }
        let floating = !screenHasNotch(screen)
        model.showsAsFloatingPill = floating

        let model = self.model
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto
        ) {
            ExpandedPanelView(model: model)
        } compactLeading: {
            CompactStatusView(model: model, side: .leading)
        } compactTrailing: {
            CompactStatusView(model: model, side: .trailing)
        }
        self.notch = notch

        hoverCancellable = notch.$isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in
                Task { @MainActor [weak self] in
                    self?.hoverDidChange(hovering)
                }
            }

        Task { [weak self] in
            guard let self, let notch = self.notch else { return }
            if floating {
                await notch.expand(on: screen)
                self.applyWindowAlpha(self.expandedWindowAlpha)
            } else {
                await notch.compact(on: screen)
                self.applyWindowAlpha(1)
            }
        }
    }

    public func dismiss() {
        let dismissed = notch
        notch = nil
        hoverCancellable = nil
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        Task { await dismissed?.hide() }
    }

    /// Display configuration changed: rebuild on the (possibly new) main
    /// display; notched vs floating may have flipped (spec §5).
    public func refresh() {
        guard notch != nil else { return }
        let old = notch
        notch = nil
        hoverCancellable = nil
        Task { [weak self] in
            await old?.hide()
            self?.show()
        }
    }

    // MARK: Internals

    /// v1 shows on the main display — the one with the menu bar (spec §2).
    private var targetScreen: NSScreen? {
        NSScreen.screens.first
    }

    private func screenHasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    private func hoverDidChange(_ hovering: Bool) {
        hoverIntentTask?.cancel()
        guard let notch, let screen = targetScreen else {
            model.isHovering = hovering
            return
        }

        if hovering {
            // Dwell before opening; a cursor just passing by cancels this.
            hoverIntentTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.hoverExpandDelay ?? 0) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.model.isHovering = true
                // Floating pill: the window stays expanded; the content
                // itself swaps between pill and panel from `isHovering`.
                guard !self.model.showsAsFloatingPill else { return }
                await notch.expand(on: screen)
                self.applyWindowAlpha(self.expandedWindowAlpha)
            }
        } else {
            model.isHovering = false
            guard !model.showsAsFloatingPill else { return }
            Task { [weak self] in
                await notch.compact(on: screen)
                self?.applyWindowAlpha(1)
            }
        }
    }
}
