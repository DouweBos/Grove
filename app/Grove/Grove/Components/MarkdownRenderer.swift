// Components/MarkdownRenderer.swift
// Grove
//
// Renders Markdown text as styled SwiftUI content.
// Uses Foundation's AttributedString Markdown parsing.

import SwiftUI

// MARK: - MarkdownRenderer

/// Renders a Markdown string using `AttributedString`.
///
/// Falls back to plain `Text` when parsing fails.
///
/// ```swift
/// MarkdownRenderer("**Bold** and _italic_ text")
/// MarkdownRenderer(content, fontSize: 14)
/// ```
struct MarkdownRenderer: View {

    // MARK: Properties

    let markdown: String
    var fontSize: CGFloat = 13

    // MARK: Body

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Preview

#Preview("Markdown Renderer") {
    VStack(alignment: .leading, spacing: 16) {
        MarkdownRenderer(markdown: "**Bold text** and *italic text*")

        MarkdownRenderer(markdown: "Inline `code` rendering")

        MarkdownRenderer(markdown: """
        A paragraph with a [link](https://example.com) and some **bold** content.

        - List item one
        - List item two
        - List item **three**
        """, fontSize: 14)

        MarkdownRenderer(markdown: "# Heading\n\nSome body text after a heading.", fontSize: 15)
    }
    .padding()
    .frame(width: 400)
}
