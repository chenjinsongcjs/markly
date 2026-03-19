//
//  MarkdownRenderModel.swift
//  Markly
//
//  Created by Codex on 2026/3/19.
//

import Foundation

struct MarkdownTableColumn: Equatable {
    let text: String
    let alignment: TableAlignment?
}

struct MarkdownTableRowModel: Equatable {
    let columns: [MarkdownTableColumn]
}

struct MarkdownTaskItemModel: Equatable {
    let text: String
    let isCompleted: Bool
}

enum MarkdownInlineNode: Equatable {
    case text(String)
    case link(title: String, destination: String, markdown: String)
    case image(alt: String, source: String, markdown: String)
    case inlineCode(String)
    case strong(String)
    case emphasis(String)
}

enum MarkdownRenderNode: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case unorderedList(items: [String])
    case orderedList(items: [String], startIndex: Int)
    case taskList(items: [MarkdownTaskItemModel])
    case quote(text: String)
    case codeBlock(language: String, code: String)
    case table(headers: [MarkdownTableColumn], rows: [MarkdownTableRowModel])
    case image(alt: String, source: String)
    case thematicBreak
}

enum MarkdownRenderModelBuilder {
    nonisolated static func build(from markdown: String) -> [MarkdownRenderNode] {
        MarkdownAnalysis.blocks(in: markdown).map(renderNode)
    }

    nonisolated static func node(for block: MarkdownBlock) -> MarkdownRenderNode {
        renderNode(from: block)
    }

    nonisolated private static func renderNode(from block: MarkdownBlock) -> MarkdownRenderNode {
        switch block.kind {
        case .heading:
            return headingNode(from: block.text)
        case .paragraph:
            return .paragraph(text: block.text)
        case .unorderedList:
            return .unorderedList(items: listItems(from: block.text, ordered: false))
        case .orderedList:
            let items = listItems(from: block.text, ordered: true)
            return .orderedList(items: items, startIndex: orderedListStartIndex(from: block.text))
        case .taskList:
            return .taskList(items: taskItems(from: block.text))
        case .quote:
            return .quote(text: quoteText(from: block.text))
        case .codeFence:
            return codeBlockNode(from: block.text)
        case .table:
            return tableNode(from: block.text)
        case .image:
            return imageNode(from: block.text)
        case .thematicBreak:
            return .thematicBreak
        }
    }

    nonisolated private static func headingNode(from text: String) -> MarkdownRenderNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let level = min(6, max(1, trimmed.prefix { $0 == "#" }.count))
        let content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: content)
    }

    nonisolated private static func listItems(from text: String, ordered: Bool) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if ordered {
                    return stripPrefix(in: trimmed, pattern: #"^\d+\.\s+"#)
                }
                return stripPrefix(in: trimmed, pattern: #"^[-*+]\s+"#)
            }
    }

    nonisolated private static func orderedListStartIndex(from text: String) -> Int {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\.\s+"#) else { return 1 }
        let nsText = firstLine as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: firstLine, range: range) else { return 1 }
        return Int(nsText.substring(with: match.range(at: 1))) ?? 1
    }

    nonisolated private static func taskItems(from text: String) -> [MarkdownTaskItemModel] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap(taskItem(from:))
    }

    nonisolated private static func taskItem(from line: String) -> MarkdownTaskItemModel? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*[-*+]\s+\[([ xX])\]\s+(.*)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        let marker = nsLine.substring(with: match.range(at: 1)).lowercased()
        let text = nsLine.substring(with: match.range(at: 2))
        return MarkdownTaskItemModel(text: text, isCompleted: marker == "x")
    }

    nonisolated private static func quoteText(from text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var value = String(line).trimmingCharacters(in: .whitespaces)
                while value.hasPrefix(">") {
                    value.removeFirst()
                    value = value.trimmingCharacters(in: .whitespaces)
                }
                return value
            }
            .joined(separator: "\n")
    }

    nonisolated private static func codeBlockNode(from text: String) -> MarkdownRenderNode {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first else {
            return .codeBlock(language: "", code: "")
        }

        let language = codeFenceLanguage(from: firstLine)
        let body = lines.dropFirst().dropLast().joined(separator: "\n")
        return .codeBlock(language: language, code: body)
    }

    nonisolated private static func tableNode(from text: String) -> MarkdownRenderNode {
        guard let table = MarkdownTable.parse(from: text) else {
            return .paragraph(text: text)
        }

        let alignments = normalizedAlignments(for: table)
        let headers = zip(table.headers, alignments).map { header, alignment in
            MarkdownTableColumn(text: header, alignment: alignment)
        }
        let rows = table.rows.map { row in
            MarkdownTableRowModel(
                columns: zip(padded(row, to: table.columnCount), alignments).map { value, alignment in
                    MarkdownTableColumn(text: value, alignment: alignment)
                }
            )
        }

        return .table(headers: headers, rows: rows)
    }

    nonisolated private static func imageNode(from text: String) -> MarkdownRenderNode {
        guard let match = text.wholeMatch(of: /!\[(.*)\]\((.*)\)/) else {
            return .paragraph(text: text)
        }

        return .image(
            alt: String(match.output.1),
            source: String(match.output.2)
        )
    }

    nonisolated private static func codeFenceLanguage(from firstLine: String) -> String {
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return String(trimmed.drop { $0 == "`" }).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("~~~") {
            return String(trimmed.drop { $0 == "~" }).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    nonisolated private static func stripPrefix(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text) else {
            return text
        }

        return String(text[range.upperBound...])
    }

    nonisolated private static func normalizedAlignments(for table: MarkdownTable) -> [TableAlignment?] {
        var alignments = table.alignments
        while alignments.count < table.columnCount {
            alignments.append(nil)
        }
        return Array(alignments.prefix(table.columnCount))
    }

    nonisolated private static func padded(_ row: [String], to count: Int) -> [String] {
        var paddedRow = row
        while paddedRow.count < count {
            paddedRow.append("")
        }
        return Array(paddedRow.prefix(count))
    }
}

enum MarkdownInlineParser {
    private static let inlineRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(([^)]+)\)|\[([^\]]+)\]\(([^)]+)\)|`([^`\n]+)`|\*\*([^*\n]+)\*\*|__([^_\n]+)__|(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#
    )

    nonisolated static func parse(_ markdown: String) -> [MarkdownInlineNode] {
        let nsText = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = inlineRegex.matches(in: markdown, range: fullRange)

        guard !matches.isEmpty else {
            return [.text(markdown)]
        }

        var nodes: [MarkdownInlineNode] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                nodes.append(.text(nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }

            if match.range(at: 1).location != NSNotFound, match.range(at: 2).location != NSNotFound {
                let alt = nsText.substring(with: match.range(at: 1))
                let source = nsText.substring(with: match.range(at: 2))
                nodes.append(
                    .image(
                        alt: alt,
                        source: source,
                        markdown: nsText.substring(with: match.range)
                    )
                )
            } else if match.range(at: 3).location != NSNotFound, match.range(at: 4).location != NSNotFound {
                let title = nsText.substring(with: match.range(at: 3))
                let destination = nsText.substring(with: match.range(at: 4))
                nodes.append(
                    .link(
                        title: title,
                        destination: destination,
                        markdown: nsText.substring(with: match.range)
                    )
                )
            } else if match.range(at: 5).location != NSNotFound {
                nodes.append(.inlineCode(nsText.substring(with: match.range(at: 5))))
            } else if match.range(at: 6).location != NSNotFound {
                nodes.append(.strong(nsText.substring(with: match.range(at: 6))))
            } else if match.range(at: 7).location != NSNotFound {
                nodes.append(.strong(nsText.substring(with: match.range(at: 7))))
            } else if match.range(at: 8).location != NSNotFound {
                nodes.append(.emphasis(nsText.substring(with: match.range(at: 8))))
            } else if match.range(at: 9).location != NSNotFound {
                nodes.append(.emphasis(nsText.substring(with: match.range(at: 9))))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            nodes.append(.text(nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))))
        }

        return nodes
    }
}
