import SwiftUI

@main
struct NotchPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // LSUIElement app: no windows from SwiftUI scenes — the notch window,
        // onboarding, and settings are managed by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
