import Foundation
import ServiceManagement

/// SMAppService wrapper (design spec §3). Only functional when running from
/// a real .app bundle — `swift run` dev builds report unavailable.
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NotchPilot: launch-at-login change failed: %@", error.localizedDescription)
        }
    }
}
