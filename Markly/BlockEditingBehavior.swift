//
//  BlockEditingBehavior.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation

enum BlockIndentDirection {
    case left
    case right
}

enum BlockEditingBehavior {
    static func shouldExitStructure(for kind: MarkdownBlockKind, currentLineText: String) -> Bool {
        let trimmed = currentLineText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .quote:
            return matches(trimmed, pattern: #"^(>\s*)+$"#)
        case .unorderedList:
            return matches(trimmed, pattern: #"^[-*+]\s*$"#)
        case .orderedList:
            return matches(trimmed, pattern: #"^\d+\.\s*$"#)
        case .taskList:
            return matches(trimmed, pattern: #"^[-*+]\s+\[[ xX]\]\s*$"#)
        default:
            return false
        }
    }

    static func continuationMarkdown(after block: MarkdownBlock, editedText: String) -> String {
        switch block.kind {
        case .heading, .paragraph, .image, .table, .thematicBreak, .codeFence:
            return "\n新段落"
        case .quote:
            return "\n> "
        case .unorderedList:
            return "\n- "
        case .orderedList:
            return "\n\(nextOrderedListNumber(from: editedText)). "
        case .taskList:
            return "\n- [ ] "
        }
    }

    static func nextOrderedListNumber(from text: String) -> Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return 1
        }

        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\.\s+"#) else { return 1 }
        let nsLine = lastNonEmptyLine as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: lastNonEmptyLine, range: range) else { return lines.count + 1 }

        let value = Int(nsLine.substring(with: match.range(at: 1))) ?? lines.count
        return value + 1
    }

    static func supportsIndentation(for kind: MarkdownBlockKind) -> Bool {
        switch kind {
        case .unorderedList, .orderedList, .taskList, .quote:
            return true
        default:
            return false
        }
    }

    static func adjustingIndentation(in text: String, selectedRange: NSRange, direction: BlockIndentDirection) -> (text: String, selection: NSRange) {
        let nsText = text as NSString
        let safeLocation = min(selectedRange.location, nsText.length)
        let safeRange = NSRange(location: safeLocation, length: min(selectedRange.length, nsText.length - safeLocation))
        let paragraphRange = nsText.paragraphRange(for: safeRange)
        let paragraphText = nsText.substring(with: paragraphRange)
        let lines = paragraphText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var delta = 0
        let adjustedLines = lines.map { line -> String in
            switch direction {
            case .right:
                guard !line.isEmpty else { return line }
                delta += 2
                return "  " + line
            case .left:
                if line.hasPrefix("  ") {
                    delta -= 2
                    return String(line.dropFirst(2))
                }
                if line.hasPrefix("\t") {
                    delta -= 1
                    return String(line.dropFirst())
                }
                if line.hasPrefix(" ") {
                    delta -= 1
                    return String(line.dropFirst())
                }
                return line
            }
        }

        let updatedParagraphText = adjustedLines.joined(separator: "\n")
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: paragraphRange, with: updatedParagraphText)

        let locationAdjustment: Int
        switch direction {
        case .right:
            locationAdjustment = adjustedLines.first.map { $0.isEmpty ? 0 : 2 } ?? 0
        case .left:
            locationAdjustment = min(0, delta)
        }

        let selectionLocation = max(0, safeRange.location + locationAdjustment)
        let selectionLength = max(0, safeRange.length + delta)
        let updatedLength = mutable.length
        let clampedLocation = min(selectionLocation, updatedLength)
        let clampedLength = min(selectionLength, max(0, updatedLength - clampedLocation))
        return (String(mutable), NSRange(location: clampedLocation, length: clampedLength))
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
