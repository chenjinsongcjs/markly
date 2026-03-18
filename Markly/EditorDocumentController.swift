//
//  EditorDocumentController.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation

struct EditorDocumentMutation {
    let text: String
    let focusLine: Int
}

enum EditorDocumentController {
    static func mergeBlocks(
        in text: String,
        previous: MarkdownBlock,
        current: MarkdownBlock
    ) -> EditorDocumentMutation? {
        let mergedText = mergedBlockText(previous: previous, current: current)
        var lines = MarkdownAnalysis.lines(in: text)
        let previousStart = max(0, previous.lineStart - 1)
        let currentEnd = min(lines.count - 1, current.lineEnd - 1)
        let mergedLines = mergedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard previousStart <= currentEnd, currentEnd < lines.count else { return nil }

        lines.replaceSubrange(previousStart...currentEnd, with: mergedLines)
        return EditorDocumentMutation(
            text: lines.joined(separator: "\n"),
            focusLine: previous.lineStart
        )
    }

    static func replaceLine(
        in text: String,
        lineNumber: Int,
        replacement: String
    ) -> EditorDocumentMutation {
        EditorDocumentMutation(
            text: MarkdownAnalysis.replaceLine(lineNumber, with: replacement, in: text),
            focusLine: lineNumber
        )
    }

    static func replaceBlock(
        in text: String,
        block: MarkdownBlock,
        replacement: String
    ) -> EditorDocumentMutation {
        EditorDocumentMutation(
            text: MarkdownAnalysis.replaceBlock(block, with: replacement, in: text),
            focusLine: block.lineStart
        )
    }

    static func insertBlock(
        in text: String,
        after block: MarkdownBlock,
        markdown: String,
        focusLineOffset: Int
    ) -> EditorDocumentMutation {
        let updatedText = MarkdownAnalysis.insertBlock(markdown, afterLine: block.lineEnd, in: text)
        return EditorDocumentMutation(
            text: updatedText,
            focusLine: block.lineEnd + focusLineOffset
        )
    }

    static func deleteBlock(
        in text: String,
        block: MarkdownBlock
    ) -> EditorDocumentMutation? {
        var lines = MarkdownAnalysis.lines(in: text)
        let startIndex = block.lineStart - 1
        let endIndex = block.lineEnd - 1
        guard startIndex >= 0, endIndex < lines.count, startIndex <= endIndex else { return nil }

        lines.removeSubrange(startIndex...endIndex)

        if startIndex > 0, startIndex < lines.count {
            let previousIsBlank = lines[startIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentIsBlank = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if previousIsBlank && currentIsBlank {
                lines.remove(at: startIndex)
            }
        }

        let focusLine = max(1, min(startIndex + 1, max(1, lines.count)))
        return EditorDocumentMutation(text: lines.joined(separator: "\n"), focusLine: focusLine)
    }

    static func duplicateBlock(
        in text: String,
        block: MarkdownBlock
    ) -> EditorDocumentMutation? {
        var lines = MarkdownAnalysis.lines(in: text)
        let range = expandedBlockRange(for: block, in: lines)
        let blockLines = Array(lines[range])
        let insertionIndex = range.upperBound + 1
        lines.insert(contentsOf: blockLines, at: insertionIndex)
        return EditorDocumentMutation(
            text: lines.joined(separator: "\n"),
            focusLine: insertionIndex + 1
        )
    }

    static func moveBlock(
        in text: String,
        block: MarkdownBlock,
        direction: BlockMoveDirection
    ) -> EditorDocumentMutation? {
        let allBlocks = MarkdownAnalysis.blocks(in: text)
        guard let index = allBlocks.firstIndex(of: block) else { return nil }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard allBlocks.indices.contains(targetIndex) else { return nil }

        var lines = MarkdownAnalysis.lines(in: text)
        let blockRange = expandedBlockRange(for: block, in: lines)
        let targetRange = expandedBlockRange(for: allBlocks[targetIndex], in: lines)
        let blockLines = Array(lines[blockRange])
        let targetLines = Array(lines[targetRange])

        if direction == .up {
            lines.removeSubrange(blockRange)
            lines.removeSubrange(targetRange)
            let reorderedLines = preservingBlockBoundary(between: blockLines, and: targetLines)
            lines.insert(contentsOf: reorderedLines, at: targetRange.lowerBound)
            return EditorDocumentMutation(
                text: lines.joined(separator: "\n"),
                focusLine: targetRange.lowerBound + 1
            )
        }

        lines.removeSubrange(targetRange)
        lines.removeSubrange(blockRange)
        let reorderedLines = preservingBlockBoundary(between: targetLines, and: blockLines)
        lines.insert(contentsOf: reorderedLines, at: blockRange.lowerBound)
        return EditorDocumentMutation(
            text: lines.joined(separator: "\n"),
            focusLine: blockRange.lowerBound + targetLines.count + 1
        )
    }

    static func toggleTaskItem(
        in text: String,
        lineNumber: Int
    ) -> EditorDocumentMutation? {
        var lines = MarkdownAnalysis.lines(in: text)
        let index = lineNumber - 1
        guard lines.indices.contains(index), let parts = taskMatch(in: lines[index]) else { return nil }

        lines[index] = parts.prefix + (parts.isCompleted ? " " : "x") + parts.suffix
        return EditorDocumentMutation(text: lines.joined(separator: "\n"), focusLine: lineNumber)
    }

    static func replaceCurrentSearchMatch(
        in text: String,
        matchRange: Range<String.Index>,
        replacement: String
    ) -> EditorDocumentMutation {
        var updatedText = text
        updatedText.replaceSubrange(matchRange, with: replacement)
        let focusLine = lineNumber(for: matchRange.lowerBound, in: text)
        return EditorDocumentMutation(text: updatedText, focusLine: focusLine)
    }

    static func replaceAllSearchMatches(
        in text: String,
        query: String,
        replacement: String
    ) -> EditorDocumentMutation {
        let updatedText = text.replacingOccurrences(of: query, with: replacement, options: .caseInsensitive)
        let focusLine = lineNumberForFirstCaseInsensitiveMatch(of: replacement, in: updatedText) ?? 1
        return EditorDocumentMutation(text: updatedText, focusLine: focusLine)
    }

    private static func expandedBlockRange(for block: MarkdownBlock, in lines: [String]) -> ClosedRange<Int> {
        let start = max(0, block.lineStart - 1)
        var end = min(lines.count - 1, block.lineEnd - 1)
        var index = end + 1

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end = index
                index += 1
            } else {
                break
            }
        }

        return start...end
    }

    private static func taskMatch(in line: String) -> (prefix: String, isCompleted: Bool, suffix: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s+.*)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else { return nil }

        return (
            prefix: nsLine.substring(with: match.range(at: 1)),
            isCompleted: nsLine.substring(with: match.range(at: 2)).lowercased() == "x",
            suffix: nsLine.substring(with: match.range(at: 3))
        )
    }

    private static func preservingBlockBoundary(
        between firstLines: [String],
        and secondLines: [String]
    ) -> [String] {
        guard
            let lastMeaningfulFirst = firstLines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            let firstMeaningfulSecond = secondLines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return firstLines + secondLines
        }

        let firstEndsWithBlank = firstLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        let secondStartsWithBlank = secondLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        let needsBlankSeparator =
            !firstEndsWithBlank &&
            !secondStartsWithBlank &&
            !isStructuralBoundaryLine(lastMeaningfulFirst) &&
            !isStructuralBoundaryLine(firstMeaningfulSecond)

        if needsBlankSeparator {
            return firstLines + [""] + secondLines
        }

        return firstLines + secondLines
    }

    private static func isStructuralBoundaryLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") ||
            trimmed.hasPrefix(">") ||
            trimmed.hasPrefix("```") ||
            trimmed.hasPrefix("~~~") ||
            trimmed.hasPrefix("|") ||
            matches(trimmed, pattern: #"^[-*+]\s+"#) ||
            matches(trimmed, pattern: #"^\d+\.\s+"#)
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func mergedBlockText(previous: MarkdownBlock, current: MarkdownBlock) -> String {
        let previousTrimmed = previous.text.trimmingCharacters(in: .newlines)
        let currentTrimmed = current.text.trimmingCharacters(in: .newlines)

        guard !previousTrimmed.isEmpty else { return currentTrimmed }
        guard !currentTrimmed.isEmpty else { return previousTrimmed }

        return previousTrimmed + mergeSeparator(previous: previous.kind, current: current.kind) + currentTrimmed
    }

    private static func mergeSeparator(previous: MarkdownBlockKind, current: MarkdownBlockKind) -> String {
        switch (previous, current) {
        case (.paragraph, .paragraph), (.heading, .paragraph), (.paragraph, .heading):
            return "\n"
        case (.quote, .quote),
             (.unorderedList, .unorderedList),
             (.orderedList, .orderedList),
             (.taskList, .taskList),
             (.codeFence, .codeFence):
            return "\n"
        default:
            return "\n\n"
        }
    }

    private static func lineNumber(for index: String.Index, in text: String) -> Int {
        let prefix = text[..<index]
        return max(1, prefix.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private static func lineNumberForFirstCaseInsensitiveMatch(of query: String, in text: String) -> Int? {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
        return lineNumber(for: range.lowerBound, in: text)
    }
}
