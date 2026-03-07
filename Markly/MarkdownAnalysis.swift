//
//  MarkdownAnalysis.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum MarkdownBlockKind: String, Equatable {
    case heading
    case paragraph
    case unorderedList
    case orderedList
    case taskList
    case quote
    case codeFence
    case thematicBreak
}

struct MarkdownBlock: Identifiable, Equatable {
    let kind: MarkdownBlockKind
    let lineStart: Int
    let lineEnd: Int
    let text: String

    var id: String {
        "\(kind.rawValue)-\(lineStart)-\(lineEnd)"
    }
}

struct MarkdownHeading: Identifiable, Equatable {
    let level: Int
    let title: String
    let lineNumber: Int

    var id: String {
        "\(lineNumber)-\(level)-\(title)"
    }
}

struct MarkdownHeadingSection: Identifiable, Equatable {
    let heading: MarkdownHeading
    let contentLineStart: Int
    let contentLineEnd: Int

    var id: String {
        heading.id
    }

    var hasContent: Bool {
        contentLineEnd >= contentLineStart
    }

    func contains(lineNumber: Int) -> Bool {
        (heading.lineNumber...max(heading.lineNumber, contentLineEnd)).contains(lineNumber)
    }
}

enum MarkdownAnalysis {
    static func blocks(in text: String) -> [MarkdownBlock] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            let lineNumber = index + 1
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let start = index
                index += 1

                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    index += 1
                }

                blocks.append(
                    MarkdownBlock(
                        kind: .codeFence,
                        lineStart: start + 1,
                        lineEnd: index,
                        text: lines[start..<min(index, lines.count)].joined(separator: "\n")
                    )
                )
                continue
            }

            if isHeading(trimmed) {
                blocks.append(
                    MarkdownBlock(
                        kind: .heading,
                        lineStart: lineNumber,
                        lineEnd: lineNumber,
                        text: line
                    )
                )
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(
                    MarkdownBlock(
                        kind: .thematicBreak,
                        lineStart: lineNumber,
                        lineEnd: lineNumber,
                        text: line
                    )
                )
                index += 1
                continue
            }

            if blockKind(for: trimmed) == .quote {
                let start = index
                while index < lines.count,
                      blockKind(for: lines[index].trimmingCharacters(in: .whitespaces)) == .quote {
                    index += 1
                }

                blocks.append(
                    MarkdownBlock(
                        kind: .quote,
                        lineStart: start + 1,
                        lineEnd: index,
                        text: lines[start..<index].joined(separator: "\n")
                    )
                )
                continue
            }

            if let detectedListKind = listKind(for: trimmed) {
                let start = index
                while index < lines.count,
                      listKind(for: lines[index].trimmingCharacters(in: .whitespaces)) == detectedListKind {
                    index += 1
                }

                blocks.append(
                    MarkdownBlock(
                        kind: detectedListKind,
                        lineStart: start + 1,
                        lineEnd: index,
                        text: lines[start..<index].joined(separator: "\n")
                    )
                )
                continue
            }

            let start = index
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || isStructural(candidate) {
                    break
                }
                index += 1
            }

            blocks.append(
                MarkdownBlock(
                    kind: .paragraph,
                    lineStart: start + 1,
                    lineEnd: index,
                    text: lines[start..<index].joined(separator: "\n")
                )
            )
        }

        return blocks
    }

    static func headings(in text: String) -> [MarkdownHeading] {
        blocks(in: text).compactMap { block in
            guard block.kind == .heading else { return nil }
            let trimmed = block.text.trimmingCharacters(in: .whitespaces)
            let level = trimmed.prefix { $0 == "#" }.count
            let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return MarkdownHeading(level: level, title: title, lineNumber: block.lineStart)
        }
    }

    static func blockCounts(in text: String) -> [MarkdownBlockKind: Int] {
        blocks(in: text).reduce(into: [MarkdownBlockKind: Int]()) { partialResult, block in
            partialResult[block.kind, default: 0] += 1
        }
    }

    static func block(containingLine lineNumber: Int, in text: String) -> MarkdownBlock? {
        blocks(in: text).first { block in
            (block.lineStart...block.lineEnd).contains(lineNumber)
        }
    }

    static func headingSections(in text: String) -> [MarkdownHeadingSection] {
        let headings = headings(in: text)
        let totalLineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)

        return headings.enumerated().map { index, heading in
            let nextSiblingOrParent = headings.dropFirst(index + 1).first(where: { $0.level <= heading.level })
            let sectionEnd = (nextSiblingOrParent?.lineNumber ?? (totalLineCount + 1)) - 1

            return MarkdownHeadingSection(
                heading: heading,
                contentLineStart: heading.lineNumber + 1,
                contentLineEnd: max(heading.lineNumber, sectionEnd)
            )
        }
    }

    private static func isStructural(_ trimmedLine: String) -> Bool {
        isHeading(trimmedLine) ||
        isThematicBreak(trimmedLine) ||
        trimmedLine.hasPrefix(">") ||
        trimmedLine.hasPrefix("```") ||
        listKind(for: trimmedLine) != nil
    }

    private static func isHeading(_ trimmedLine: String) -> Bool {
        let level = trimmedLine.prefix { $0 == "#" }.count
        return (1...6).contains(level) && trimmedLine.dropFirst(level).first?.isWhitespace == true
    }

    private static func isThematicBreak(_ trimmedLine: String) -> Bool {
        ["---", "***", "___"].contains(trimmedLine)
    }

    private static func blockKind(for trimmedLine: String) -> MarkdownBlockKind? {
        if trimmedLine.hasPrefix(">") {
            return .quote
        }
        return listKind(for: trimmedLine)
    }

    private static func listKind(for trimmedLine: String) -> MarkdownBlockKind? {
        if matches(trimmedLine, pattern: #"^[-*+]\s+\[[ xX]\]\s+.*$"#) {
            return .taskList
        }

        if matches(trimmedLine, pattern: #"^[-*+]\s+.*$"#) {
            return .unorderedList
        }

        if matches(trimmedLine, pattern: #"^\d+\.\s+.*$"#) {
            return .orderedList
        }

        return nil
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
