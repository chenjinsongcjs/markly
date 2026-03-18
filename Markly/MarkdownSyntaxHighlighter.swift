//
//  MarkdownSyntaxHighlighter.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import AppKit

final class MarkdownSyntaxHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let rules: [HighlightRule]

    init() {
        rules = [
            HighlightRule(pattern: #"(?m)^(#{1,6})\s+(.+)$"#) { match, storage in
                let level = match.range(at: 1).length
                let color: NSColor

                switch level {
                case 1:
                    color = .systemRed
                case 2:
                    color = .systemOrange
                case 3:
                    color = .systemYellow
                default:
                    color = .systemBrown
                }

                storage.addAttributes(
                    [
                        .foregroundColor: color,
                        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
                    ],
                    range: match.range
                )
            },
            HighlightRule(pattern: #"(?m)^\s*[-*+]\s+.+$"#) { match, storage in
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            },
            HighlightRule(pattern: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+.+$"#) { match, storage in
                storage.addAttribute(.foregroundColor, value: NSColor.systemMint, range: match.range)
            },
            HighlightRule(pattern: #"(?m)^\s*\d+\.\s+.+$"#) { match, storage in
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            },
            HighlightRule(pattern: #"(?m)^>\s?.+$"#) { match, storage in
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
            },
            HighlightRule(pattern: #"(?s)```.*?```"#) { match, storage in
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.systemIndigo,
                        .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .systemIndigo) ?? NSColor.textBackgroundColor
                    ],
                    range: match.range
                )
            },
            HighlightRule(pattern: #"`[^`\n]+`"#) { match, storage in
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.systemPurple,
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                    ],
                    range: match.range
                )
            },
            HighlightRule(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#) { match, storage in
                storage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                    range: match.range
                )
            },
            HighlightRule(pattern: #"\*[^*\n]+\*|_[^_\n]+_"#) { match, storage in
                storage.addAttribute(.obliqueness, value: 0.18, range: match.range)
            },
            HighlightRule(pattern: #"\[[^\]]+\]\([^)]+\)"#) { match, storage in
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: match.range)
            }
        ]
    }

    func highlight(textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()
        textStorage.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )

        rules.forEach { rule in
            rule.apply(to: textStorage)
        }

        textStorage.endEditing()
    }
}

private struct HighlightRule {
    let regex: NSRegularExpression
    let handler: (NSTextCheckingResult, NSTextStorage) -> Void

    init(pattern: String, handler: @escaping (NSTextCheckingResult, NSTextStorage) -> Void) {
        self.regex = try! NSRegularExpression(pattern: pattern)
        self.handler = handler
    }

    func apply(to textStorage: NSTextStorage) {
        let text = textStorage.string
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.matches(in: text, range: range).forEach { handler($0, textStorage) }
    }
}
