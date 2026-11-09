import Foundation

/// A firmware's description, which its author may have written in Markdown.
enum FirmwareDescription {
    /// The description with its bold, italics and code shown, and its links as plain text, so a
    /// tap on a description doesn't leave the app.
    static func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var styled = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for range in styled.runs.filter({ $0.link != nil }).map(\.range) {
            styled[range].link = nil
        }
        return styled
    }

    /// The description without its Markdown, for the 8-bit look's fixed-width text.
    static func plain(_ text: String) -> String {
        String(styled(text).characters)
    }
}
