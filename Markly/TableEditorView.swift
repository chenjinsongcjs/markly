//
//  TableEditorView.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import SwiftUI

/// 表格编辑视图
struct TableEditorView: View {
    @Binding var table: MarkdownTable
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCell: (row: Int, column: Int)?
    @State private var editingCell: (row: Int, column: Int)?
    @State private var cellEdits: [String: String] = [:]

    var onSave: ((MarkdownTable) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerBar

            Divider()

            // 表格编辑器
            ScrollView([.horizontal, .vertical]) {
                tableView
                    .padding()
            }

            Divider()

            // 底部操作栏
            actionToolbar
        }
        .frame(minWidth: 600, minHeight: 400)
        .onDisappear {
            saveChanges()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text("表格编辑器")
                .font(.title3.weight(.semibold))

            Spacer()

            Text("\(table.columnCount) 列 × \(table.rowCount) 行")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("取消") {
                dismiss()
            }

            Button("保存") {
                saveChanges()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Table View

    private var tableView: some View {
        VStack(spacing: 0) {
            // 表头
            headerRow

            Divider()

            // 数据行
            ForEach(0..<table.rowCount, id: \.self) { rowIndex in
                dataRow(at: rowIndex)

                if rowIndex < table.rowCount - 1 {
                    Divider()
                }
            }

            // 添加新行按钮
            addRowButton
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                headerCell(at: columnIndex)

                if columnIndex < table.columnCount - 1 {
                    Divider()
                        .frame(height: 40)
                }
            }
        }
        .frame(height: 40)
        .background(Color.accentColor.opacity(0.1))
    }

    private func headerCell(at index: Int) -> some View {
        let header = table.headers[index]
        let alignment = alignments[index]

        return HStack {
            Menu {
                Button("左对齐") {
                    updateAlignment(at: index, to: .left)
                }
                Button("居中") {
                    updateAlignment(at: index, to: .center)
                }
                Button("右对齐") {
                    updateAlignment(at: index, to: .right)
                }
                Divider()
                Button("删除列", role: .destructive) {
                    removeColumn(at: index)
                }
            } label: {
                Text(header)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: alignmentAsFrame(alignment))
            }
            .menuStyle(.borderlessButton)

            Text(alignment?.symbol ?? TableAlignment.left.symbol)
                .font(.caption2)
        }
        .frame(width: 100)
        .padding(.horizontal, 8)
        .background(
            selectedCell?.column == index && selectedCell?.row == -1 ?
            Color.accentColor.opacity(0.2) : Color.clear
        )
        .onTapGesture {
            selectedCell = (row: -1, column: index)
        }
    }

    private func dataRow(at rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                dataCell(row: rowIndex, column: columnIndex)

                if columnIndex < table.columnCount - 1 {
                    Divider()
                }
            }

            // 行操作按钮
            rowActionMenu(at: rowIndex)
        }
    }

    private func dataCell(row: Int, column: Int) -> some View {
        let key = "\(row)-\(column)"

        return TextField("...", text: Binding(
            get: { cellEdits[key] ?? table.rows[row][column] },
            set: { cellEdits[key] = $0 }
        ))
        .textFieldStyle(.plain)
        .frame(width: 100, alignment: .leading)
        .padding(8)
        .background(
            editingCell?.row == row && editingCell?.column == column ?
            Color.accentColor.opacity(0.15) : Color.clear
        )
        .onTapGesture {
            editingCell = (row: row, column: column)
        }
        .submitLabel(.next)
        .onSubmit {
            moveToNextCell(from: (row, column))
        }
    }

    private func rowActionMenu(at index: Int) -> some View {
        Menu {
            Button("在上方插入行") {
                insertRow(at: index)
            }
            Button("在下方插入行") {
                insertRow(at: index + 1)
            }
            Divider()
            Button("删除行", role: .destructive) {
                removeRow(at: index)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 32)
    }

    private var addRowButton: some View {
        Button {
            let newRow = Array(repeating: "", count: table.columnCount)
            table = table.addRow(newRow)
        } label: {
            Label("添加行", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(8)
        .foregroundStyle(.secondary)
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 16) {
            Button {
                table = table.addColumn(
                    at: table.columnCount,
                    header: "新列",
                    alignment: nil
                )
            } label: {
                Label("添加列", systemImage: "plus.rectangle.on.rectangle")
            }

            Spacer()

            Button("插入表格") {
                insertTableAtCursor()
            }
            .disabled(onSave == nil)

            Button("清空表格") {
                if table.rowCount > 0 && table.columnCount > 0 {
                    let emptyHeaders = Array(repeating: "", count: table.columnCount)
                    let emptyRows = Array(repeating: Array(repeating: "", count: table.columnCount), count: table.rowCount)
                    let emptyAlignments = Array(repeating: nil as TableAlignment?, count: table.columnCount)
                    table = MarkdownTable(
                        headers: emptyHeaders,
                        rows: emptyRows,
                        alignments: emptyAlignments
                    )
                }
            }
            .disabled(table.rowCount == 0 || table.columnCount == 0)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func insertRow(at index: Int) {
        let newRow = Array(repeating: "", count: table.columnCount)

        if index == 0 {
            table = MarkdownTable(
                headers: table.headers,
                rows: [newRow] + table.rows,
                alignments: table.alignments
            )
        } else if index >= table.rowCount {
            table = table.addRow(newRow)
        } else {
            var newRows = table.rows
            newRows.insert(newRow, at: index)
            table = MarkdownTable(
                headers: table.headers,
                rows: newRows,
                alignments: table.alignments
            )
        }
    }

    private func removeRow(at index: Int) {
        table = table.removeRow(at: index)
    }

    private func removeColumn(at index: Int) {
        table = table.removeColumn(at: index)
    }

    private func updateAlignment(at index: Int, to alignment: TableAlignment) {
        var newAlignments = table.alignments
        if index < newAlignments.count {
            newAlignments[index] = alignment
        } else {
            while newAlignments.count <= index {
                newAlignments.append(nil)
            }
            newAlignments[index] = alignment
        }
        table = MarkdownTable(
            headers: table.headers,
            rows: table.rows,
            alignments: newAlignments
        )
    }

    private func moveToNextCell(from cell: (row: Int, column: Int)) {
        let nextColumn = cell.column + 1
        let nextRow = cell.row

        if nextColumn < table.columnCount {
            editingCell = (row: nextRow, column: nextColumn)
        } else if nextRow + 1 < table.rowCount {
            editingCell = (row: nextRow + 1, column: 0)
        } else {
            // 到达末尾，添加新行
            let newRow = Array(repeating: "", count: table.columnCount)
            table = table.addRow(newRow)
            editingCell = (row: table.rowCount - 1, column: 0)
        }
    }

    private func saveChanges() {
        // 应用所有编辑
        var updatedTable = table
        for (key, value) in cellEdits {
            let components = key.split(separator: "-")
            if components.count == 2,
               let row = Int(components[0]),
               let column = Int(components[1]) {
                updatedTable = updatedTable.updateCell(row: row, column: column, value: value)
            }
        }

        table = updatedTable
        onSave?(table)
    }

    private func insertTableAtCursor() {
        onSave?(table)
        dismiss()
    }

    // MARK: - Helpers

    private var alignments: [TableAlignment?] {
        table.alignments
    }

    private func alignmentAsFrame(_ alignment: TableAlignment?) -> Alignment {
        switch alignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        case nil:
            return .leading
        }
    }
}
