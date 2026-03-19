//
//  TableEditorView.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import AppKit
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
        .onAppear {
            guard editingCell == nil, table.rowCount > 0, table.columnCount > 0 else { return }
            setEditingCell(row: 0, column: 0)
        }
        .onChange(of: table.rowCount) { _, _ in
            normalizeEditingCell()
        }
        .onChange(of: table.columnCount) { _, _ in
            normalizeEditingCell()
        }
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
        let isFocused = editingCell?.row == row && editingCell?.column == column

        return TableCellTextField(
            text: Binding(
                get: { cellEdits[key] ?? table.rows[row][column] },
                set: { cellEdits[key] = $0 }
            ),
            isFocused: isFocused,
            onFocus: {
                setEditingCell(row: row, column: column)
            },
            onSubmit: {
                moveToNextCell(from: (row, column))
            },
            onNavigate: { direction in
                handleNavigation(direction, from: TableCellCoordinate(row: row, column: column))
            }
        )
        .frame(width: 100, alignment: .leading)
        .padding(8)
        .background(
            isFocused ? Color.accentColor.opacity(0.15) : Color.clear
        )
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

        let targetRow = min(index, max(0, table.rowCount - 1))
        if table.columnCount > 0, table.rowCount > 0 {
            setEditingCell(row: targetRow, column: min(editingCell?.column ?? 0, table.columnCount - 1))
        }
    }

    private func removeRow(at index: Int) {
        table = table.removeRow(at: index)
        normalizeEditingCell()
    }

    private func removeColumn(at index: Int) {
        table = table.removeColumn(at: index)
        normalizeEditingCell()
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
        handleNavigation(.forward, from: TableCellCoordinate(row: cell.row, column: cell.column))
    }

    private func applyNavigationResult(_ result: TableCellNavigationResult) {
        switch result {
        case .focus(let coordinate):
            setEditingCell(row: coordinate.row, column: coordinate.column)
        case .appendRowAndFocus(let coordinate):
            let newRow = Array(repeating: "", count: table.columnCount)
            table = table.addRow(newRow)
            setEditingCell(row: coordinate.row, column: coordinate.column)
        case .stay:
            break
        }
    }

    private func handleNavigation(_ direction: TableCellNavigationDirection, from cell: TableCellCoordinate) {
        applyNavigationResult(
            TableCellNavigator.navigate(
                from: cell,
                direction: direction,
                rowCount: table.rowCount,
                columnCount: table.columnCount
            )
        )
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

    private func setEditingCell(row: Int, column: Int) {
        let coordinate = (row: row, column: column)
        editingCell = coordinate
        selectedCell = coordinate
    }

    private func normalizeEditingCell() {
        guard table.rowCount > 0, table.columnCount > 0 else {
            editingCell = nil
            selectedCell = nil
            return
        }

        guard let editingCell else {
            setEditingCell(row: 0, column: 0)
            return
        }

        let normalizedRow = min(max(0, editingCell.row), table.rowCount - 1)
        let normalizedColumn = min(max(0, editingCell.column), table.columnCount - 1)
        setEditingCell(row: normalizedRow, column: normalizedColumn)
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

private struct TableCellTextField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onNavigate: (TableCellNavigationDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocus: onFocus,
            onSubmit: onSubmit,
            onNavigate: onNavigate
        )
    }

    func makeNSView(context: Context) -> NavigatingTableTextField {
        let textField = NavigatingTableTextField()
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = context.coordinator
        textField.navigationHandler = context.coordinator.handleNavigation
        textField.focusHandler = context.coordinator.handleFocus
        textField.submitHandler = context.coordinator.handleSubmit
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ nsView: NavigatingTableTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.navigationHandler = context.coordinator.handleNavigation
        nsView.focusHandler = context.coordinator.handleFocus
        nsView.submitHandler = context.coordinator.handleSubmit

        if isFocused, nsView.window?.firstResponder != nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onFocus: () -> Void
        private let onSubmit: () -> Void
        private let onNavigate: (TableCellNavigationDirection) -> Void

        init(
            text: Binding<String>,
            onFocus: @escaping () -> Void,
            onSubmit: @escaping () -> Void,
            onNavigate: @escaping (TableCellNavigationDirection) -> Void
        ) {
            _text = text
            self.onFocus = onFocus
            self.onSubmit = onSubmit
            self.onNavigate = onNavigate
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            onFocus()
        }

        func handleFocus() {
            onFocus()
        }

        func handleSubmit() {
            onSubmit()
        }

        func handleNavigation(_ direction: TableCellNavigationDirection) {
            onNavigate(direction)
        }
    }
}

private final class NavigatingTableTextField: NSTextField {
    var navigationHandler: ((TableCellNavigationDirection) -> Void)?
    var focusHandler: (() -> Void)?
    var submitHandler: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            focusHandler?()
        }
        return result
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        focusHandler?()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 48:
            navigationHandler?(event.modifierFlags.contains(.shift) ? .backward : .forward)
        case 36, 76:
            submitHandler?()
        case 123:
            navigationHandler?(.left)
        case 124:
            navigationHandler?(.right)
        case 125:
            navigationHandler?(.down)
        case 126:
            navigationHandler?(.up)
        default:
            super.keyDown(with: event)
        }
    }
}
