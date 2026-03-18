//
//  EditorRootView.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import AppKit
import SwiftUI

private struct PreviewTaskItem: Identifiable {
    let lineNumber: Int
    let text: String
    let isCompleted: Bool

    var id: Int { lineNumber }
}

private struct PreviewLinkItem: Identifiable {
    let title: String
    let destination: URL
    let markdown: String

    var id: String { markdown }
}

private struct PreviewImageItem {
    let alt: String
    let source: String
    let url: URL?
}

private struct TableEditingContext: Identifiable {
    let block: MarkdownBlock
    var table: MarkdownTable

    var id: String { block.id }
}

private enum EditorInsertSheet: String, Identifiable {
    case link
    case image

    var id: String { rawValue }
}

private enum BlockMoveDirection {
    case up
    case down
}

private struct LinkEditingContext {
    let blockLineStart: Int
    let originalMarkdown: String
}

private struct ImageEditingContext {
    let lineNumber: Int
}

private struct SearchMatch: Identifiable {
    let range: Range<String.Index>
    let index: Int

    var id: Int { index }
}

struct EditorRootView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @State private var viewMode: EditorViewMode = EditorPreferences.shared.viewMode
    @State private var editMode: EditorEditMode = EditorPreferences.shared.editMode
    @State private var selectionState = EditorSelectionState()
    @State private var requestedLine: Int?
    @State private var revealedLine: Int?
    @State private var foldedHeadingLines: Set<Int> = []
    @State private var activeInsertSheet: EditorInsertSheet?
    @State private var linkTitleDraft = ""
    @State private var linkURLDraft = "https://"
    @State private var imageAltDraft = ""
    @State private var imageSourceDraft = ""
    @State private var linkEditingContext: LinkEditingContext?
    @State private var imageEditingContext: ImageEditingContext?
    @State private var showExportSheet = false
    @State private var exportSucceeded = false
    @State private var showSearchSheet = false
    @State private var showPreferencesSheet = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var currentSearchIndex = 0
    @State private var activeEditingBlockID: String?
    @State private var editingBlockText = ""
    @State private var tableEditingContext: TableEditingContext?
    @FocusState private var blockEditorFocused: Bool

    private let preferences = EditorPreferences.shared

    private var blocks: [MarkdownBlock] {
        MarkdownAnalysis.blocks(in: document.text)
    }

    private var headings: [MarkdownHeading] {
        MarkdownAnalysis.headings(in: document.text)
    }

    private var headingSections: [MarkdownHeadingSection] {
        MarkdownAnalysis.headingSections(in: document.text)
    }

    private var blockCounts: [MarkdownBlockKind: Int] {
        MarkdownAnalysis.blockCounts(in: document.text)
    }

    private var visiblePreviewBlocks: [MarkdownBlock] {
        blocks.filter { block in
            !headingSections.contains { section in
                foldedHeadingLines.contains(section.heading.lineNumber) &&
                section.hasContent &&
                block.lineStart > section.heading.lineNumber &&
                block.lineStart <= section.contentLineEnd
            }
        }
    }

    private var currentBlock: MarkdownBlock? {
        if let activeEditingBlockID {
            return blocks.first(where: { $0.id == activeEditingBlockID })
        }

        return MarkdownAnalysis.block(containingLine: selectionState.line, in: document.text)
    }

    private var currentHeadingLine: Int? {
        guard let currentBlock else { return nil }
        if currentBlock.kind == .heading {
            return currentBlock.lineStart
        }

        return headings.last(where: { $0.lineNumber <= currentBlock.lineStart })?.lineNumber
    }

    private var currentHeadingSection: MarkdownHeadingSection? {
        guard let currentHeadingLine else { return nil }
        return headingSections.first(where: { $0.heading.lineNumber == currentHeadingLine })
    }

    private var previousHeading: MarkdownHeading? {
        guard let currentHeadingLine else { return nil }
        return headings.last(where: { $0.lineNumber < currentHeadingLine })
    }

    private var nextHeading: MarkdownHeading? {
        guard let currentHeadingLine else { return headings.first }
        return headings.first(where: { $0.lineNumber > currentHeadingLine })
    }

    private var highlightedEditorLineRange: ClosedRange<Int>? {
        guard let currentHeadingSection else { return nil }
        return currentHeadingSection.heading.lineNumber...max(
            currentHeadingSection.heading.lineNumber,
            currentHeadingSection.contentLineEnd
        )
    }

    private var softFoldedEditorRanges: [ClosedRange<Int>] {
        headingSections.compactMap { section in
            guard foldedHeadingLines.contains(section.heading.lineNumber), section.hasContent else {
                return nil
            }

            return section.contentLineStart...section.contentLineEnd
        }
    }

    private var searchMatches: [SearchMatch] {
        guard let query = searchText.nonEmpty else { return [] }

        var matches: [SearchMatch] = []
        var searchStart = document.text.startIndex
        var index = 0
        let loweredContent = document.text.lowercased()
        let loweredQuery = query.lowercased()

        while searchStart < document.text.endIndex,
              let range = loweredContent.range(of: loweredQuery, range: searchStart..<loweredContent.endIndex) {
            matches.append(SearchMatch(range: range, index: index))
            searchStart = range.upperBound
            index += 1
        }

        return matches
    }

    private var currentSearchMatch: SearchMatch? {
        guard !searchMatches.isEmpty else { return nil }
        let safeIndex = min(max(0, currentSearchIndex), searchMatches.count - 1)
        return searchMatches[safeIndex]
    }

    private var lineCount: Int {
        max(1, MarkdownAnalysis.lines(in: document.text).count)
    }

    private var wordCount: Int {
        document.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var listBlockCount: Int {
        blockCounts[.unorderedList, default: 0] +
        blockCounts[.orderedList, default: 0] +
        blockCounts[.taskList, default: 0]
    }

    private var dominantBlockKind: MarkdownBlockKind? {
        blockCounts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    private var documentSelectionState: EditorSelectionState {
        if let currentBlock {
            return EditorSelectionState(line: currentBlock.lineStart, column: 1, selectedLength: 0)
        }

        return selectionState
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            editorPane
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        .toolbar {
            ToolbarItemGroup {
                toolbarCommandButton("标题", systemImage: "textformat", command: .heading)
                toolbarCommandButton("粗体", systemImage: "bold", command: .bold)
                toolbarCommandButton("斜体", systemImage: "italic", command: .italic)
                toolbarCommandButton("代码", systemImage: "chevron.left.forwardslash.chevron.right", command: .inlineCode)
                toolbarCommandButton("代码块", systemImage: "curlybraces.square", command: .codeFence)
                insertToolbarButton("链接", systemImage: "link", sheet: .link)
                insertToolbarButton("图片", systemImage: "photo", sheet: .image)
                toolbarCommandButton("引用", systemImage: "text.bubble", command: .quote)
                toolbarCommandButton("列表", systemImage: "list.bullet", command: .bulletList)
                toolbarCommandButton("编号", systemImage: "list.number", command: .orderedList)
                toolbarCommandButton("任务", systemImage: "checkmark.square", command: .taskList)
                toolbarCommandButton("勾选", systemImage: "checkmark.circle", command: .toggleTaskCompletion)
                foldToolbarButton
                Divider()
                searchToolbarButton
                preferencesToolbarButton
                viewModeToolbarMenu
                editModeToolbarMenu
            }

            ToolbarItemGroup(placement: .primaryAction) {
                exportButton
            }
        }
        .sheet(item: $activeInsertSheet) { sheet in
            switch sheet {
            case .link:
                linkInsertSheet
            case .image:
                imageInsertSheet
            }
        }
        .sheet(item: $tableEditingContext) { context in
            tableEditorSheet(context)
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
        .sheet(isPresented: $showPreferencesSheet) {
            preferencesSheet
        }
        .alert("导出成功", isPresented: $exportSucceeded) {
            Button("确定") {
                exportSucceeded = false
            }
        } message: {
            Text("文档已成功导出")
        }
        .onAppear {
            viewMode = preferences.viewMode
            editMode = preferences.editMode
        }
        .onChange(of: viewMode) { _, newValue in
            preferences.viewMode = newValue
        }
        .onChange(of: editMode) { _, newValue in
            preferences.editMode = newValue
        }
        .onChange(of: document.text) { _, _ in
            if currentSearchIndex >= searchMatches.count {
                currentSearchIndex = max(0, searchMatches.count - 1)
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("文档") {
                Label(viewMode == .document ? "文档模式" : "源码模式", systemImage: viewMode.systemImage)
                Label("\(wordCount) 字", systemImage: "textformat")
                Label("\(lineCount) 行", systemImage: "list.number")
                Label("\(blocks.count) 块", systemImage: "square.stack.3d.up")
            }

            Section("Typora 方向") {
                Label("单文档编辑为主", systemImage: "doc.richtext")
                Label("源码模式为辅助", systemImage: "text.cursor")
                Label("双击内容块进入编辑", systemImage: "cursorarrow.click.2")
            }

            Section("大纲") {
                if headings.isEmpty {
                    Text("还没有标题")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(headings) { heading in
                        let section = headingSections.first(where: { $0.heading.lineNumber == heading.lineNumber })
                        HStack(spacing: 8) {
                            if let section, section.hasContent {
                                Button {
                                    toggleFold(for: heading.lineNumber)
                                } label: {
                                    Image(systemName: foldedHeadingLines.contains(heading.lineNumber) ? "chevron.right" : "chevron.down")
                                        .font(.caption2.weight(.bold))
                                        .frame(width: 12)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(width: 12, height: 12)
                            }

                            Button {
                                requestedLine = heading.lineNumber
                                revealedLine = heading.lineNumber
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(heading.title)
                                        .fontWeight(currentHeadingLine == heading.lineNumber ? .semibold : .regular)
                                        .lineLimit(1)
                                    Text("H\(heading.level) · 第 \(heading.lineNumber) 行")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                        .background(currentHeadingLine == heading.lineNumber ? Color.accentColor.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            Section("结构") {
                blockCountRow("标题", kind: .heading, systemImage: "number.square")
                blockCountRow("段落", kind: .paragraph, systemImage: "paragraph")
                blockCountRow("引用", kind: .quote, systemImage: "text.bubble")
                blockCountRow("列表", count: listBlockCount, systemImage: "list.bullet")
                blockCountRow("表格", kind: .table, systemImage: "tablecells")
                blockCountRow("图片", kind: .image, systemImage: "photo")
                blockCountRow("代码块", kind: .codeFence, systemImage: "chevron.left.forwardslash.chevron.right")
                Label("已折叠 · \(foldedHeadingLines.count)", systemImage: "arrowtriangle.right.square")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Markly")
    }

    private var editorPane: some View {
        Group {
            switch viewMode {
            case .document:
                documentEditor
            case .source:
                sourceEditor
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("源码")

            if let currentHeadingSection {
                headingContextBar(currentHeadingSection)
                Divider()
            }

            NativeMarkdownEditor(
                text: $document.text,
                selectionState: $selectionState,
                requestedLine: $requestedLine,
                revealedLine: $revealedLine,
                highlightedLineRange: highlightedEditorLineRange,
                softFoldedLineRanges: softFoldedEditorRanges,
                editMode: editMode,
                fontSize: CGFloat(preferences.fontSize)
            )
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            StatusBarView(
                text: document.text,
                selectionState: selectionState,
                currentBlock: currentBlock
            )
        }
    }

    private var documentEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("文档")

            if let currentHeadingSection {
                headingContextBar(currentHeadingSection)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        documentSummary

                        ForEach(visiblePreviewBlocks) { block in
                            documentBlockView(block)
                                .id(block.id)
                        }
                    }
                    .frame(maxWidth: preferences.documentContentWidth, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .onChange(of: revealedLine) { _, newValue in
                    guard
                        let newValue,
                        let block = blocks.first(where: { ($0.lineStart...$0.lineEnd).contains(newValue) })
                    else { return }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(block.id, anchor: .center)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if revealedLine == newValue {
                            revealedLine = nil
                        }
                    }
                }
                .onChange(of: currentSearchMatch?.id) { _, _ in
                    guard let line = currentSearchLine else { return }
                    revealedLine = line
                }
            }

            Divider()

            StatusBarView(
                text: document.text,
                selectionState: documentSelectionState,
                currentBlock: currentBlock
            )
        }
    }

    private var documentSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typora 风格主路径")
                .font(.headline)

            HStack(spacing: 10) {
                previewChip(title: "标题", value: blockCounts[.heading, default: 0], color: .red)
                previewChip(title: "表格", value: blockCounts[.table, default: 0], color: .orange)
                previewChip(title: "图片", value: blockCounts[.image, default: 0], color: .green)
                previewChip(title: "代码块", value: blockCounts[.codeFence, default: 0], color: .indigo)
            }

            Text("双击任意块进入编辑，任务项可直接勾选，表格和图片支持专用编辑入口。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let dominantBlockKind {
                Text("当前文档以\(blockDisplayName(for: dominantBlockKind))为主。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func documentBlockView(_ block: MarkdownBlock) -> some View {
        if activeEditingBlockID == block.id, isInlineEditable(block) {
            blockEditorCard(block)
        } else {
            previewBlockView(block)
        }
    }

    private func blockEditorCard(_ block: MarkdownBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(blockDisplayName(for: block.kind), systemImage: blockSystemImage(for: block.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    cancelBlockEditing()
                }
                Button("应用") {
                    commitBlockEditing(block)
                }
                .buttonStyle(.borderedProminent)
            }

            TextEditor(text: $editingBlockText)
                .font(.system(size: CGFloat(preferences.fontSize), design: .monospaced))
                .frame(minHeight: block.kind == .codeFence ? 220 : 120)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($blockEditorFocused)

            HStack {
                Text("直接编辑该块对应的 Markdown。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下方插入段落") {
                    insertParagraph(after: block)
                }
                Button("删除块", role: .destructive) {
                    deleteBlock(block)
                    cancelBlockEditing()
                }
            }
        }
        .padding(16)
        .background(blockCardBackground(for: block, tint: .accentColor))
        .onAppear {
            blockEditorFocused = true
        }
    }

    @ViewBuilder
    private func previewBlockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)
        case .heading:
            previewHeadingView(block)
        case .taskList:
            previewTaskListView(block)
        case .codeFence:
            previewCodeFenceView(block)
        case .table:
            previewTableView(block)
        case .image:
            if let image = imageItem(in: block) {
                previewImageView(block, image: image)
            } else {
                previewTextBlockView(block)
            }
        default:
            previewTextBlockView(block)
        }
    }

    private func previewTextBlockView(_ block: MarkdownBlock) -> some View {
        let links = previewLinks(in: block.text)

        return VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            Text(highlightedMarkdownAttributedString(for: block))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isBlockCurrent(block) ? 1 : 0.96)

            if !links.isEmpty {
                HStack(spacing: 8) {
                    ForEach(links.prefix(3)) { link in
                        Button {
                            openURL(link.destination)
                        } label: {
                            Label(link.title, systemImage: "link")
                        }
                        .buttonStyle(.borderless)
                        .help(link.destination.absoluteString)
                        .contextMenu {
                            Button("打开链接") {
                                openURL(link.destination)
                            }
                            Button("编辑链接") {
                                beginEditingLink(link, in: block)
                            }
                            Button("删除链接") {
                                deleteLink(link, in: block)
                            }
                            Button("复制链接") {
                                copyToPasteboard(link.destination.absoluteString)
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(14)
        .background(blockCardBackground(for: block, tint: .blue))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            blockContextMenu(for: block)
        }
        .onTapGesture(count: 2) {
            beginEditingBlock(block)
        }
    }

    private func previewHeadingView(_ block: MarkdownBlock) -> some View {
        let heading = headings.first(where: { $0.lineNumber == block.lineStart })
        let isFolded = foldedHeadingLines.contains(block.lineStart)

        return VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            HStack(spacing: 10) {
                Text(heading.map { "H\($0.level)" } ?? "H")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(heading?.title ?? block.text.trimmingCharacters(in: .whitespaces))
                    .font(previewHeadingFont(for: heading?.level ?? 1))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if headingSections.contains(where: { $0.heading.lineNumber == block.lineStart && $0.hasContent }) {
                    Button {
                        toggleFold(for: block.lineStart)
                    } label: {
                        Image(systemName: isFolded ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Label("第 \(block.lineStart) 行", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let section = headingSections.first(where: { $0.heading.lineNumber == block.lineStart }), section.hasContent {
                    Text("\(max(0, section.contentLineEnd - section.heading.lineNumber)) 行内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .red))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            blockContextMenu(for: block)
        }
        .onTapGesture(count: 2) {
            beginEditingBlock(block)
        }
    }

    private func previewTaskListView(_ block: MarkdownBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            ForEach(taskItems(in: block)) { item in
                Button {
                    toggleTaskItem(at: item.lineNumber)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                            .padding(.top, 2)

                        Text(item.text.isEmpty ? " " : item.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .green))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            blockContextMenu(for: block)
        }
        .onTapGesture(count: 2) {
            beginEditingBlock(block)
        }
    }

    private func previewCodeFenceView(_ block: MarkdownBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(for: block, allowInlineEdit: true)

            HStack {
                Label(codeFenceLanguage(in: block.text), systemImage: "curlybraces.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    copyToPasteboard(block.text)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: block.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .indigo))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button("复制代码块") {
                copyToPasteboard(block.text)
            }
            Divider()
            blockContextMenu(for: block, includeNavigation: false)
        }
        .onTapGesture(count: 2) {
            beginEditingBlock(block)
        }
    }

    private func previewTableView(_ block: MarkdownBlock) -> some View {
        let parsedTable = MarkdownTable.parse(from: block.text)

        return VStack(alignment: .leading, spacing: 12) {
            blockHeader(for: block, allowInlineEdit: false)

            if let parsedTable {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(parsedTable.headers.enumerated()), id: \.offset) { _, header in
                            Text(header.nonEmpty ?? "列")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ForEach(Array(parsedTable.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value.nonEmpty ?? " ")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("表格内容无法解析，仍可切换到源码模式修复。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .orange))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            blockContextMenu(for: block)
        }
    }

    private func previewImageView(_ block: MarkdownBlock, image: PreviewImageItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(for: block, allowInlineEdit: false)

            HStack {
                Label(image.alt.isEmpty ? "图片" : image.alt, systemImage: "photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let url = image.url {
                    Button("打开") {
                        openURL(url)
                    }
                    .buttonStyle(.borderless)
                }
                Button("复制路径") {
                    copyToPasteboard(image.source)
                }
                .buttonStyle(.borderless)
            }

            imageDisplay(for: image)

            Text(image.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .green))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if let url = image.url {
                Button("打开图片") {
                    openURL(url)
                }
            }

            Button("编辑图片") {
                beginEditingImage(image, at: block.lineStart)
            }

            Button("删除图片") {
                deleteImage(at: block.lineStart)
            }

            Divider()
            blockContextMenu(for: block)
        }
    }

    @ViewBuilder
    private func imageDisplay(for image: PreviewImageItem) -> some View {
        switch preferences.imageDisplayMode {
        case .markdownOnly:
            Text(verbatim: "![\(image.alt)](\(image.source))")
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .compact:
            imagePreview(for: image, maxHeight: 120)
        case .full:
            imagePreview(for: image, maxHeight: 280)
        }
    }

    @ViewBuilder
    private func imagePreview(for image: PreviewImageItem, maxHeight: CGFloat) -> some View {
        if let nsImage = localImage(for: image.source) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let remoteURL = URL(string: image.source), ["http", "https"].contains(remoteURL.scheme?.lowercased()) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: maxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .failure, .empty:
                    previewImagePlaceholder(for: image.source, height: maxHeight)
                @unknown default:
                    previewImagePlaceholder(for: image.source, height: maxHeight)
                }
            }
        } else {
            previewImagePlaceholder(for: image.source, height: maxHeight)
        }
    }

    private func previewImagePlaceholder(for source: String, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func blockHeader(for block: MarkdownBlock, allowInlineEdit: Bool) -> some View {
        HStack {
            Label(blockDisplayName(for: block.kind), systemImage: blockSystemImage(for: block.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isSearchHit(block) {
                Text("匹配搜索")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer()

            Text("第 \(block.lineStart) 行")
                .font(.caption)
                .foregroundStyle(.secondary)

            if allowInlineEdit {
                Button("编辑") {
                    beginEditingBlock(block)
                }
                .buttonStyle(.borderless)
            } else if block.kind == .table {
                Button("编辑表格") {
                    beginEditingTable(block)
                }
                .buttonStyle(.borderless)
            } else if block.kind == .image {
                Button("编辑图片") {
                    if let image = imageItem(in: block) {
                        beginEditingImage(image, at: block.lineStart)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func paneTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if !searchMatches.isEmpty {
                Text("搜索结果 \(min(currentSearchIndex + 1, searchMatches.count))/\(searchMatches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func toolbarCommandButton(
        _ title: String,
        systemImage: String,
        command: MarkdownEditorCommand
    ) -> some View {
        Button {
            postEditorCommand(command)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help(title)
    }

    private func insertToolbarButton(
        _ title: String,
        systemImage: String,
        sheet: EditorInsertSheet
    ) -> some View {
        Button {
            activeInsertSheet = sheet
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help(title)
    }

    private var linkInsertSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("插入链接")
                .font(.title3.weight(.semibold))

            TextField("显示文本", text: $linkTitleDraft)
            TextField("URL", text: $linkURLDraft)

            HStack {
                Spacer()
                Button("取消") {
                    resetLinkSheet()
                }
                Button("插入") {
                    commitLinkChanges()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var imageInsertSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("插入图片")
                .font(.title3.weight(.semibold))

            TextField("图片描述", text: $imageAltDraft)
            TextField("图片地址或本地路径", text: $imageSourceDraft)

            HStack {
                Spacer()
                Button("取消") {
                    resetImageSheet()
                }
                Button("插入") {
                    commitImageChanges()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func tableEditorSheet(_ context: TableEditingContext) -> some View {
        TableEditorView(table: Binding(
            get: { context.table },
            set: { newValue in
                tableEditingContext = TableEditingContext(block: context.block, table: newValue)
            }
        )) { updatedTable in
            replaceBlock(context.block, with: updatedTable.toMarkdown())
            tableEditingContext = nil
        }
    }

    private var searchSheet: some View {
        FindReplaceSheet(
            searchText: $searchText,
            replaceText: $replaceText,
            matchCount: searchMatches.count,
            currentMatchIndex: searchMatches.isEmpty ? 0 : currentSearchIndex + 1,
            onPrevious: { moveToSearchMatch(step: -1) },
            onNext: { moveToSearchMatch(step: 1) },
            onReplaceCurrent: replaceCurrentSearchMatch,
            onReplaceAll: replaceAllSearchMatches
        )
    }

    private var preferencesSheet: some View {
        PreferencesSheetView(
            initialViewMode: preferences.viewMode,
            initialEditMode: preferences.editMode,
            initialFontSize: preferences.fontSize,
            initialDocumentWidth: preferences.documentContentWidth,
            initialAutoSaveInterval: preferences.autoSaveInterval,
            initialUseSystemAppearance: preferences.useSystemAppearance,
            initialImageDisplayMode: preferences.imageDisplayMode
        ) { newPreferences in
            preferences.viewMode = newPreferences.viewMode
            preferences.editMode = newPreferences.editMode
            preferences.fontSize = newPreferences.fontSize
            preferences.documentContentWidth = newPreferences.documentWidth
            preferences.autoSaveInterval = newPreferences.autoSaveInterval
            preferences.useSystemAppearance = newPreferences.useSystemAppearance
            preferences.imageDisplayMode = newPreferences.imageDisplayMode
            viewMode = newPreferences.viewMode
            editMode = newPreferences.editMode
        }
    }

    private var searchToolbarButton: some View {
        Button {
            showSearchSheet = true
        } label: {
            Label("查找替换", systemImage: "magnifyingglass")
        }
        .help("查找与替换")
    }

    private var preferencesToolbarButton: some View {
        Button {
            showPreferencesSheet = true
        } label: {
            Label("偏好设置", systemImage: "slider.horizontal.3")
        }
        .help("编辑器偏好设置")
    }

    private var foldToolbarButton: some View {
        Menu {
            Button("折叠当前标题", action: toggleCurrentHeadingFold)
                .disabled(currentHeadingSection == nil)
            Button("全部折叠", action: collapseAllHeadings)
                .disabled(headingSections.filter(\.hasContent).isEmpty)
            Button("全部展开", action: expandAllHeadings)
                .disabled(foldedHeadingLines.isEmpty)
        } label: {
            Label("折叠", systemImage: "arrowtriangle.right.square")
        }
        .help("标题折叠")
    }

    private func headingContextBar(_ section: MarkdownHeadingSection) -> some View {
        HStack(spacing: 12) {
            Label("H\(section.heading.level)", systemImage: "number.square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(section.heading.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            Text("第 \(section.heading.lineNumber) 行")
                .font(.caption)
                .foregroundStyle(.secondary)

            if section.hasContent {
                Text("\(max(0, section.contentLineEnd - section.heading.lineNumber)) 行内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(foldedHeadingLines.contains(section.heading.lineNumber) ? "展开" : "折叠") {
                    toggleFold(for: section.heading.lineNumber)
                }
                .buttonStyle(.borderless)
            }

            Divider()
                .frame(height: 14)

            Button {
                jumpToHeading(previousHeading)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(previousHeading == nil)

            Button {
                jumpToHeading(nextHeading)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(nextHeading == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.05))
    }

    private func blockCountRow(_ title: String, kind: MarkdownBlockKind, systemImage: String) -> some View {
        blockCountRow(title, count: blockCounts[kind, default: 0], systemImage: systemImage)
    }

    private func blockCountRow(_ title: String, count: Int, systemImage: String) -> some View {
        Label("\(title) · \(count)", systemImage: systemImage)
    }

    private func previewChip(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func markdownAttributedString(for markdown: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: markdown.isEmpty ? " " : markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return AttributedString(markdown)
        }
    }

    private func highlightedMarkdownAttributedString(for block: MarkdownBlock) -> AttributedString {
        let base = markdownAttributedString(for: block.text)
        guard let query = searchText.nonEmpty else { return base }

        let mutable = NSMutableAttributedString(base)
        let nsText = block.text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let regexPattern = NSRegularExpression.escapedPattern(for: query)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return base
        }

        let currentLine = currentSearchLine
        let isCurrentSearchBlock = currentLine.map { (block.lineStart...block.lineEnd).contains($0) } ?? false

        for (index, match) in regex.matches(in: block.text, range: fullRange).enumerated() {
            let isPrimaryMatch = isCurrentSearchBlock && index == 0
            mutable.addAttributes(
                [
                    .backgroundColor: NSColor.systemYellow.withAlphaComponent(isPrimaryMatch ? 0.38 : 0.18),
                    .foregroundColor: NSColor.labelColor
                ],
                range: match.range
            )
        }

        return AttributedString(mutable)
    }

    private func beginEditingBlock(_ block: MarkdownBlock) {
        guard isInlineEditable(block) else {
            if block.kind == .table {
                beginEditingTable(block)
            } else if block.kind == .image, let image = imageItem(in: block) {
                beginEditingImage(image, at: block.lineStart)
            }
            return
        }

        activeEditingBlockID = block.id
        editingBlockText = block.text
        requestedLine = block.lineStart
        revealedLine = block.lineStart
    }

    private func commitBlockEditing(_ block: MarkdownBlock) {
        let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteBlock(block)
        } else {
            replaceBlock(block, with: editingBlockText)
        }
        cancelBlockEditing()
    }

    private func cancelBlockEditing() {
        activeEditingBlockID = nil
        editingBlockText = ""
        blockEditorFocused = false
    }

    private func beginEditingTable(_ block: MarkdownBlock) {
        guard let table = MarkdownTable.parse(from: block.text) else { return }
        tableEditingContext = TableEditingContext(block: block, table: table)
    }

    private func beginEditingLink(_ link: PreviewLinkItem, in block: MarkdownBlock) {
        linkTitleDraft = link.title
        linkURLDraft = link.destination.absoluteString
        linkEditingContext = LinkEditingContext(blockLineStart: block.lineStart, originalMarkdown: link.markdown)
        activeInsertSheet = .link
    }

    private func beginEditingImage(_ image: PreviewImageItem, at lineNumber: Int) {
        imageAltDraft = image.alt
        imageSourceDraft = image.source
        imageEditingContext = ImageEditingContext(lineNumber: lineNumber)
        activeInsertSheet = .image
    }

    private func deleteLink(_ link: PreviewLinkItem, in block: MarkdownBlock) {
        replaceFirstOccurrenceInBlock(
            startingAt: block.lineStart,
            target: link.markdown,
            replacement: link.title
        )
    }

    private func deleteImage(at lineNumber: Int) {
        replaceLine(lineNumber, with: "")
    }

    private func commitLinkChanges() {
        let newMarkdown = "[\(linkTitleDraft.nonEmpty ?? "链接文本")](\(linkURLDraft.nonEmpty ?? "https://"))"

        if let context = linkEditingContext {
            replaceFirstOccurrenceInBlock(
                startingAt: context.blockLineStart,
                target: context.originalMarkdown,
                replacement: newMarkdown
            )
        } else {
            postEditorCommand(
                .insertLink,
                payload: ["title": linkTitleDraft, "url": linkURLDraft]
            )
        }

        resetLinkSheet()
    }

    private func commitImageChanges() {
        let newMarkdown = "![\(imageAltDraft.nonEmpty ?? "图片描述")](\(imageSourceDraft.nonEmpty ?? "/path/to/image.png"))"

        if let context = imageEditingContext {
            replaceLine(context.lineNumber, with: newMarkdown)
        } else {
            postEditorCommand(
                .insertImage,
                payload: ["alt": imageAltDraft, "source": imageSourceDraft]
            )
        }

        resetImageSheet()
    }

    private func resetLinkSheet() {
        activeInsertSheet = nil
        linkEditingContext = nil
        linkTitleDraft = ""
        linkURLDraft = "https://"
    }

    private func resetImageSheet() {
        activeInsertSheet = nil
        imageEditingContext = nil
        imageAltDraft = ""
        imageSourceDraft = ""
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func codeFenceLanguage(in text: String) -> String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let language = firstLine.trimmingCharacters(in: .whitespaces).dropFirst(3).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "代码块" : language.uppercased()
    }

    private func previewLinks(in text: String) -> [PreviewLinkItem] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            let title = nsText.substring(with: match.range(at: 1))
            let rawURL = nsText.substring(with: match.range(at: 2))
            guard let destination = URL(string: rawURL) else { return nil }
            return PreviewLinkItem(
                title: title,
                destination: destination,
                markdown: nsText.substring(with: match.range)
            )
        }
    }

    private func imageItem(in block: MarkdownBlock) -> PreviewImageItem? {
        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#) else {
            return nil
        }

        let nsText = trimmed as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: trimmed, range: range) else { return nil }

        let source = nsText.substring(with: match.range(at: 2))
        return PreviewImageItem(
            alt: nsText.substring(with: match.range(at: 1)),
            source: source,
            url: imageURL(from: source)
        )
    }

    private func localImage(for source: String) -> NSImage? {
        if let resolvedURL = resolvedImageURL(from: source), resolvedURL.isFileURL {
            return NSImage(contentsOf: resolvedURL)
        }

        if source.hasPrefix("file://"), let url = URL(string: source) {
            return NSImage(contentsOf: url)
        }

        if source.hasPrefix("/") {
            return NSImage(contentsOfFile: source)
        }

        return nil
    }

    private func imageURL(from source: String) -> URL? {
        if let resolvedURL = resolvedImageURL(from: source) {
            return resolvedURL
        }

        if source.hasPrefix("file://") {
            return URL(string: source)
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        return URL(string: source)
    }

    private func resolvedImageURL(from source: String) -> URL? {
        if source.hasPrefix("file://"), let url = URL(string: source) {
            return url
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        if let remoteURL = URL(string: source), let scheme = remoteURL.scheme, !scheme.isEmpty {
            return remoteURL
        }

        guard let fileURL else { return nil }
        return fileURL.deletingLastPathComponent().appendingPathComponent(source)
    }

    private func replaceLine(_ lineNumber: Int, with replacement: String) {
        document.text = MarkdownAnalysis.replaceLine(lineNumber, with: replacement, in: document.text)
        requestedLine = lineNumber
        revealedLine = lineNumber
    }

    private func replaceFirstOccurrenceInBlock(startingAt lineNumber: Int, target: String, replacement: String) {
        guard let block = blocks.first(where: { $0.lineStart == lineNumber }) else { return }
        guard let range = block.text.range(of: target) else { return }
        let updatedBlockText = block.text.replacingCharacters(in: range, with: replacement)
        replaceBlock(block, with: updatedBlockText)
    }

    private func replaceBlock(_ block: MarkdownBlock, with replacement: String) {
        document.text = MarkdownAnalysis.replaceBlock(block, with: replacement, in: document.text)
        requestedLine = block.lineStart
        revealedLine = block.lineStart
    }

    private func insertParagraph(after block: MarkdownBlock) {
        document.text = MarkdownAnalysis.insertBlock("\n新段落", afterLine: block.lineEnd, in: document.text)
        let line = block.lineEnd + 2
        requestedLine = line
        revealedLine = line
        activeEditingBlockID = nil
    }

    private func convertBlockToHeading(_ block: MarkdownBlock, level: Int) {
        let normalized = normalizedLines(from: block)
        let title = normalized.first?.nonEmpty ?? "标题"
        let heading = String(repeating: "#", count: max(1, min(level, 6))) + " " + title
        replaceBlock(block, with: heading)
    }

    private func convertBlock(_ block: MarkdownBlock, to kind: MarkdownBlockKind) {
        let normalized = normalizedLines(from: block)
        let replacement: String

        switch kind {
        case .paragraph:
            replacement = normalized.joined(separator: "\n").nonEmpty ?? "段落内容"
        case .quote:
            replacement = normalized.map { $0.isEmpty ? "" : "> " + $0 }.joined(separator: "\n")
        case .unorderedList:
            replacement = normalized.map { $0.isEmpty ? "" : "- " + $0 }.joined(separator: "\n")
        case .orderedList:
            replacement = normalized.enumerated().map { index, line in
                line.isEmpty ? "" : "\(index + 1). " + line
            }.joined(separator: "\n")
        case .taskList:
            replacement = normalized.map { $0.isEmpty ? "" : "- [ ] " + $0 }.joined(separator: "\n")
        case .codeFence:
            let blockText = block.kind == .codeFence ? unwrapCodeFence(from: block.text) : block.text
            replacement = "```\n" + blockText.trimmingCharacters(in: .newlines) + "\n```"
        case .heading, .table, .image, .thematicBreak:
            replacement = block.text
        }

        replaceBlock(block, with: replacement)
    }

    private func normalizedLines(from block: MarkdownBlock) -> [String] {
        block.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(normalizeLineContent)
    }

    private func normalizeLineContent(_ line: String) -> String {
        let strippedQuote = replaceRegex(in: line, pattern: #"^\s*(?:>\s*)+"#, with: "")
        let strippedHeading = replaceRegex(in: strippedQuote, pattern: #"^\s*#{1,6}\s+"#, with: "")
        let strippedTask = replaceRegex(in: strippedHeading, pattern: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, with: "")
        let strippedUnordered = replaceRegex(in: strippedTask, pattern: #"^\s*[-*+]\s+"#, with: "")
        let strippedOrdered = replaceRegex(in: strippedUnordered, pattern: #"^\s*\d+\.\s+"#, with: "")
        return strippedOrdered.trimmingCharacters(in: .whitespaces)
    }

    private func replaceRegex(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private func unwrapCodeFence(from text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
        }
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func deleteBlock(_ block: MarkdownBlock) {
        var lines = MarkdownAnalysis.lines(in: document.text)
        let startIndex = block.lineStart - 1
        let endIndex = block.lineEnd - 1
        guard startIndex >= 0, endIndex < lines.count, startIndex <= endIndex else { return }

        lines.removeSubrange(startIndex...endIndex)

        if startIndex > 0, startIndex < lines.count {
            let previousIsBlank = lines[startIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentIsBlank = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if previousIsBlank && currentIsBlank {
                lines.remove(at: startIndex)
            }
        }

        document.text = lines.joined(separator: "\n")
        let newLine = max(1, min(startIndex + 1, max(1, lines.count)))
        requestedLine = newLine
        revealedLine = newLine
    }

    private func duplicateBlock(_ block: MarkdownBlock) {
        var lines = MarkdownAnalysis.lines(in: document.text)
        let range = expandedBlockRange(for: block, in: lines)
        let blockLines = Array(lines[range])
        let insertionIndex = range.upperBound + 1
        lines.insert(contentsOf: blockLines, at: insertionIndex)
        document.text = lines.joined(separator: "\n")
        let newLine = insertionIndex + 1
        requestedLine = newLine
        revealedLine = newLine
    }

    private func moveBlock(_ block: MarkdownBlock, direction: BlockMoveDirection) {
        let allBlocks = blocks
        guard let index = allBlocks.firstIndex(of: block) else { return }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard allBlocks.indices.contains(targetIndex) else { return }

        var lines = MarkdownAnalysis.lines(in: document.text)
        let blockRange = expandedBlockRange(for: block, in: lines)
        let targetRange = expandedBlockRange(for: allBlocks[targetIndex], in: lines)
        let blockLines = Array(lines[blockRange])
        let targetLines = Array(lines[targetRange])

        if direction == .up {
            lines.removeSubrange(blockRange)
            lines.removeSubrange(targetRange)
            lines.insert(contentsOf: blockLines, at: targetRange.lowerBound)
            lines.insert(contentsOf: targetLines, at: targetRange.lowerBound + blockLines.count)
            let newLine = targetRange.lowerBound + 1
            document.text = lines.joined(separator: "\n")
            requestedLine = newLine
            revealedLine = newLine
        } else {
            lines.removeSubrange(targetRange)
            lines.removeSubrange(blockRange)
            lines.insert(contentsOf: targetLines, at: blockRange.lowerBound)
            lines.insert(contentsOf: blockLines, at: blockRange.lowerBound + targetLines.count)
            let newLine = blockRange.lowerBound + targetLines.count + 1
            document.text = lines.joined(separator: "\n")
            requestedLine = newLine
            revealedLine = newLine
        }
    }

    private func expandedBlockRange(for block: MarkdownBlock, in lines: [String]) -> ClosedRange<Int> {
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

    private func previewHeadingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 28, weight: .bold)
        case 2:
            return .system(size: 24, weight: .bold)
        case 3:
            return .system(size: 20, weight: .semibold)
        case 4:
            return .system(size: 18, weight: .semibold)
        default:
            return .headline
        }
    }

    private func taskItems(in block: MarkdownBlock) -> [PreviewTaskItem] {
        block.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                guard let parts = taskMatch(in: String(line)) else { return nil }
                return PreviewTaskItem(
                    lineNumber: block.lineStart + index,
                    text: parts.text,
                    isCompleted: parts.isCompleted
                )
            }
    }

    private func toggleTaskItem(at lineNumber: Int) {
        var lines = MarkdownAnalysis.lines(in: document.text)
        let index = lineNumber - 1
        guard lines.indices.contains(index), let parts = taskMatch(in: lines[index]) else { return }

        lines[index] = parts.prefix + (parts.isCompleted ? " " : "x") + parts.suffix
        document.text = lines.joined(separator: "\n")
        requestedLine = lineNumber
        revealedLine = lineNumber
    }

    private func taskMatch(in line: String) -> (prefix: String, isCompleted: Bool, suffix: String, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*)$"#) else {
            return nil
        }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else { return nil }

        return (
            prefix: nsLine.substring(with: match.range(at: 1)),
            isCompleted: nsLine.substring(with: match.range(at: 2)).lowercased() == "x",
            suffix: nsLine.substring(with: match.range(at: 3)) + nsLine.substring(with: match.range(at: 4)),
            text: nsLine.substring(with: match.range(at: 4))
        )
    }

    private func collapseAllHeadings() {
        foldedHeadingLines = Set(headingSections.filter(\.hasContent).map(\.heading.lineNumber))
    }

    private func expandAllHeadings() {
        foldedHeadingLines.removeAll()
    }

    private func isFirstBlock(_ block: MarkdownBlock) -> Bool {
        blocks.first == block
    }

    private func isLastBlock(_ block: MarkdownBlock) -> Bool {
        blocks.last == block
    }

    private func isInlineEditable(_ block: MarkdownBlock) -> Bool {
        switch block.kind {
        case .table, .image:
            return false
        default:
            return true
        }
    }

    private func isBlockCurrent(_ block: MarkdownBlock) -> Bool {
        currentBlock?.id == block.id
    }

    private func isBlockRevealed(_ block: MarkdownBlock) -> Bool {
        guard let revealedLine else { return false }
        return (block.lineStart...block.lineEnd).contains(revealedLine)
    }

    private func isSearchHit(_ block: MarkdownBlock) -> Bool {
        guard let query = searchText.nonEmpty else { return false }
        return block.text.localizedCaseInsensitiveContains(query)
    }

    private var currentSearchLine: Int? {
        guard let match = currentSearchMatch else { return nil }
        let prefix = document.text[..<match.range.lowerBound]
        return max(1, prefix.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private func moveToSearchMatch(step: Int) {
        guard !searchMatches.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + step + searchMatches.count) % searchMatches.count
        if let line = currentSearchLine {
            requestedLine = line
            revealedLine = line
        }
    }

    private func replaceCurrentSearchMatch() {
        guard let match = currentSearchMatch else { return }
        document.text.replaceSubrange(match.range, with: replaceText)
    }

    private func replaceAllSearchMatches() {
        guard let query = searchText.nonEmpty else { return }
        document.text = document.text.replacingOccurrences(of: query, with: replaceText, options: .caseInsensitive)
    }

    @ViewBuilder
    private func blockContextMenu(for block: MarkdownBlock, includeNavigation: Bool = true) -> some View {
        if includeNavigation {
            Button("定位到内容块") {
                requestedLine = block.lineStart
                revealedLine = block.lineStart
            }
        }

        Button("复制块") {
            copyToPasteboard(block.text)
        }

        Button("复制块到下方") {
            duplicateBlock(block)
        }

        Divider()

        Menu("转换为") {
            Button("标题 H1") {
                convertBlockToHeading(block, level: 1)
            }
            Button("标题 H2") {
                convertBlockToHeading(block, level: 2)
            }
            Button("标题 H3") {
                convertBlockToHeading(block, level: 3)
            }

            Divider()

            Button("引用") {
                convertBlock(block, to: .quote)
            }
            Button("无序列表") {
                convertBlock(block, to: .unorderedList)
            }
            Button("有序列表") {
                convertBlock(block, to: .orderedList)
            }
            Button("任务列表") {
                convertBlock(block, to: .taskList)
            }
            Button("代码块") {
                convertBlock(block, to: .codeFence)
            }
            Button("普通段落") {
                convertBlock(block, to: .paragraph)
            }
        }

        Divider()

        Button("上移块") {
            moveBlock(block, direction: .up)
        }
        .disabled(isFirstBlock(block))

        Button("下移块") {
            moveBlock(block, direction: .down)
        }
        .disabled(isLastBlock(block))

        Divider()

        Button("删除块", role: .destructive) {
            deleteBlock(block)
        }
    }

    private func blockDisplayName(for kind: MarkdownBlockKind) -> String {
        switch kind {
        case .heading:
            return "标题块"
        case .paragraph:
            return "段落块"
        case .unorderedList:
            return "无序列表"
        case .orderedList:
            return "有序列表"
        case .taskList:
            return "任务列表"
        case .quote:
            return "引用块"
        case .codeFence:
            return "代码块"
        case .table:
            return "表格"
        case .image:
            return "图片"
        case .thematicBreak:
            return "分隔线"
        }
    }

    private func blockSystemImage(for kind: MarkdownBlockKind) -> String {
        switch kind {
        case .heading:
            return "number.square"
        case .paragraph:
            return "paragraph"
        case .unorderedList, .orderedList, .taskList:
            return "list.bullet"
        case .quote:
            return "text.bubble"
        case .codeFence:
            return "chevron.left.forwardslash.chevron.right"
        case .table:
            return "tablecells"
        case .image:
            return "photo"
        case .thematicBreak:
            return "minus"
        }
    }

    private func toggleFold(for lineNumber: Int) {
        if foldedHeadingLines.contains(lineNumber) {
            foldedHeadingLines.remove(lineNumber)
        } else {
            foldedHeadingLines.insert(lineNumber)
        }
    }

    private func toggleCurrentHeadingFold() {
        guard let currentHeadingSection, currentHeadingSection.hasContent else { return }
        toggleFold(for: currentHeadingSection.heading.lineNumber)
    }

    private func jumpToHeading(_ heading: MarkdownHeading?) {
        guard let heading else { return }
        requestedLine = heading.lineNumber
        revealedLine = heading.lineNumber
    }

    private func postEditorCommand(_ command: MarkdownEditorCommand, payload: [String: String] = [:]) {
        cancelBlockEditing()
        if payload.isEmpty {
            NotificationCenter.default.post(name: .marklyEditorCommand, object: command)
        } else {
            NotificationCenter.default.post(
                name: .marklyEditorCommand,
                object: MarkdownEditorCommandRequest(command: command, payload: payload)
            )
        }
    }

    private var viewModeToolbarMenu: some View {
        Menu {
            Button {
                viewMode = .document
            } label: {
                Label(EditorViewMode.document.localizedName, systemImage: EditorViewMode.document.systemImage)
            }
            .keyboardShortcut("1", modifiers: [.command, .control])
            .disabled(viewMode == .document)

            Button {
                viewMode = .source
            } label: {
                Label(EditorViewMode.source.localizedName, systemImage: EditorViewMode.source.systemImage)
            }
            .keyboardShortcut("2", modifiers: [.command, .control])
            .disabled(viewMode == .source)
        } label: {
            Label(viewMode.localizedName, systemImage: viewMode.systemImage)
        }
        .help("视图模式")
    }

    private var editModeToolbarMenu: some View {
        Menu {
            Button {
                editMode = .normal
            } label: {
                Label(EditorEditMode.normal.localizedName, systemImage: EditorEditMode.normal.systemImage)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(editMode == .normal)

            Button {
                editMode = .focus
            } label: {
                Label(EditorEditMode.focus.localizedName, systemImage: EditorEditMode.focus.systemImage)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(editMode == .focus)

            Button {
                editMode = .typewriter
            } label: {
                Label(EditorEditMode.typewriter.localizedName, systemImage: EditorEditMode.typewriter.systemImage)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(editMode == .typewriter)
        } label: {
            Label(editMode.localizedName, systemImage: editMode.systemImage)
        }
        .help("编辑模式")
    }

    private var exportButton: some View {
        Button {
            showExportSheet = true
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
        .help("导出文档")
    }

    private var exportSheet: some View {
        ExportSheetView(markdown: document.text) { success, _ in
            if success {
                exportSucceeded = true
            }
            showExportSheet = false
        }
    }

    private func blockCardBackground(for block: MarkdownBlock, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(isBlockRevealed(block) ? 0.18 : (isBlockCurrent(block) ? 0.14 : 0.08)))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(isBlockRevealed(block) ? 0.36 : (isBlockCurrent(block) ? 0.28 : 0.12)), lineWidth: 1)
            }
    }
}

private struct PreferencesDraft {
    var viewMode: EditorViewMode
    var editMode: EditorEditMode
    var fontSize: Int
    var documentWidth: Double
    var autoSaveInterval: TimeInterval
    var useSystemAppearance: Bool
    var imageDisplayMode: EditorImageDisplayMode
}

private struct FindReplaceSheet: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    let matchCount: Int
    let currentMatchIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplaceCurrent: () -> Void
    let onReplaceAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("查找与替换")
                .font(.title3.weight(.semibold))

            TextField("查找内容", text: $searchText)
            TextField("替换为", text: $replaceText)

            HStack {
                Text(matchCount == 0 ? "无匹配项" : "第 \(currentMatchIndex) / \(matchCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("上一个", action: onPrevious)
                    .disabled(matchCount == 0)
                Button("下一个", action: onNext)
                    .disabled(matchCount == 0)
            }

            HStack {
                Button("替换当前", action: onReplaceCurrent)
                    .disabled(matchCount == 0)
                Button("全部替换", action: onReplaceAll)
                    .disabled(matchCount == 0)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct PreferencesSheetView: View {
    @State private var draft: PreferencesDraft
    let onSave: (PreferencesDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        initialViewMode: EditorViewMode,
        initialEditMode: EditorEditMode,
        initialFontSize: Int,
        initialDocumentWidth: Double,
        initialAutoSaveInterval: TimeInterval,
        initialUseSystemAppearance: Bool,
        initialImageDisplayMode: EditorImageDisplayMode,
        onSave: @escaping (PreferencesDraft) -> Void
    ) {
        _draft = State(initialValue: PreferencesDraft(
            viewMode: initialViewMode,
            editMode: initialEditMode,
            fontSize: initialFontSize,
            documentWidth: initialDocumentWidth,
            autoSaveInterval: initialAutoSaveInterval,
            useSystemAppearance: initialUseSystemAppearance,
            imageDisplayMode: initialImageDisplayMode
        ))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑器偏好设置")
                .font(.title3.weight(.semibold))

            Picker("默认视图", selection: $draft.viewMode) {
                ForEach(EditorViewMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }

            Picker("编辑模式", selection: $draft.editMode) {
                ForEach(EditorEditMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("字体大小 \(draft.fontSize)")
                Slider(
                    value: Binding(
                        get: { Double(draft.fontSize) },
                        set: { draft.fontSize = Int($0.rounded()) }
                    ),
                    in: 12...24,
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("文档宽度 \(Int(draft.documentWidth))")
                Slider(value: $draft.documentWidth, in: 680...1040, step: 20)
            }

            Picker("图片显示", selection: $draft.imageDisplayMode) {
                ForEach(EditorImageDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("自动保存 \(draft.autoSaveInterval == 0 ? "已禁用" : "\(Int(draft.autoSaveInterval)) 秒")")
                Slider(value: $draft.autoSaveInterval, in: 0...120, step: 10)
            }

            Toggle("跟随系统外观", isOn: $draft.useSystemAppearance)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
