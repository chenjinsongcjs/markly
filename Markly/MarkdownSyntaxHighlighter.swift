//
//  MarkdownSyntaxHighlighter.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import AppKit

final class MarkdownSyntaxHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

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

        apply(pattern: #"(?m)^(#{1,6})\s+(.+)$"#, in: textStorage) { match, storage in
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
        }

        apply(pattern: #"(?m)^\s*[-*+]\s+.+$"#, in: textStorage) { match, storage in
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
        }

        apply(pattern: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+.+$"#, in: textStorage) { match, storage in
            storage.addAttribute(.foregroundColor, value: NSColor.systemMint, range: match.range)
        }

        apply(pattern: #"(?m)^\s*\d+\.\s+.+$"#, in: textStorage) { match, storage in
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
        }

        apply(pattern: #"(?m)^>\s?.+$"#, in: textStorage) { match, storage in
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
        }

        apply(pattern: #"(?s)```.*?```"#, in: textStorage) { match, storage in
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.systemIndigo,
                    .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .systemIndigo) ?? NSColor.textBackgroundColor
                ],
                range: match.range
            )
        }

        apply(pattern: #"`[^`\n]+`"#, in: textStorage) { match, storage in
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.systemPurple,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                ],
                range: match.range
            )
        }

        apply(pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#, in: textStorage) { match, storage in
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                range: match.range
            )
        }

        apply(pattern: #"\*[^*\n]+\*|_[^_\n]+_"#, in: textStorage) { match, storage in
            storage.addAttribute(.obliqueness, value: 0.18, range: match.range)
        }

        apply(pattern: #"\[[^\]]+\]\([^)]+\)"#, in: textStorage) { match, storage in
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: match.range)
        }

        textStorage.endEditing()
    }

    private func apply(
        pattern: String,
        in textStorage: NSTextStorage,
        handler: (NSTextCheckingResult, NSTextStorage) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = textStorage.string
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.matches(in: text, range: range).forEach { handler($0, textStorage) }
    }
}
