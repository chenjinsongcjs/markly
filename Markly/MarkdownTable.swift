//
//  MarkdownTable.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation

/// Markdown 表格解析器
struct MarkdownTable {
    /// 表头单元格
    let headers: [String]

    /// 行数据（每行是一个单元格数组）
    let rows: [[String]]

    /// 表格对齐方式（nil 表示默认左对齐）
    let alignments: [TableAlignment?]

    /// 是否有效
    var isValid: Bool {
        !headers.isEmpty
    }

    /// 行数
    var rowCount: Int {
        rows.count
    }

    /// 列数
    var columnCount: Int {
        headers.count
    }

    /// 转换为 Markdown 字符串
    func toMarkdown() -> String {
        var markdown = ""

        // 表头行
        markdown += "| " + headers.joined(separator: " | ") + " |\n"

        // 对齐行
        let alignmentRow = alignments.map { alignment in
            switch alignment {
            case .left:
                return ":---"
            case .center:
                return ":---:"
            case .right:
                return "---:"
            case nil:
                return "---"
            }
        }
        markdown += "| " + alignmentRow.joined(separator: " | ") + " |\n"

        // 数据行
        for row in rows {
            // 确保每行都有正确的列数
            let paddedRow = paddingRow(to: columnCount, row: row)
            markdown += "| " + paddedRow.joined(separator: " | ") + " |\n"
        }

        return markdown
    }

    /// 添加新行
    func addRow(_ row: [String]) -> MarkdownTable {
        let paddedRow = paddingRow(to: columnCount, row: row)
        let newRows = rows + [paddedRow]
        return MarkdownTable(headers: headers, rows: newRows, alignments: alignments)
    }

    /// 删除指定行
    func removeRow(at index: Int) -> MarkdownTable {
        guard index >= 0 && index < rowCount else { return self }
        var newRows = rows
        newRows.remove(at: index)
        return MarkdownTable(headers: headers, rows: newRows, alignments: alignments)
    }

    /// 更新指定单元格
    func updateCell(row: Int, column: Int, value: String) -> MarkdownTable {
        guard row >= 0 && row < rowCount, column >= 0 && column < columnCount else {
            return self
        }

        var newRows = rows
        var newRow = newRows[row]
        newRow[column] = value
        newRows[row] = newRow

        return MarkdownTable(headers: headers, rows: newRows, alignments: alignments)
    }

    /// 删除指定列
    func removeColumn(at index: Int) -> MarkdownTable {
        guard index >= 0 && index < columnCount else { return self }

        var newHeaders = headers
        newHeaders.remove(at: index)

        var newAlignments = alignments
        newAlignments.remove(at: index)

        let newRows = rows.map { row in
            var newRow = row
            newRow.remove(at: index)
            return newRow
        }

        return MarkdownTable(headers: newHeaders, rows: newRows, alignments: newAlignments)
    }

    /// 在指定位置添加列
    func addColumn(at index: Int, header: String, alignment: TableAlignment? = nil) -> MarkdownTable {
        let clampedIndex = max(0, min(index, columnCount))

        var newHeaders = headers
        newHeaders.insert(header, at: clampedIndex)

        var newAlignments = alignments
        newAlignments.insert(alignment, at: clampedIndex)

        let newRows = rows.map { row in
            var newRow = row
            newRow.insert("", at: clampedIndex)
            return newRow
        }

        return MarkdownTable(headers: newHeaders, rows: newRows, alignments: newAlignments)
    }

    // MARK: - Private Helpers

    private func paddingRow(to count: Int, row: [String]) -> [String] {
        var padded = row
        while padded.count < count {
            padded.append("")
        }
        return Array(padded.prefix(count))
    }
}

/// 表格对齐方式
enum TableAlignment: String {
    case left
    case center
    case right

    var localizedName: String {
        switch self {
        case .left:
            return "左对齐"
        case .center:
            return "居中"
        case .right:
            return "右对齐"
        }
    }

    var symbol: String {
        switch self {
        case .left:
            return "⬅️"
        case .center:
            return "↔️"
        case .right:
            return "➡️"
        }
    }
}

// MARK: - MarkdownTable Parsing

extension MarkdownTable {
    /// 从 Markdown 文本解析表格
    /// - Parameter markdown: Markdown 文本
    /// - Returns: 解析结果，如果文本不是表格则返回 nil
    static func parse(from markdown: String) -> MarkdownTable? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        // 至少需要表头和对齐行
        guard lines.count >= 2 else { return nil }

        let headerLine = lines[0]
        let alignmentLine = lines[1]

        // 检查是否是表格
        guard isTableRow(headerLine) && isAlignmentRow(alignmentLine) else { return nil }

        // 解析表头
        guard let headers = parseTableRow(headerLine) else { return nil }

        // 解析对齐方式
        let alignments = parseAlignments(from: alignmentLine, columnCount: headers.count)

        // 解析数据行
        var rows: [[String]] = []
        for i in 2..<lines.count {
            if let row = parseTableRow(lines[i]) {
                let paddedRow = paddingRow(to: headers.count, row: row)
                rows.append(paddedRow)
            } else {
                // 遇到非表格行，停止解析
                break
            }
        }

        return MarkdownTable(headers: headers, rows: rows, alignments: alignments)
    }

    /// 从完整的 Markdown 文本中提取第一个表格
    static func extractFirst(from markdown: String) -> MarkdownTable? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            if isTableRow(line) && index + 1 < lines.count && isAlignmentRow(lines[index + 1]) {
                // 提取从当前行开始的表格块
                let tableLines = Array(lines[index...].prefix { isTableRow($0) || isAlignmentRow($0) })
                return parse(from: tableLines.joined(separator: "\n"))
            }
        }

        return nil
    }

    /// 查找表格在文本中的位置
    static func findTableRange(in markdown: String) -> Range<String.Index>? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var startIndex: Int?
        var endIndex: Int?

        for (index, line) in lines.enumerated() {
            if isTableRow(String(line)) &&
                index + 1 < lines.count &&
                isAlignmentRow(String(lines[index + 1])) {
                if startIndex == nil {
                    startIndex = index
                }
            } else if startIndex != nil {
                // 遇到非表格行，表格结束
                endIndex = index - 1
                break
            }
        }

        // 如果最后一行是表格的一部分
        if startIndex != nil && endIndex == nil && !lines.isEmpty {
            endIndex = lines.count - 1
        }

        guard let start = startIndex, let end = endIndex else { return nil }

        // 计算字符范围
        let characterIndices = markdown.indices
        var characterStart: String.Index?
        var characterEnd: String.Index?

        var currentLine = 0
        for characterIndex in characterIndices {
            if markdown[characterIndex] == "\n" {
                currentLine += 1
                if currentLine == start {
                    characterStart = markdown.index(after: characterIndex)
                } else if currentLine == end {
                    characterEnd = characterIndex
                    break
                }
            }
        }

        guard let charStart = characterStart, let charEnd = characterEnd else {
            return nil
        }

        return charStart..<charEnd
    }

    // MARK: - Private Parsing Helpers

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2
    }

    private static func isAlignmentRow(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }

        let content = line.trimmingCharacters(in: .whitespaces)
        let cells = content.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: true)

        // 检查每个单元格是否都是对齐语法
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        let content = line.trimmingCharacters(in: .whitespaces)
        guard content.hasPrefix("|") && content.hasSuffix("|") else { return nil }

        let cells = content.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseAlignments(from line: String, columnCount: Int) -> [TableAlignment?] {
        guard let cells = parseTableRow(line) else { return Array(repeating: nil, count: columnCount) }

        var alignments: [TableAlignment?] = []
        for cell in cells.prefix(columnCount) {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") {
                alignments.append(.center)
            } else if trimmed.hasPrefix(":") {
                alignments.append(.left)
            } else if trimmed.hasSuffix(":") {
                alignments.append(.right)
            } else {
                alignments.append(nil)
            }
        }

        // 填充缺失的对齐
        while alignments.count < columnCount {
            alignments.append(nil)
        }

        return alignments
    }

    private static func paddingRow(to count: Int, row: [String]) -> [String] {
        var padded = row
        while padded.count < count {
            padded.append("")
        }
        return Array(padded.prefix(count))
    }
}

// MARK: - String Extension for Markdown

extension String {
    /// 尝试将文本作为 Markdown 表格解析
    var asMarkdownTable: MarkdownTable? {
        MarkdownTable.parse(from: self)
    }

    /// 从文本中提取第一个表格
    var extractFirstTable: MarkdownTable? {
        MarkdownTable.extractFirst(from: self)
    }
}
