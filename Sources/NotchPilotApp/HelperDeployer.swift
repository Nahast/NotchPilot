import ClaudeCodeProvider
import Foundation

/// Copies the bundled notchpilot-hook helper to a stable location
/// (`~/Library/Application Support/NotchPilot/bin/`) so the command registered
/// in `~/.claude/settings.json` keeps working when the app is moved or updated.
enum HelperDeployer {
    @discardableResult
    static func deployIfNeeded() -> URL? {
        guard let source = bundledHelperURL() else { return nil }
        let destination = ClaudeCodePaths.defaultHelperInstallURL
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.contentsEqual(atPath: source.path, andPath: destination.path) {
            return destination
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
            return destination
        } catch {
            NSLog("NotchPilot: helper deploy failed: %@", error.localizedDescription)
            return fileManager.fileExists(atPath: destination.path) ? destination : nil
        }
    }

    private static func bundledHelperURL() -> URL? {
        var candidates: [URL] = [
            // Bundled app layout.
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/notchpilot-hook"),
        ]
        // Dev layout (`swift run`): both executables sit in the build folder.
        if let executable = Bundle.main.executableURL {
            candidates.append(
                executable.deletingLastPathComponent().appendingPathComponent("notchpilot-hook")
            )
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
