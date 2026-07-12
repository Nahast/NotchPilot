import SwiftUI

/// A bundled legal document (Privacy Policy, EULA) shown from Settings.
enum LegalDocument: String, Identifiable, CaseIterable {
    case privacyPolicy = "PRIVACY_POLICY"
    case eula = "EULA"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "Privacy Policy"
        case .eula: return "End User License Agreement"
        }
    }

    /// Markdown text, from the app bundle (copied in by make_app.sh) with a
    /// repo-root fallback for `swift run` dev builds.
    var text: String {
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("\(rawValue).md")
        if let text = try? String(contentsOf: devURL, encoding: .utf8) {
            return text
        }
        return "The \(title) could not be loaded from this build. "
            + "The current version is available in the source repository "
            + "and ships with every packaged release."
    }
}

/// Plain scrollable reader — legal text wants legibility, not chrome.
struct LegalDocumentView: View {
    let document: LegalDocument
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 480)
    }

    /// Best-effort markdown rendering; falls back to the raw text.
    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: document.text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(document.text)
    }
}
