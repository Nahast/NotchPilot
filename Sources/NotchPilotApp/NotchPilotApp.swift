import SwiftUI

@main
struct NotchPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Build-pipeline smoke check: prove the binary links and its
        // frameworks load, without bringing up the UI or touching ~/.claude.
        if CommandLine.arguments.contains("--smoke-test") {
            print("smoke-ok \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "dev")")
            exit(0)
        }
    }

    var body: some Scene {
        // LSUIElement app: no windows from SwiftUI scenes — the notch window,
        // onboarding, and settings are managed by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
