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

/// Scrollable reader rendering the documents' markdown properly: headings,
/// lists, and paragraphs as blocks; bold/code/links inline.
struct LegalDocumentView: View {
    let document: LegalDocument
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(MarkdownBlock.parse(document.text)) { block in
                        blockView(block)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 600, height: 520)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading1:
            Text(inline(block.text))
                .font(.title2.bold())
        case .heading2:
            Text(inline(block.text))
                .font(.headline)
                .padding(.top, 8)
        case .paragraph:
            Text(inline(block.text))
                .font(.system(size: 12.5))
                .lineSpacing(2.5)
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(block.marker)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(inline(block.text))
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
            }
            .padding(.leading, 8)
        }
    }

    /// Inline markdown (bold, code, links); falls back to the raw text.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}

/// Minimal block-level markdown model covering what the legal documents use:
/// `#`/`##` headings, `-` bullets, `1.` ordered items (with indented
/// continuation lines), and paragraphs joined across soft line wraps.
struct MarkdownBlock: Identifiable {
    enum Kind { case heading1, heading2, paragraph, listItem }

    let id: Int
    let kind: Kind
    var text: String
    var marker: String = ""

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(MarkdownBlock(
                id: blocks.count, kind: .paragraph,
                text: paragraph.joined(separator: " ")
            ))
            paragraph = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(MarkdownBlock(
                    id: blocks.count, kind: .heading2,
                    text: String(trimmed.dropFirst(3))
                ))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(MarkdownBlock(
                    id: blocks.count, kind: .heading1,
                    text: String(trimmed.dropFirst(2))
                ))
                continue
            }
            if trimmed.hasPrefix("- ") {
                flushParagraph()
                blocks.append(MarkdownBlock(
                    id: blocks.count, kind: .listItem,
                    text: String(trimmed.dropFirst(2)), marker: "•"
                ))
                continue
            }
            if let dot = trimmed.firstIndex(of: "."),
               trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
               trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
                flushParagraph()
                blocks.append(MarkdownBlock(
                    id: blocks.count, kind: .listItem,
                    text: trimmed[trimmed.index(dot, offsetBy: 2)...]
                        .trimmingCharacters(in: .whitespaces),
                    marker: String(trimmed[...dot])
                ))
                continue
            }
            // Indented continuation of the previous list item.
            if rawLine.hasPrefix("  "), paragraph.isEmpty,
               let last = blocks.indices.last, blocks[last].kind == .listItem {
                blocks[last].text += " " + trimmed
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        return blocks
    }
}
