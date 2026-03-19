//
//  EditorInteractionSupport.swift
//  Markly
//
//  Created by Codex on 2026/3/19.
//

import Foundation

struct TableCellCoordinate: Hashable {
    let row: Int
    let column: Int
}

enum TableCellNavigationDirection {
    case left
    case right
    case up
    case down
    case forward
    case backward
}

enum TableCellNavigationResult: Equatable {
    case focus(TableCellCoordinate)
    case appendRowAndFocus(TableCellCoordinate)
    case stay
}

enum TableCellNavigator {
    static func navigate(
        from cell: TableCellCoordinate,
        direction: TableCellNavigationDirection,
        rowCount: Int,
        columnCount: Int
    ) -> TableCellNavigationResult {
        guard rowCount > 0, columnCount > 0 else { return .stay }

        switch direction {
        case .forward:
            if cell.column + 1 < columnCount {
                return .focus(TableCellCoordinate(row: cell.row, column: cell.column + 1))
            }
            if cell.row + 1 < rowCount {
                return .focus(TableCellCoordinate(row: cell.row + 1, column: 0))
            }
            return .appendRowAndFocus(TableCellCoordinate(row: rowCount, column: 0))
        case .backward:
            if cell.column > 0 {
                return .focus(TableCellCoordinate(row: cell.row, column: cell.column - 1))
            }
            if cell.row > 0 {
                return .focus(TableCellCoordinate(row: cell.row - 1, column: columnCount - 1))
            }
            return .stay
        case .left:
            guard cell.column > 0 else { return .stay }
            return .focus(TableCellCoordinate(row: cell.row, column: cell.column - 1))
        case .right:
            guard cell.column + 1 < columnCount else { return .stay }
            return .focus(TableCellCoordinate(row: cell.row, column: cell.column + 1))
        case .up:
            guard cell.row > 0 else { return .stay }
            return .focus(TableCellCoordinate(row: cell.row - 1, column: cell.column))
        case .down:
            guard cell.row + 1 < rowCount else { return .stay }
            return .focus(TableCellCoordinate(row: cell.row + 1, column: cell.column))
        }
    }
}

enum MarkdownAssetPathing {
    static func markdownPath(for assetURL: URL, relativeTo documentURL: URL?) -> String {
        let preferredURL: URL
        if let documentURL,
           let relativePath = relativePath(from: documentURL.deletingLastPathComponent(), to: assetURL) {
            preferredURL = URL(fileURLWithPath: relativePath)
        } else {
            preferredURL = assetURL
        }

        let rawPath: String
        if preferredURL.isFileURL {
            rawPath = preferredURL.path(percentEncoded: false)
        } else {
            rawPath = preferredURL.absoluteString
        }

        return rawPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    static func resolvedAssetURL(for source: String, relativeTo documentURL: URL?) -> URL? {
        if source.hasPrefix("file://"), let url = URL(string: source) {
            return url
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        if let remoteURL = URL(string: source), let scheme = remoteURL.scheme, !scheme.isEmpty {
            return remoteURL
        }

        guard let documentURL else { return nil }
        return documentURL.deletingLastPathComponent().appendingPathComponent(source)
    }

    private static func relativePath(from baseDirectoryURL: URL, to targetURL: URL) -> String? {
        guard baseDirectoryURL.isFileURL, targetURL.isFileURL else { return nil }

        let baseComponents = standardizedPathComponents(for: baseDirectoryURL)
        let targetComponents = standardizedPathComponents(for: targetURL)

        guard !baseComponents.isEmpty, !targetComponents.isEmpty else { return nil }
        guard baseComponents.first == targetComponents.first else { return nil }

        var sharedPrefixCount = 0
        while sharedPrefixCount < min(baseComponents.count, targetComponents.count),
              baseComponents[sharedPrefixCount] == targetComponents[sharedPrefixCount] {
            sharedPrefixCount += 1
        }

        let upwardMoves = Array(repeating: "..", count: max(0, baseComponents.count - sharedPrefixCount))
        let remainingPath = Array(targetComponents.dropFirst(sharedPrefixCount))
        let components = upwardMoves + remainingPath
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    private static func standardizedPathComponents(for url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    }
}

enum DocumentOutlineBehavior {
    static func visibleBlocks(
        from blocks: [MarkdownBlock],
        headingSections: [MarkdownHeadingSection],
        foldedHeadingLines: Set<Int>
    ) -> [MarkdownBlock] {
        blocks.filter { block in
            !headingSections.contains { section in
                foldedHeadingLines.contains(section.heading.lineNumber) &&
                section.hasContent &&
                block.lineStart > section.heading.lineNumber &&
                block.lineStart <= section.contentLineEnd
            }
        }
    }

    static func foldedEditorRanges(
        headingSections: [MarkdownHeadingSection],
        foldedHeadingLines: Set<Int>
    ) -> [ClosedRange<Int>] {
        headingSections.compactMap { section in
            guard foldedHeadingLines.contains(section.heading.lineNumber), section.hasContent else {
                return nil
            }

            return section.contentLineStart...section.contentLineEnd
        }
    }
}

struct DocumentPreviewRow: Equatable {
    let marker: String?
    let inlineNodes: [MarkdownInlineNode]
}

enum DocumentPreviewContent: Equatable {
    case paragraph([MarkdownInlineNode])
    case heading([MarkdownInlineNode])
    case list([DocumentPreviewRow])
    case taskList([DocumentPreviewRow])
    case quote([DocumentPreviewRow])
    case unsupported
}

enum DocumentPreviewSupport {
    static func content(for renderNode: MarkdownRenderNode) -> DocumentPreviewContent {
        switch renderNode {
        case .paragraph(let text):
            return .paragraph(MarkdownInlineParser.parse(text))
        case .heading(_, let text):
            return .heading(MarkdownInlineParser.parse(text))
        case .unorderedList(let items):
            return .list(items.map { DocumentPreviewRow(marker: "•", inlineNodes: MarkdownInlineParser.parse($0)) })
        case .orderedList(let items, let startIndex):
            return .list(
                items.enumerated().map { index, item in
                    DocumentPreviewRow(
                        marker: "\(startIndex + index).",
                        inlineNodes: MarkdownInlineParser.parse(item)
                    )
                }
            )
        case .taskList(let items):
            return .taskList(
                items.map { item in
                    DocumentPreviewRow(marker: nil, inlineNodes: MarkdownInlineParser.parse(item.text))
                }
            )
        case .quote(let text):
            let rows = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .map { DocumentPreviewRow(marker: nil, inlineNodes: MarkdownInlineParser.parse($0)) }
            return .quote(rows)
        default:
            return .unsupported
        }
    }
}
