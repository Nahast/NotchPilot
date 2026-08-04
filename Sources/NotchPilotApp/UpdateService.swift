import Foundation
import OSLog
import Sparkle

/// Sparkle 2 wrapper; appcast on GitHub Releases (design spec §3, §6).
/// The updater only starts when running from a real bundle with a feed URL —
/// dev runs (`swift run`) skip it cleanly.
final class UpdateService {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Start Sparkle only with a complete, valid configuration; otherwise
        // it puts up a modal error at launch. The placeholder SUPublicEDKey
        // in unreleased builds intentionally fails the base64/length check.
        let info = Bundle.main.infoDictionary ?? [:]
        let hasFeed = info["SUFeedURL"] is String
        let keyIsValid = (info["SUPublicEDKey"] as? String)
            .flatMap { Data(base64Encoded: $0) }
            .map { $0.count == 32 } ?? false
        if hasFeed, keyIsValid {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            controller = nil
            if hasFeed {
                Log.app.warning("Sparkle disabled — SUPublicEDKey is not a valid Ed25519 key (see RELEASING.md)")
            }
        }
    }

    var isAvailable: Bool {
        controller != nil
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticChecksEnabled: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
