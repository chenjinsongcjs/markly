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

enum BlockMoveDirection {
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

private struct QuickLinkEditingContext: Identifiable, Equatable {
    let blockLineStart: Int
    let originalMarkdown: String

    var id: String { "\(blockLineStart)::\(originalMarkdown)" }
}

private struct QuickImageEditingContext: Identifiable, Equatable {
    let lineNumber: Int

    var id: Int { lineNumber }
}

private struct CodeFenceLanguageEditingContext: Identifiable {
    let blockLineStart: Int
    let currentLanguage: String

    var id: Int { blockLineStart }
}

private struct SearchMatch: Identifiable {
    let range: Range<String.Index>
    let index: Int

    var id: Int { index }
}

private struct PreviewBlockSnapshot {
    let renderNode: MarkdownRenderNode
    let inlineNodes: [MarkdownInlineNode]?
    let attributedText: AttributedString
    let links: [PreviewLinkItem]
    let image: PreviewImageItem?
    let taskItems: [PreviewTaskItem]
    let table: MarkdownTable?
    let codeFenceLanguage: String
}

private struct EditorDocumentPreviewSnapshot {
    let text: String
    let query: String
    let currentSearchLine: Int?
    let blocksByID: [String: PreviewBlockSnapshot]

    static func analyze(
        blocks: [MarkdownBlock],
        query: String,
        currentSearchLine: Int?,
        imageURLResolver: (String) -> URL?
    ) -> EditorDocumentPreviewSnapshot {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocksByID: [String: PreviewBlockSnapshot] = Dictionary(uniqueKeysWithValues: blocks.map { block -> (String, PreviewBlockSnapshot) in
            let renderNode = MarkdownRenderModelBuilder.node(for: block)
            return (
                block.id,
                PreviewBlockSnapshot(
                    renderNode: renderNode,
                    inlineNodes: PreviewParsing.inlineNodes(from: renderNode),
                    attributedText: PreviewParsing.highlightedMarkdownAttributedString(
                        for: block,
                        query: normalizedQuery,
                        currentSearchLine: currentSearchLine
                    ),
                    links: PreviewParsing.links(in: block.text),
                    image: PreviewParsing.imageItem(from: renderNode, imageURLResolver: imageURLResolver),
                    taskItems: PreviewParsing.taskItems(in: block, from: renderNode),
                    table: PreviewParsing.table(from: renderNode),
                    codeFenceLanguage: PreviewParsing.codeFenceLanguage(from: renderNode)
                )
            )
        })

        return EditorDocumentPreviewSnapshot(
            text: blocks.map(\.text).joined(separator: "\u{1F}"),
            query: normalizedQuery,
            currentSearchLine: currentSearchLine,
            blocksByID: blocksByID
        )
    }
}

private enum PreviewParsing {
    static let imageRegex = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)

    static func markdownAttributedString(for markdown: String) -> AttributedString {
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

    nonisolated static func inlineNodes(from renderNode: MarkdownRenderNode) -> [MarkdownInlineNode]? {
        switch DocumentPreviewSupport.content(for: renderNode) {
        case .heading(let nodes), .paragraph(let nodes):
            return nodes
        default:
            return nil
        }
    }

    static func highlightedMarkdownAttributedString(
        for block: MarkdownBlock,
        query: String,
        currentSearchLine: Int?
    ) -> AttributedString {
        let base = markdownAttributedString(for: block.text)
        guard !query.isEmpty else { return base }

        let mutable = NSMutableAttributedString(base)
        let nsText = block.text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let regexPattern = NSRegularExpression.escapedPattern(for: query)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return base
        }

        let isCurrentSearchBlock = currentSearchLine.map { (block.lineStart...block.lineEnd).contains($0) } ?? false

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

    nonisolated static func codeFenceLanguage(in text: String) -> String {
        let language = rawCodeFenceLanguage(in: text)
        return language.isEmpty ? "代码块" : language.uppercased()
    }

    nonisolated static func codeFenceLanguage(from renderNode: MarkdownRenderNode) -> String {
        let language = rawCodeFenceLanguage(from: renderNode)
        return language.isEmpty ? "代码块" : language.uppercased()
    }

    nonisolated static func rawCodeFenceLanguage(in text: String) -> String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    nonisolated static func rawCodeFenceLanguage(from renderNode: MarkdownRenderNode) -> String {
        guard case .codeBlock(let language, _) = renderNode else { return "" }
        return language
    }

    nonisolated static func codeFenceBody(from renderNode: MarkdownRenderNode, fallback text: String) -> String {
        guard case .codeBlock(_, let code) = renderNode else { return text }
        return code
    }

    nonisolated static func links(in text: String) -> [PreviewLinkItem] {
        MarkdownInlineParser.parse(text).compactMap { node in
            guard case let .link(title, rawURL, markdown) = node,
                  let destination = URL(string: rawURL) else {
                return nil
            }

            return PreviewLinkItem(
                title: title,
                destination: destination,
                markdown: markdown
            )
        }
    }

    nonisolated static func imageItem(from renderNode: MarkdownRenderNode, imageURLResolver: (String) -> URL?) -> PreviewImageItem? {
        guard case .image(let alt, let source) = renderNode else { return nil }
        return PreviewImageItem(
            alt: alt,
            source: source,
            url: imageURLResolver(source)
        )
    }

    nonisolated static func taskItems(in block: MarkdownBlock, from renderNode: MarkdownRenderNode) -> [PreviewTaskItem] {
        guard case .taskList(let items) = renderNode else { return [] }
        return items.enumerated().map { index, item in
            PreviewTaskItem(
                lineNumber: block.lineStart + index,
                text: item.text,
                isCompleted: item.isCompleted
            )
        }
    }

    nonisolated static func table(from renderNode: MarkdownRenderNode) -> MarkdownTable? {
        guard case .table(let headers, let rows) = renderNode else { return nil }
        return MarkdownTable(
            headers: headers.map(\.text),
            rows: rows.map { $0.columns.map(\.text) },
            alignments: headers.map(\.alignment)
        )
    }
}

private struct EditorDocumentAnalysisSnapshot {
    let text: String
    let blocks: [MarkdownBlock]
    let headings: [MarkdownHeading]
    let headingSections: [MarkdownHeadingSection]
    let headingSectionsByLine: [Int: MarkdownHeadingSection]
    let blockCounts: [MarkdownBlockKind: Int]
    let lineCount: Int
    let wordCount: Int

    static func analyze(_ text: String) -> EditorDocumentAnalysisSnapshot {
        let blocks = MarkdownAnalysis.blocks(in: text)
        let headings = blocks.compactMap { block -> MarkdownHeading? in
            guard block.kind == .heading else { return nil }
            let trimmed = block.text.trimmingCharacters(in: .whitespaces)
            let level = trimmed.prefix { $0 == "#" }.count
            let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return MarkdownHeading(level: level, title: title, lineNumber: block.lineStart)
        }
        let totalLineCount = max(1, MarkdownAnalysis.lines(in: text).count)
        let headingSections = headings.enumerated().map { index, heading in
            let nextSiblingOrParent = headings.dropFirst(index + 1).first(where: { $0.level <= heading.level })
            let sectionEnd = (nextSiblingOrParent?.lineNumber ?? (totalLineCount + 1)) - 1

            return MarkdownHeadingSection(
                heading: heading,
                contentLineStart: heading.lineNumber + 1,
                contentLineEnd: max(heading.lineNumber, sectionEnd)
            )
        }
        let headingSectionsByLine = Dictionary(uniqueKeysWithValues: headingSections.map { ($0.heading.lineNumber, $0) })
        let blockCounts = blocks.reduce(into: [MarkdownBlockKind: Int]()) { partialResult, block in
            partialResult[block.kind, default: 0] += 1
        }

        return EditorDocumentAnalysisSnapshot(
            text: text,
            blocks: blocks,
            headings: headings,
            headingSections: headingSections,
            headingSectionsByLine: headingSectionsByLine,
            blockCounts: blockCounts,
            lineCount: totalLineCount,
            wordCount: text.split { $0.isWhitespace || $0.isNewline }.count
        )
    }
}

private enum AnalysisRefreshMode {
    case immediate
    case deferred
}

private struct EditorSearchSnapshot {
    let text: String
    let query: String
    let matches: [SearchMatch]

    static func analyze(text: String, query: String) -> EditorSearchSnapshot {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return EditorSearchSnapshot(text: text, query: query, matches: [])
        }

        var matches: [SearchMatch] = []
        var searchStart = text.startIndex
        var index = 0
        let loweredContent = text.lowercased()
        let loweredQuery = normalizedQuery.lowercased()

        while searchStart < text.endIndex,
              let range = loweredContent.range(of: loweredQuery, range: searchStart..<loweredContent.endIndex) {
            matches.append(SearchMatch(range: range, index: index))
            searchStart = range.upperBound
            index += 1
        }

        return EditorSearchSnapshot(text: text, query: query, matches: matches)
    }
}

private enum BlockEditorAction {
    case commit
    case continueFromCurrentLine(text: String, range: NSRange)
    case deleteIfEmpty
    case mergeWithPrevious
    case indentSelection(range: NSRange)
    case outdentSelection(range: NSRange)
}

struct EditorRootView: View {
    private static let untitledDraftKey = "editor.untitledDraft"
    private static let untitledDraftTimestampKey = "editor.untitledDraft.timestamp"

    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var quickLinkEditingContext: QuickLinkEditingContext?
    @State private var quickImageEditingContext: QuickImageEditingContext?
    @State private var codeFenceLanguageEditingContext: CodeFenceLanguageEditingContext?
    @State private var codeFenceLanguageDraft = ""
    @State private var showExportSheet = false
    @State private var exportSucceeded = false
    @State private var showSearchSheet = false
    @State private var showPreferencesSheet = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var currentSearchIndex = 0
    @State private var activeEditingBlockID: String?
    @State private var editingBlockText = ""
    @State private var blockEditorSelection = NSRange(location: 0, length: 0)
    @State private var analysisSnapshot = EditorDocumentAnalysisSnapshot.analyze(MarkdownDocument().text)
    @State private var pendingAnalysisRefreshTask: Task<Void, Never>?
    @State private var searchSnapshot = EditorSearchSnapshot.analyze(text: MarkdownDocument().text, query: "")
    @State private var previewSnapshot = EditorDocumentPreviewSnapshot(
        text: "",
        query: "",
        currentSearchLine: nil,
        blocksByID: [:]
    )
    @State private var tableEditingContext: TableEditingContext?
    @StateObject private var autoSaveManager = AutoSaveManager.shared
    @State private var lastSavedText = ""
    @State private var initialDocumentText = ""
    @State private var didRegisterAutoSave = false
    @State private var isSavingDocument = false
    @State private var pendingUntitledDraftRecovery: String?
    @State private var lastUntitledDraftSaveTime: Date?
    @State private var didApplyUITestConfiguration = false
    @FocusState private var blockEditorFocused: Bool

    private let preferences = EditorPreferences.shared
    private let analysisRefreshDelayNanoseconds: UInt64 = 80_000_000

    private var uiTestConfiguration: UITestLaunchConfiguration? {
        UITestLaunchConfiguration.current
    }

    private var untitledDraftStorageValue: String? {
        UserDefaults.standard.string(forKey: Self.untitledDraftKey)
    }

    private var untitledDraftTimestamp: Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.untitledDraftTimestampKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private var isDirty: Bool {
        document.text != lastSavedText
    }

    private var autoSaveStatusText: String? {
        if fileURL == nil {
            if let lastUntitledDraftSaveTime {
                let secondsAgo = Int(Date().timeIntervalSince(lastUntitledDraftSaveTime))
                return secondsAgo < 60 ? "草稿已暂存" : "\(max(1, secondsAgo / 60)) 分钟前暂存"
            }
            return nil
        }

        return autoSaveManager.autoSaveStatus
    }

    private var blocks: [MarkdownBlock] {
        analysisSnapshot.blocks
    }

    private var headings: [MarkdownHeading] {
        analysisSnapshot.headings
    }

    private var headingSections: [MarkdownHeadingSection] {
        analysisSnapshot.headingSections
    }

    private var headingSectionsByLine: [Int: MarkdownHeadingSection] {
        analysisSnapshot.headingSectionsByLine
    }

    private var blockCounts: [MarkdownBlockKind: Int] {
        analysisSnapshot.blockCounts
    }

    private var visiblePreviewBlocks: [MarkdownBlock] {
        DocumentOutlineBehavior.visibleBlocks(
            from: blocks,
            headingSections: headingSections,
            foldedHeadingLines: foldedHeadingLines
        )
    }

    private var currentBlock: MarkdownBlock? {
        if let activeEditingBlockID {
            return blocks.first(where: { $0.id == activeEditingBlockID })
        }

        return blocks.first { ($0.lineStart...$0.lineEnd).contains(selectionState.line) }
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
        return headingSectionsByLine[currentHeadingLine]
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
        DocumentOutlineBehavior.foldedEditorRanges(
            headingSections: headingSections,
            foldedHeadingLines: foldedHeadingLines
        )
    }

    private var searchMatches: [SearchMatch] {
        searchSnapshot.matches
    }

    private var currentSearchMatch: SearchMatch? {
        guard !searchMatches.isEmpty else { return nil }
        let safeIndex = min(max(0, currentSearchIndex), searchMatches.count - 1)
        return searchMatches[safeIndex]
    }

    private var lineCount: Int {
        analysisSnapshot.lineCount
    }

    private var previewBlocksByID: [String: PreviewBlockSnapshot] {
        previewSnapshot.blocksByID
    }

    private var wordCount: Int {
        analysisSnapshot.wordCount
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
        .sheet(item: $codeFenceLanguageEditingContext) { _ in
            codeFenceLanguageSheet
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
            applyUITestConfigurationIfNeeded()
            scheduleAnalysisSnapshotRefresh(for: document.text, mode: .immediate)
            refreshSearchSnapshot(for: document.text, query: searchText)
            refreshPreviewSnapshot()
            viewMode = preferences.viewMode
            editMode = preferences.editMode
            applyUITestConfigurationIfNeeded()
            lastSavedText = document.text
            initialDocumentText = document.text
            configureAutoSaveIfNeeded()
            restoreUntitledDraftIfNeeded()
            refreshDocumentEditedState()
            syncSearchLocation()
        }
        .onDisappear {
            pendingAnalysisRefreshTask?.cancel()
            saveDocumentIfNeeded(forcePanelForUntitled: false)
            persistUntitledDraftIfNeeded()
            unregisterAutoSave()
        }
        .onChange(of: viewMode) { _, newValue in
            preferences.viewMode = newValue
            if newValue == .document {
                scheduleAnalysisSnapshotRefresh(for: document.text, mode: .immediate)
            }
            syncSearchLocation()
        }
        .onChange(of: editMode) { _, newValue in
            preferences.editMode = newValue
        }
        .onChange(of: document.text) { oldValue, newValue in
            scheduleAnalysisSnapshotRefresh(for: newValue, mode: analysisRefreshMode(for: oldValue, newValue))
            refreshSearchSnapshot(for: newValue, query: searchText)
            refreshPreviewSnapshot()
            if currentSearchIndex >= searchMatches.count {
                currentSearchIndex = max(0, searchMatches.count - 1)
            }
            handleDocumentTextChange(from: oldValue, to: newValue)
            syncSearchLocation()
        }
        .onChange(of: searchText) { _, _ in
            refreshSearchSnapshot(for: document.text, query: searchText)
            refreshPreviewSnapshot()
            currentSearchIndex = 0
            syncSearchLocation()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .inactive || newValue == .background else { return }
            persistUntitledDraftIfNeeded()
            saveDocumentIfNeeded(forcePanelForUntitled: false)
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
                        let section = headingSectionsByLine[heading.lineNumber]
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
        .accessibilityIdentifier("editor.sidebar")
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
                .accessibilityIdentifier("editor.sourcePaneTitle")

            if let pendingUntitledDraftRecovery, fileURL == nil {
                untitledDraftRecoveryBanner(draft: pendingUntitledDraftRecovery)
                Divider()
            }

            if let currentHeadingSection {
                headingContextBar(currentHeadingSection)
                Divider()
            }

            NativeMarkdownEditor(
                text: $document.text,
                selectionState: $selectionState,
                requestedLine: $requestedLine,
                revealedLine: $revealedLine,
                documentFileURL: fileURL,
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
                currentBlock: currentBlock,
                isDirty: isDirty,
                autoSaveStatus: autoSaveStatusText
            )
        }
    }

    private var documentEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("文档")
                .accessibilityIdentifier("editor.documentPaneTitle")

            if let pendingUntitledDraftRecovery, fileURL == nil {
                untitledDraftRecoveryBanner(draft: pendingUntitledDraftRecovery)
                Divider()
            }

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
                .accessibilityIdentifier("editor.documentScrollView")
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
                currentBlock: currentBlock,
                isDirty: isDirty,
                autoSaveStatus: autoSaveStatusText
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
        .accessibilityIdentifier("editor.documentSummary")
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
                .accessibilityIdentifier("editor.block.\(block.lineStart).cancelButton")
                Button("应用") {
                    commitBlockEditing(block)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("editor.block.\(block.lineStart).applyButton")
            }

            BlockTextEditor(
                text: $editingBlockText,
                selectedRange: $blockEditorSelection,
                fontSize: CGFloat(preferences.fontSize),
                accessibilityID: "editor.block.\(block.lineStart).textView"
            ) { action in
                handleBlockEditorAction(action, for: block)
            }
                .frame(minHeight: block.kind == .codeFence ? 220 : 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($blockEditorFocused)

            HStack {
                Text("直接编辑该块对应的 Markdown。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下方插入段落") {
                    executeDocumentCommand(.insertParagraph(after: block))
                }
                Button("删除块", role: .destructive) {
                    executeDocumentCommand(.deleteBlock(block))
                    cancelBlockEditing()
                }
            }
        }
        .padding(16)
        .background(blockCardBackground(for: block, tint: .accentColor))
        .accessibilityIdentifier("editor.block.\(block.lineStart).editorCard")
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
        case .unorderedList, .orderedList:
            previewListView(block)
        case .quote:
            previewQuoteView(block)
        case .taskList:
            previewTaskListView(block)
        case .codeFence:
            previewCodeFenceView(block)
        case .table:
            previewTableView(block)
        case .image:
            if let image = previewBlocksByID[block.id]?.image {
                previewImageView(block, image: image)
            } else {
                previewTextBlockView(block)
            }
        default:
            previewTextBlockView(block)
        }
    }

    private var semanticInlinePreviewEnabled: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func previewTextBlockView(_ block: MarkdownBlock) -> some View {
        let snapshot = previewBlocksByID[block.id]
        let links = snapshot?.links ?? []

        return VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            if semanticInlinePreviewEnabled, let inlineNodes = snapshot?.inlineNodes {
                previewInlineText(inlineNodes)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isBlockCurrent(block) ? 1 : 0.96)
            } else {
                Text(snapshot?.attributedText ?? PreviewParsing.markdownAttributedString(for: block.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isBlockCurrent(block) ? 1 : 0.96)
            }

            if !links.isEmpty {
                previewLinkChips(links, in: block)
            }
        }
        .padding(14)
        .background(blockCardBackground(for: block, tint: .blue))
        .accessibilityIdentifier("editor.block.\(block.lineStart).card")
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
        let inlineNodes = previewBlocksByID[block.id]?.inlineNodes
        let headingLineNumber = block.lineStart

        return VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            HStack(spacing: 10) {
                Text(heading.map { "H\($0.level)" } ?? "H")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if semanticInlinePreviewEnabled, let inlineNodes {
                    previewInlineText(inlineNodes, font: previewHeadingFont(for: heading?.level ?? 1), isBold: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("editor.heading.\(headingLineNumber).title")
                } else {
                    Text(heading?.title ?? block.text.trimmingCharacters(in: .whitespaces))
                        .font(previewHeadingFont(for: heading?.level ?? 1))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("editor.heading.\(headingLineNumber).title")
                }

                if headingSectionsByLine[block.lineStart]?.hasContent == true {
                    Button {
                        toggleFold(for: block.lineStart)
                    } label: {
                        Image(systemName: isFolded ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor.heading.\(headingLineNumber).foldButton")
                }
            }

            HStack(spacing: 8) {
                Label("第 \(block.lineStart) 行", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let section = headingSectionsByLine[block.lineStart], section.hasContent {
                    Text("\(max(0, section.contentLineEnd - section.heading.lineNumber)) 行内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(blockCardBackground(for: block, tint: .red))
        .accessibilityIdentifier("editor.heading.\(headingLineNumber).card")
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            blockContextMenu(for: block)
        }
        .onTapGesture(count: 2) {
            beginEditingBlock(block)
        }
    }

    private func previewListView(_ block: MarkdownBlock) -> some View {
        let snapshot = previewBlocksByID[block.id]
        let links = snapshot?.links ?? []

        guard semanticInlinePreviewEnabled, let renderNode = snapshot?.renderNode else {
            return AnyView(previewTextBlockView(block))
        }

        let rows: [DocumentPreviewRow]
        switch DocumentPreviewSupport.content(for: renderNode) {
        case .list(let previewRows):
            rows = previewRows
        default:
            return AnyView(previewTextBlockView(block))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                blockHeader(for: block, allowInlineEdit: true)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.marker ?? "•")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)

                        previewInlineText(row.inlineNodes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !links.isEmpty {
                    previewLinkChips(links, in: block)
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
        )
    }

    private func previewQuoteView(_ block: MarkdownBlock) -> some View {
        let snapshot = previewBlocksByID[block.id]
        let links = snapshot?.links ?? []

        guard semanticInlinePreviewEnabled,
              let renderNode = snapshot?.renderNode else {
            return AnyView(previewTextBlockView(block))
        }

        let rows: [DocumentPreviewRow]
        switch DocumentPreviewSupport.content(for: renderNode) {
        case .quote(let previewRows):
            rows = previewRows
        default:
            return AnyView(previewTextBlockView(block))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                blockHeader(for: block, allowInlineEdit: true)

                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 4)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            previewInlineText(row.inlineNodes)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if !links.isEmpty {
                    previewLinkChips(links, in: block)
                }
            }
            .padding(14)
            .background(blockCardBackground(for: block, tint: .mint))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu {
                blockContextMenu(for: block)
            }
            .onTapGesture(count: 2) {
                beginEditingBlock(block)
            }
        )
    }

    private func previewTaskListView(_ block: MarkdownBlock) -> some View {
        let items = previewBlocksByID[block.id]?.taskItems ?? []
        let links = previewBlocksByID[block.id]?.links ?? []
        let renderNode = previewBlocksByID[block.id]?.renderNode
        let previewRows: [DocumentPreviewRow]
        if let renderNode,
           case .taskList(let rows) = DocumentPreviewSupport.content(for: renderNode) {
            previewRows = rows
        } else {
            previewRows = items.map { _ in DocumentPreviewRow(marker: nil, inlineNodes: []) }
        }

        return VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block, allowInlineEdit: true)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    executeDocumentCommand(.toggleTaskItem(lineNumber: item.lineNumber))
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
                            .padding(.top, 2)

                        if semanticInlinePreviewEnabled {
                            previewInlineText(
                                previewRows.indices.contains(index)
                                    ? previewRows[index].inlineNodes
                                    : MarkdownInlineParser.parse(item.text.isEmpty ? " " : item.text),
                                foregroundColor: item.isCompleted ? .secondaryLabelColor : .labelColor,
                                strikethrough: item.isCompleted
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.text.isEmpty ? " " : item.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .strikethrough(item.isCompleted, color: .secondary)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor.task.\(item.lineNumber).toggle")
            }

            if !links.isEmpty {
                previewLinkChips(links, in: block)
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
        let renderNode = previewBlocksByID[block.id]?.renderNode
        let language = previewBlocksByID[block.id]?.codeFenceLanguage ?? PreviewParsing.codeFenceLanguage(in: block.text)
        let codeBody = renderNode.map { PreviewParsing.codeFenceBody(from: $0, fallback: block.text) } ?? block.text

        return VStack(alignment: .leading, spacing: 12) {
            blockHeader(for: block, allowInlineEdit: true)

            HStack {
                Label(language, systemImage: "curlybraces.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("语言") {
                    beginEditingCodeFenceLanguage(
                        block,
                        currentLanguage: renderNode.map(PreviewParsing.rawCodeFenceLanguage(from:)) ?? PreviewParsing.rawCodeFenceLanguage(in: block.text)
                    )
                }
                .buttonStyle(.borderless)
                Button("复制") {
                    copyToPasteboard(block.text)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: codeBody)
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
            Button("编辑语言") {
                beginEditingCodeFenceLanguage(
                    block,
                    currentLanguage: renderNode.map(PreviewParsing.rawCodeFenceLanguage(from:)) ?? PreviewParsing.rawCodeFenceLanguage(in: block.text)
                )
            }
            Divider()
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

    private func previewInlineText(
        _ nodes: [MarkdownInlineNode],
        font: Font = .body,
        isBold: Bool = false,
        foregroundColor: NSColor? = nil,
        strikethrough: Bool = false
    ) -> Text {
        Text(
            previewInlineAttributedString(
                nodes,
                font: font,
                isBold: isBold,
                foregroundColor: foregroundColor,
                strikethrough: strikethrough
            )
        )
    }

    private func previewInlineAttributedString(
        _ nodes: [MarkdownInlineNode],
        font: Font,
        isBold: Bool,
        foregroundColor: NSColor?,
        strikethrough: Bool
    ) -> AttributedString {
        nodes.reduce(into: AttributedString()) { partial, node in
            partial.append(
                previewInlineAttributedFragment(
                    node,
                    font: font,
                    isBold: isBold,
                    foregroundColor: foregroundColor,
                    strikethrough: strikethrough
                )
            )
        }
    }

    private func previewInlineAttributedFragment(
        _ node: MarkdownInlineNode,
        font: Font,
        isBold: Bool,
        foregroundColor: NSColor?,
        strikethrough: Bool
    ) -> AttributedString {
        var textValue = ""
        var result: AttributedString

        switch node {
        case .text(let text):
            textValue = text
        case .image(let alt, _, _):
            textValue = alt.isEmpty ? "[图片]" : "[图片: \(alt)]"
        case .link(let title, _, _):
            textValue = title
        case .inlineCode(let text):
            textValue = text
        case .strong(let text):
            textValue = text
        case .emphasis(let text):
            textValue = text
        }

        result = AttributedString(textValue)

        switch node {
        case .inlineCode:
            result.font = .system(.body, design: .monospaced)
            result.foregroundColor = .systemPink
        case .link:
            result.font = font
            result.foregroundColor = .systemBlue
            result.underlineStyle = .single
        case .image:
            result.font = font
            result.foregroundColor = .secondary
        case .strong:
            result.font = font.weight(.bold)
        case .emphasis:
            result.font = font.italic()
        case .text:
            result.font = font
        }

        if isBold, case .text = node {
            result.font = font.weight(.bold)
        } else if isBold, case .emphasis = node {
            result.font = font.weight(.bold).italic()
        }

        if let foregroundColor, !matchesSpecialForeground(of: node) {
            result.foregroundColor = foregroundColor
        }

        if strikethrough {
            result.strikethroughStyle = .single
            result.strikethroughColor = .secondaryLabelColor
        }

        return result
    }

    private func matchesSpecialForeground(of node: MarkdownInlineNode) -> Bool {
        switch node {
        case .link, .image, .inlineCode:
            return true
        case .text, .strong, .emphasis:
            return false
        }
    }

    private func previewLinkChips(_ links: [PreviewLinkItem], in block: MarkdownBlock) -> some View {
        HStack(spacing: 8) {
            ForEach(links.prefix(3)) { link in
                HStack(spacing: 4) {
                    Button {
                        openURL(link.destination)
                    } label: {
                        Label(link.title, systemImage: "link")
                    }
                    .buttonStyle(.borderless)
                    .help(link.destination.absoluteString)

                    Button {
                        beginQuickEditingLink(link, in: block)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("快速编辑链接")
                    .popover(
                        isPresented: Binding(
                            get: {
                                quickLinkEditingContext == QuickLinkEditingContext(
                                    blockLineStart: block.lineStart,
                                    originalMarkdown: link.markdown
                                )
                            },
                            set: { isPresented in
                                if !isPresented,
                                   quickLinkEditingContext == QuickLinkEditingContext(
                                    blockLineStart: block.lineStart,
                                    originalMarkdown: link.markdown
                                   ) {
                                    resetLinkEditors()
                                }
                            }
                        ),
                        arrowEdge: .bottom
                    ) {
                        quickLinkEditorPopover
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                .contextMenu {
                    Button("打开链接") {
                        openURL(link.destination)
                    }
                    Button("编辑链接") {
                        beginQuickEditingLink(link, in: block)
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

    private func previewTableView(_ block: MarkdownBlock) -> some View {
        let parsedTable = previewBlocksByID[block.id]?.table

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
                Button("编辑") {
                    beginQuickEditingImage(image, at: block.lineStart)
                }
                .buttonStyle(.borderless)
                .popover(
                    isPresented: Binding(
                        get: { quickImageEditingContext == QuickImageEditingContext(lineNumber: block.lineStart) },
                        set: { isPresented in
                            if !isPresented,
                               quickImageEditingContext == QuickImageEditingContext(lineNumber: block.lineStart) {
                                resetImageEditors()
                            }
                        }
                    ),
                    arrowEdge: .bottom
                ) {
                    quickImageEditorPopover
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
                beginQuickEditingImage(image, at: block.lineStart)
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
                    if let image = previewBlocksByID[block.id]?.image {
                        beginQuickEditingImage(image, at: block.lineStart)
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
                .accessibilityIdentifier(title == "文档" ? "editor.documentPaneTitleLabel" : "editor.sourcePaneTitleLabel")
            Spacer()
            if !searchMatches.isEmpty {
                Text("搜索结果 \(min(currentSearchIndex + 1, searchMatches.count))/\(searchMatches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.searchStatusLabel")
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
            performEditorCommand(command)
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

    private var quickLinkEditorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑链接")
                .font(.headline)

            TextField("显示文本", text: $linkTitleDraft)
            TextField("URL", text: $linkURLDraft)

            HStack {
                Spacer()
                Button("取消") {
                    resetLinkEditors()
                }
                Button("应用") {
                    commitLinkChanges()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var quickImageEditorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑图片")
                .font(.headline)

            TextField("图片描述", text: $imageAltDraft)
            TextField("图片地址或本地路径", text: $imageSourceDraft)

            HStack {
                Spacer()
                Button("取消") {
                    resetImageEditors()
                }
                Button("应用") {
                    commitImageChanges()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
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
            let previousAutoSaveInterval = preferences.autoSaveInterval
            preferences.viewMode = newPreferences.viewMode
            preferences.editMode = newPreferences.editMode
            preferences.fontSize = newPreferences.fontSize
            preferences.documentContentWidth = newPreferences.documentWidth
            preferences.autoSaveInterval = newPreferences.autoSaveInterval
            preferences.useSystemAppearance = newPreferences.useSystemAppearance
            preferences.imageDisplayMode = newPreferences.imageDisplayMode
            viewMode = newPreferences.viewMode
            editMode = newPreferences.editMode

            if previousAutoSaveInterval != newPreferences.autoSaveInterval {
                autoSaveManager.restartAutoSaveTimer()
            }
        }
    }

    private var codeFenceLanguageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("代码块语言")
                .font(.title3.weight(.semibold))

            TextField("例如 swift、python、json", text: $codeFenceLanguageDraft)

            Text("留空会保留为无语言标记的代码块。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") {
                    resetCodeFenceLanguageSheet()
                }
                Button("应用") {
                    commitCodeFenceLanguageChanges()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var searchToolbarButton: some View {
        Button {
            showSearchSheet = true
        } label: {
            Label("查找替换", systemImage: "magnifyingglass")
        }
        .help("查找与替换")
        .accessibilityIdentifier("editor.searchToolbarButton")
    }

    private var preferencesToolbarButton: some View {
        Button {
            showPreferencesSheet = true
        } label: {
            Label("偏好设置", systemImage: "slider.horizontal.3")
        }
        .help("编辑器偏好设置")
        .accessibilityIdentifier("editor.preferencesToolbarButton")
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

    private func untitledDraftRecoveryBanner(draft: String) -> some View {
        HStack(spacing: 12) {
            Label("发现未命名文档草稿", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))

            Text("\(draftPreviewText(for: draft))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("恢复草稿") {
                restoreUntitledDraft(draft)
            }
            .buttonStyle(.borderedProminent)

            Button("丢弃") {
                discardUntitledDraftRecovery()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
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

    private func beginEditingBlock(_ block: MarkdownBlock) {
        guard isInlineEditable(block) else {
            if block.kind == .table {
                beginEditingTable(block)
            } else if block.kind == .image, let image = previewBlocksByID[block.id]?.image {
                beginEditingImage(image, at: block.lineStart)
            }
            return
        }

        activeEditingBlockID = block.id
        editingBlockText = block.text
        blockEditorSelection = NSRange(location: (block.text as NSString).length, length: 0)
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

    private func handleBlockEditorAction(_ action: BlockEditorAction, for block: MarkdownBlock) {
        switch action {
        case .commit:
            commitBlockEditing(block)
        case .continueFromCurrentLine(let text, let range):
            continueFromBlockEditing(block, currentLineText: text, currentLineRange: range)
        case .deleteIfEmpty:
            let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                deleteBlock(block)
                cancelBlockEditing()
            }
        case .mergeWithPrevious:
            mergeBlockWithPrevious(block)
        case .indentSelection(let range):
            indentBlockEditing(for: block, range: range, direction: .right)
        case .outdentSelection(let range):
            indentBlockEditing(for: block, range: range, direction: .left)
        }
    }

    private func continueFromBlockEditing(_ block: MarkdownBlock, currentLineText: String, currentLineRange: NSRange) {
        let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedText = editingBlockText

        if trimmed.isEmpty {
            deleteBlock(block)
            cancelBlockEditing()
            return
        }

        if BlockEditingBehavior.shouldExitStructure(for: block.kind, currentLineText: currentLineText) {
            let cleaned = removingCurrentLine(in: editedText, range: currentLineRange)
            editingBlockText = cleaned
            let cleanedTrimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedTrimmed.isEmpty {
                deleteBlock(block)
                cancelBlockEditing()
            } else {
                replaceBlock(block, with: cleaned)
                let updatedBlock = blocks.first(where: { $0.lineStart == block.lineStart }) ??
                    MarkdownAnalysis.block(containingLine: block.lineStart, in: document.text) ??
                    block
                insertBlockAfter(updatedBlock, markdown: "\n新段落", focusLineOffset: 2)
            }
            return
        }

        replaceBlock(block, with: editedText)

        let updatedBlock = blocks.first(where: { $0.lineStart == block.lineStart }) ?? MarkdownAnalysis.block(containingLine: block.lineStart, in: document.text) ?? block
        let continuation = BlockEditingBehavior.continuationMarkdown(after: updatedBlock, editedText: editedText)
        insertBlockAfter(updatedBlock, markdown: continuation, focusLineOffset: continuationFocusLineOffset(for: updatedBlock))
    }

    private func removingCurrentLine(in text: String, range: NSRange) -> String {
        let nsText = text as NSString
        let paragraphRange = nsText.paragraphRange(for: range)
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: paragraphRange, with: "")

        var result = String(mutable)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .newlines)
    }

    private func cancelBlockEditing() {
        activeEditingBlockID = nil
        editingBlockText = ""
        blockEditorSelection = NSRange(location: 0, length: 0)
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

    private func beginQuickEditingLink(_ link: PreviewLinkItem, in block: MarkdownBlock) {
        linkTitleDraft = link.title
        linkURLDraft = link.destination.absoluteString
        linkEditingContext = LinkEditingContext(blockLineStart: block.lineStart, originalMarkdown: link.markdown)
        quickLinkEditingContext = QuickLinkEditingContext(
            blockLineStart: block.lineStart,
            originalMarkdown: link.markdown
        )
    }

    private func beginEditingImage(_ image: PreviewImageItem, at lineNumber: Int) {
        imageAltDraft = image.alt
        imageSourceDraft = image.source
        imageEditingContext = ImageEditingContext(lineNumber: lineNumber)
        activeInsertSheet = .image
    }

    private func beginQuickEditingImage(_ image: PreviewImageItem, at lineNumber: Int) {
        imageAltDraft = image.alt
        imageSourceDraft = image.source
        imageEditingContext = ImageEditingContext(lineNumber: lineNumber)
        quickImageEditingContext = QuickImageEditingContext(lineNumber: lineNumber)
    }

    private func beginEditingCodeFenceLanguage(_ block: MarkdownBlock, currentLanguage: String) {
        codeFenceLanguageDraft = currentLanguage
        codeFenceLanguageEditingContext = CodeFenceLanguageEditingContext(
            blockLineStart: block.lineStart,
            currentLanguage: currentLanguage
        )
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
        let normalizedSource = normalizedImageSourceDraft() ?? "/path/to/image.png"
        let newMarkdown = "![\(imageAltDraft.nonEmpty ?? "图片描述")](\(normalizedSource))"

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

    private func normalizedImageSourceDraft() -> String? {
        guard let source = imageSourceDraft.nonEmpty else { return nil }

        if source.hasPrefix("file://"), let url = URL(string: source) {
            return MarkdownAssetPathing.markdownPath(for: url, relativeTo: fileURL)
        }

        if source.hasPrefix("/") {
            return MarkdownAssetPathing.markdownPath(for: URL(fileURLWithPath: source), relativeTo: fileURL)
        }

        return source
    }

    private func commitCodeFenceLanguageChanges() {
        guard let context = codeFenceLanguageEditingContext,
              let block = MarkdownAnalysis.block(containingLine: context.blockLineStart, in: document.text)
        else {
            resetCodeFenceLanguageSheet()
            return
        }

        applyMutation(
            EditorDocumentController.updateCodeFenceLanguage(
                in: document.text,
                block: block,
                language: codeFenceLanguageDraft
            )
        )
        resetCodeFenceLanguageSheet()
    }

    private func resetLinkSheet() {
        activeInsertSheet = nil
        resetLinkEditors()
    }

    private func resetImageSheet() {
        activeInsertSheet = nil
        resetImageEditors()
    }

    private func resetLinkEditors() {
        quickLinkEditingContext = nil
        linkEditingContext = nil
        linkTitleDraft = ""
        linkURLDraft = "https://"
    }

    private func resetImageEditors() {
        quickImageEditingContext = nil
        imageEditingContext = nil
        imageAltDraft = ""
        imageSourceDraft = ""
    }

    private func resetCodeFenceLanguageSheet() {
        codeFenceLanguageEditingContext = nil
        codeFenceLanguageDraft = ""
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
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
        resolvedImageURL(from: source)
    }

    private func resolvedImageURL(from source: String) -> URL? {
        MarkdownAssetPathing.resolvedAssetURL(for: source, relativeTo: fileURL)
    }

    private func replaceLine(_ lineNumber: Int, with replacement: String) {
        applyMutation(
            EditorDocumentController.replaceLine(
                in: document.text,
                lineNumber: lineNumber,
                replacement: replacement
            )
        )
    }

    private func configureAutoSaveIfNeeded() {
        guard !didRegisterAutoSave else { return }
        didRegisterAutoSave = true

        if let fileURL {
            autoSaveManager.registerFile(url: fileURL) { _ in
                saveDocumentIfNeeded(forcePanelForUntitled: false)
            }
        }
    }

    private func unregisterAutoSave() {
        guard didRegisterAutoSave else { return }
        didRegisterAutoSave = false

        if let fileURL {
            autoSaveManager.unregisterFile(url: fileURL)
        }
    }

    private func handleDocumentTextChange(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else { return }

        markDocumentAsChanged()
        refreshDocumentEditedState()

        if let fileURL {
            autoSaveManager.notifyPendingChange(for: fileURL, content: newValue)
        } else {
            persistUntitledDraftIfNeeded()
        }
    }

    private func markDocumentAsChanged() {
        resolvedNSDocument()?.updateChangeCount(.changeDone)
    }

    private func refreshDocumentEditedState() {
        NSApp.mainWindow?.isDocumentEdited = isDirty
        NSApp.keyWindow?.isDocumentEdited = isDirty
    }

    private func resolvedNSDocument() -> NSDocument? {
        if let fileURL {
            return NSDocumentController.shared.documents.first(where: { $0.fileURL == fileURL }) ?? NSDocumentController.shared.currentDocument
        }

        return NSDocumentController.shared.currentDocument
    }

    private func saveDocumentIfNeeded(forcePanelForUntitled: Bool) {
        guard !isSavingDocument else { return }
        guard isDirty || forcePanelForUntitled else { return }
        guard let appDocument = resolvedNSDocument() else { return }

        let snapshot = document.text
        isSavingDocument = true

        let completion: (Error?) -> Void = { error in
            Task { @MainActor in
                isSavingDocument = false
                guard error == nil else { return }

                lastSavedText = snapshot
                refreshDocumentEditedState()

                if let fileURL {
                    if document.text == snapshot {
                        autoSaveManager.clearPendingChange(for: fileURL)
                    } else {
                        autoSaveManager.notifyPendingChange(for: fileURL, content: document.text)
                    }
                }
            }
        }

        if fileURL == nil, forcePanelForUntitled {
            appDocument.save(nil)
            completion(nil)
            return
        }

        appDocument.autosave(withImplicitCancellability: true) { error in
            completion(error)
        }
    }

    private func restoreUntitledDraftIfNeeded() {
        guard uiTestConfiguration == nil else {
            pendingUntitledDraftRecovery = nil
            clearUntitledDraftStorage()
            return
        }

        guard fileURL == nil else {
            clearUntitledDraftStorage()
            return
        }

        lastUntitledDraftSaveTime = untitledDraftTimestamp

        guard let draft = untitledDraftStorageValue?.nonEmpty else { return }
        guard draft != document.text else {
            pendingUntitledDraftRecovery = nil
            return
        }
        guard document.text == initialDocumentText else { return }

        pendingUntitledDraftRecovery = draft
    }

    private func restoreUntitledDraft(_ draft: String) {
        pendingUntitledDraftRecovery = nil
        document.text = draft
        scheduleAnalysisSnapshotRefresh(for: draft, mode: .immediate)
        lastUntitledDraftSaveTime = untitledDraftTimestamp ?? Date()
    }

    private func discardUntitledDraftRecovery() {
        pendingUntitledDraftRecovery = nil
        clearUntitledDraftStorage()
    }

    private func persistUntitledDraftIfNeeded() {
        guard uiTestConfiguration == nil else { return }
        guard fileURL == nil else { return }

        if shouldPersistUntitledDraft(document.text) {
            UserDefaults.standard.set(document.text, forKey: Self.untitledDraftKey)
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.untitledDraftTimestampKey)
            lastUntitledDraftSaveTime = now
        } else {
            clearUntitledDraftStorage()
        }
    }

    private func shouldPersistUntitledDraft(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return text != initialDocumentText
    }

    private func clearUntitledDraftStorage() {
        UserDefaults.standard.removeObject(forKey: Self.untitledDraftKey)
        UserDefaults.standard.removeObject(forKey: Self.untitledDraftTimestampKey)
        lastUntitledDraftSaveTime = nil
    }

    private func applyUITestConfigurationIfNeeded() {
        guard !didApplyUITestConfiguration, let uiTestConfiguration else { return }
        didApplyUITestConfiguration = true

        if let initialViewMode = uiTestConfiguration.initialViewMode {
            viewMode = initialViewMode
        }

        if let initialText = uiTestConfiguration.initialText {
            document.text = initialText
            lastSavedText = initialText
            initialDocumentText = initialText
        }
    }

    private func draftPreviewText(for text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "继续上次未保存的内容"
    }

    private func replaceFirstOccurrenceInBlock(startingAt lineNumber: Int, target: String, replacement: String) {
        guard let block = blocks.first(where: { $0.lineStart == lineNumber }) else { return }
        guard let range = block.text.range(of: target) else { return }
        let updatedBlockText = block.text.replacingCharacters(in: range, with: replacement)
        replaceBlock(block, with: updatedBlockText)
    }

    private func replaceBlock(_ block: MarkdownBlock, with replacement: String) {
        applyMutation(
            EditorDocumentController.replaceBlock(
                in: document.text,
                block: block,
                replacement: replacement
            )
        )
    }

    private func insertParagraph(after block: MarkdownBlock) {
        insertBlockAfter(block, markdown: "\n新段落", focusLineOffset: 2)
    }

    private func executeDocumentCommand(_ command: EditorDocumentCommand) {
        switch command {
        case .insertParagraph(let block):
            insertParagraph(after: block)
        case .toggleTaskItem(let lineNumber):
            toggleTaskItem(at: lineNumber)
        case .convertBlockToHeading(let block, let level):
            convertBlockToHeading(block, level: level)
        case .convertBlock(let block, let kind):
            convertBlock(block, to: kind)
        case .duplicateBlock(let block):
            duplicateBlock(block)
        case .moveBlock(let block, let direction):
            moveBlock(block, direction: direction)
        case .deleteBlock(let block):
            deleteBlock(block)
        }
    }

    private func insertBlockAfter(_ block: MarkdownBlock, markdown: String, focusLineOffset: Int) {
        let insertionBlock = blocks.first(where: { $0.id == block.id }) ?? block
        let mutation = EditorDocumentController.insertBlock(
            in: document.text,
            after: insertionBlock,
            markdown: markdown,
            focusLineOffset: focusLineOffset
        )
        applyMutation(mutation)
        let line = mutation.focusLine
        if let newBlock = MarkdownAnalysis.block(containingLine: line, in: document.text), isInlineEditable(newBlock) {
            activeEditingBlockID = newBlock.id
            editingBlockText = newBlock.text
        } else {
            activeEditingBlockID = nil
            editingBlockText = ""
        }
    }

    private func continuationFocusLineOffset(for block: MarkdownBlock) -> Int {
        switch block.kind {
        case .heading, .paragraph, .image, .table, .thematicBreak, .codeFence:
            return 2
        case .quote, .unorderedList, .orderedList, .taskList:
            return 2
        }
    }

    private func mergeBlockWithPrevious(_ block: MarkdownBlock) {
        let allBlocks = blocks
        guard let currentIndex = allBlocks.firstIndex(of: block), currentIndex > 0 else { return }

        let previousBlock = allBlocks[currentIndex - 1]
        guard isInlineEditable(previousBlock) else { return }

        let mergedText = mergedBlockText(previous: previousBlock, current: block)
        guard let mutation = EditorDocumentController.mergeBlocks(in: document.text, previous: previousBlock, current: block) else {
            return
        }
        applyMutation(mutation)

        if let updatedBlock = MarkdownAnalysis.block(containingLine: mutation.focusLine, in: document.text), isInlineEditable(updatedBlock) {
            activeEditingBlockID = updatedBlock.id
            editingBlockText = updatedBlock.text
            blockEditorSelection = NSRange(location: mergeSelectionOffset(in: mergedText, previousText: previousBlock.text), length: 0)
        } else {
            cancelBlockEditing()
        }
    }

    private func mergedBlockText(previous: MarkdownBlock, current: MarkdownBlock) -> String {
        let previousTrimmed = previous.text.trimmingCharacters(in: .newlines)
        let currentTrimmed = current.text.trimmingCharacters(in: .newlines)

        guard !previousTrimmed.isEmpty else { return currentTrimmed }
        guard !currentTrimmed.isEmpty else { return previousTrimmed }

        let separator = mergeSeparator(previous: previous.kind, current: current.kind)
        return previousTrimmed + separator + currentTrimmed
    }

    private func mergeSeparator(previous: MarkdownBlockKind, current: MarkdownBlockKind) -> String {
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

    private func mergeSelectionOffset(in mergedText: String, previousText: String) -> Int {
        let offset = previousText.trimmingCharacters(in: .newlines).count
        return min(offset, (mergedText as NSString).length)
    }

    private func indentBlockEditing(for block: MarkdownBlock, range: NSRange, direction: BlockIndentDirection) {
        guard BlockEditingBehavior.supportsIndentation(for: block.kind) else { return }
        let updated = BlockEditingBehavior.adjustingIndentation(in: editingBlockText, selectedRange: range, direction: direction)
        guard updated.text != editingBlockText || updated.selection != blockEditorSelection else { return }
        editingBlockText = updated.text
        blockEditorSelection = updated.selection
    }

    private func convertBlockToHeading(_ block: MarkdownBlock, level: Int) {
        applyMutation(
            EditorDocumentController.convertBlockToHeading(
                in: document.text,
                block: block,
                level: level
            )
        )
    }

    private func convertBlock(_ block: MarkdownBlock, to kind: MarkdownBlockKind) {
        applyMutation(
            EditorDocumentController.convertBlock(
                in: document.text,
                block: block,
                to: kind
            )
        )
    }

    private func deleteBlock(_ block: MarkdownBlock) {
        guard let mutation = EditorDocumentController.deleteBlock(in: document.text, block: block) else { return }
        applyMutation(mutation)
    }

    private func duplicateBlock(_ block: MarkdownBlock) {
        guard let mutation = EditorDocumentController.duplicateBlock(in: document.text, block: block) else { return }
        applyMutation(mutation)
    }

    private func moveBlock(_ block: MarkdownBlock, direction: BlockMoveDirection) {
        guard let mutation = EditorDocumentController.moveBlock(in: document.text, block: block, direction: direction) else { return }
        applyMutation(mutation)
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

    private func toggleTaskItem(at lineNumber: Int) {
        guard let mutation = EditorDocumentController.toggleTaskItem(in: document.text, lineNumber: lineNumber) else { return }
        applyMutation(mutation)
    }

    private func applyMutation(_ mutation: EditorDocumentMutation) {
        document.text = mutation.text
        requestedLine = mutation.focusLine
        revealedLine = mutation.focusLine
    }

    private func refreshAnalysisSnapshot(for text: String) {
        guard analysisSnapshot.text != text else { return }
        analysisSnapshot = EditorDocumentAnalysisSnapshot.analyze(text)
    }

    private func scheduleAnalysisSnapshotRefresh(for text: String, mode: AnalysisRefreshMode) {
        pendingAnalysisRefreshTask?.cancel()
        pendingAnalysisRefreshTask = nil

        switch mode {
        case .immediate:
            refreshAnalysisSnapshot(for: text)
        case .deferred:
            guard analysisSnapshot.text != text else { return }
            pendingAnalysisRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: analysisRefreshDelayNanoseconds)
                guard !Task.isCancelled else { return }
                refreshAnalysisSnapshot(for: document.text)
                pendingAnalysisRefreshTask = nil
            }
        }
    }

    private func analysisRefreshMode(for oldValue: String, _ newValue: String) -> AnalysisRefreshMode {
        if viewMode == .document || activeEditingBlockID != nil {
            return .immediate
        }

        let lineDelta = abs(
            MarkdownAnalysis.lines(in: newValue).count - MarkdownAnalysis.lines(in: oldValue).count
        )
        if lineDelta > 4 {
            return .immediate
        }

        return .deferred
    }

    private func refreshSearchSnapshot(for text: String, query: String) {
        guard searchSnapshot.text != text || searchSnapshot.query != query else { return }
        searchSnapshot = EditorSearchSnapshot.analyze(text: text, query: query)
    }

    private func refreshPreviewSnapshot() {
        let previewBlocks = analysisSnapshot.text == document.text ? blocks : MarkdownAnalysis.blocks(in: document.text)
        let documentFingerprint = previewBlocks.map(\.id).joined(separator: "|") + "::" + previewBlocks.map(\.text).joined(separator: "\u{1F}")
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLine = currentSearchLine

        guard
            previewSnapshot.text != documentFingerprint ||
            previewSnapshot.query != normalizedQuery ||
            previewSnapshot.currentSearchLine != currentLine
        else { return }

        previewSnapshot = EditorDocumentPreviewSnapshot.analyze(
            blocks: previewBlocks,
            query: normalizedQuery,
            currentSearchLine: currentLine,
            imageURLResolver: imageURL(from:)
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
        syncSearchLocation()
    }

    private func replaceCurrentSearchMatch() {
        guard let match = currentSearchMatch else { return }
        applyMutation(
            EditorDocumentController.replaceCurrentSearchMatch(
                in: document.text,
                matchRange: match.range,
                replacement: replaceText
            )
        )
        syncSearchLocation()
    }

    private func replaceAllSearchMatches() {
        guard let query = searchText.nonEmpty else { return }
        applyMutation(
            EditorDocumentController.replaceAllSearchMatches(
                in: document.text,
                query: query,
                replacement: replaceText
            )
        )
        syncSearchLocation()
    }

    private func syncSearchLocation() {
        guard let line = currentSearchLine else { return }
        requestedLine = line
        revealedLine = line
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
            executeDocumentCommand(.duplicateBlock(block))
        }

        Divider()

        Menu("转换为") {
            Button("标题 H1") {
                executeDocumentCommand(.convertBlockToHeading(block: block, level: 1))
            }
            Button("标题 H2") {
                executeDocumentCommand(.convertBlockToHeading(block: block, level: 2))
            }
            Button("标题 H3") {
                executeDocumentCommand(.convertBlockToHeading(block: block, level: 3))
            }

            Divider()

            Button("引用") {
                executeDocumentCommand(.convertBlock(block: block, kind: .quote))
            }
            Button("无序列表") {
                executeDocumentCommand(.convertBlock(block: block, kind: .unorderedList))
            }
            Button("有序列表") {
                executeDocumentCommand(.convertBlock(block: block, kind: .orderedList))
            }
            Button("任务列表") {
                executeDocumentCommand(.convertBlock(block: block, kind: .taskList))
            }
            Button("代码块") {
                executeDocumentCommand(.convertBlock(block: block, kind: .codeFence))
            }
            Button("普通段落") {
                executeDocumentCommand(.convertBlock(block: block, kind: .paragraph))
            }
        }

        Divider()

        Button("上移块") {
            executeDocumentCommand(.moveBlock(block, direction: .up))
        }
        .disabled(isFirstBlock(block))

        Button("下移块") {
            executeDocumentCommand(.moveBlock(block, direction: .down))
        }
        .disabled(isLastBlock(block))

        Divider()

        Button("删除块", role: .destructive) {
            executeDocumentCommand(.deleteBlock(block))
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

    private func performEditorCommand(_ command: MarkdownEditorCommand, payload: [String: String] = [:]) {
        if viewMode == .document, payload.isEmpty, handleDocumentModeCommand(command) {
            return
        }

        postEditorCommand(command, payload: payload)
    }

    private func handleDocumentModeCommand(_ command: MarkdownEditorCommand) -> Bool {
        switch command {
        case .heading:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlockToHeading(block: block, level: 1))
            }
        case .quote:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlock(block: block, kind: .quote))
            }
        case .bulletList:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlock(block: block, kind: .unorderedList))
            }
        case .orderedList:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlock(block: block, kind: .orderedList))
            }
        case .taskList:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlock(block: block, kind: .taskList))
            }
        case .codeFence:
            return performDocumentBlockCommand { block in
                executeDocumentCommand(.convertBlock(block: block, kind: .codeFence))
            }
        case .toggleTaskCompletion:
            guard let lineNumber = currentTaskLineNumber() else { return false }
            executeDocumentCommand(.toggleTaskItem(lineNumber: lineNumber))
            return true
        case .bold:
            return wrapCurrentBlockEditorSelection(prefix: "**", suffix: "**")
        case .italic:
            return wrapCurrentBlockEditorSelection(prefix: "*", suffix: "*")
        case .inlineCode:
            return wrapCurrentBlockEditorSelection(prefix: "`", suffix: "`")
        case .insertLink, .insertImage,
             .toggleViewMode, .toggleEditMode,
             .switchToNormalMode, .switchToFocusMode, .switchToTypewriterMode,
             .switchToSourceMode, .switchToWysiwygMode, .switchToSplitMode:
            return false
        }
    }

    private func performDocumentBlockCommand(_ action: (MarkdownBlock) -> Void) -> Bool {
        guard let block = activeDocumentCommandBlock else { return false }
        let wasEditing = activeEditingBlockID == block.id
        action(block)

        if wasEditing {
            refreshActiveEditingBlock(at: block.lineStart)
        }

        return true
    }

    private var activeDocumentCommandBlock: MarkdownBlock? {
        if let activeEditingBlockID, let block = blocks.first(where: { $0.id == activeEditingBlockID }) {
            return block
        }

        return currentBlock
    }

    private func refreshActiveEditingBlock(at lineNumber: Int) {
        guard let updatedBlock = MarkdownAnalysis.block(containingLine: lineNumber, in: document.text), isInlineEditable(updatedBlock) else {
            cancelBlockEditing()
            return
        }

        activeEditingBlockID = updatedBlock.id
        editingBlockText = updatedBlock.text
        requestedLine = updatedBlock.lineStart
        revealedLine = updatedBlock.lineStart
    }

    private func currentTaskLineNumber() -> Int? {
        guard let block = activeDocumentCommandBlock, block.kind == .taskList else { return nil }

        if let activeEditingBlockID, activeEditingBlockID == block.id {
            let nsText = editingBlockText as NSString
            let safeLocation = min(blockEditorSelection.location, nsText.length)
            let prefix = nsText.substring(to: safeLocation)
            let relativeLine = max(1, prefix.split(separator: "\n", omittingEmptySubsequences: false).count)
            return block.lineStart + relativeLine - 1
        }

        return block.lineStart
    }

    private func wrapCurrentBlockEditorSelection(prefix: String, suffix: String) -> Bool {
        guard activeEditingBlockID != nil else { return false }

        let nsText = editingBlockText as NSString
        let safeLocation = min(max(0, blockEditorSelection.location), nsText.length)
        let safeLength = min(max(0, blockEditorSelection.length), nsText.length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        let selectedText = nsText.substring(with: safeRange)

        let replacement: String
        let newSelection: NSRange

        if selectedText.hasPrefix(prefix),
           selectedText.hasSuffix(suffix),
           selectedText.count >= prefix.count + suffix.count {
            let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
            let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
            replacement = String(selectedText[start..<end])
            newSelection = NSRange(location: safeRange.location, length: replacement.utf16.count)
        } else {
            replacement = prefix + selectedText + suffix
            newSelection = NSRange(
                location: safeRange.location + prefix.utf16.count,
                length: safeRange.length
            )
        }

        editingBlockText = nsText.replacingCharacters(in: safeRange, with: replacement)
        blockEditorSelection = newSelection
        return true
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
        .accessibilityIdentifier("editor.viewModeToolbarMenu")
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
        .accessibilityIdentifier("editor.exportToolbarButton")
    }

    private var exportSheet: some View {
        ExportSheetView(markdown: document.text, sourceDocumentURL: fileURL) { success, _ in
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

private struct BlockTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let fontSize: CGFloat
    let accessibilityID: String
    let onAction: (BlockEditorAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, onAction: onAction)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.setAccessibilityIdentifier(accessibilityID + ".scrollView")

        let textView = BlockEditingTextView()
        textView.delegate = context.coordinator
        textView.onAction = context.coordinator.handleAction
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.backgroundColor = .textBackgroundColor
        textView.setAccessibilityIdentifier(accessibilityID)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        if textView.font?.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        if !NSEqualRanges(textView.selectedRange(), selectedRange) {
            textView.setSelectedRange(selectedRange)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selectedRange: NSRange
        let onAction: (BlockEditorAction) -> Void
        weak var textView: BlockEditingTextView?

        init(text: Binding<String>, selectedRange: Binding<NSRange>, onAction: @escaping (BlockEditorAction) -> Void) {
            _text = text
            _selectedRange = selectedRange
            self.onAction = onAction
        }

        func textDidChange(_ notification: Notification) {
            text = textView?.string ?? text
            if let textView {
                selectedRange = textView.selectedRange()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView {
                selectedRange = textView.selectedRange()
            }
        }

        func handleAction(_ action: BlockEditorAction) {
            onAction(action)
        }
    }
}

private final class BlockEditingTextView: NSTextView {
    var onAction: ((BlockEditorAction) -> Void)?

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if flags.contains(.shift) {
                super.doCommand(by: selector)
                return
            }

            if flags.contains(.command) {
                onAction?(.commit)
                return
            }

            let nsText = string as NSString
            let selectedRange = selectedRange()
            let lineRange = nsText.paragraphRange(for: selectedRange)
            let lineText = nsText.substring(with: lineRange)
            onAction?(.continueFromCurrentLine(text: lineText, range: lineRange))
            return
        }

        if selector == #selector(insertTab(_:)) {
            onAction?(.indentSelection(range: selectedRange()))
            return
        }

        if selector == #selector(insertBacktab(_:)) {
            onAction?(.outdentSelection(range: selectedRange()))
            return
        }

        if selector == #selector(deleteBackward(_:)) || selector == #selector(deleteForward(_:)) {
            let currentSelection = selectedRange()
            if selector == #selector(deleteBackward(_:)), currentSelection.length == 0, currentSelection.location == 0 {
                onAction?(.mergeWithPrevious)
                return
            }

            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onAction?(.deleteIfEmpty)
                return
            }
        }

        super.doCommand(by: selector)
    }
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
                .accessibilityIdentifier("editor.searchSheetTitle")

            TextField("查找内容", text: $searchText)
                .accessibilityIdentifier("editor.searchField")
            TextField("替换为", text: $replaceText)
                .accessibilityIdentifier("editor.replaceField")

            HStack {
                Text(matchCount == 0 ? "无匹配项" : "第 \(currentMatchIndex) / \(matchCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("上一个", action: onPrevious)
                    .disabled(matchCount == 0)
                    .accessibilityIdentifier("editor.searchPreviousButton")
                Button("下一个", action: onNext)
                    .disabled(matchCount == 0)
                    .accessibilityIdentifier("editor.searchNextButton")
            }

            HStack {
                Button("替换当前", action: onReplaceCurrent)
                    .disabled(matchCount == 0)
                    .accessibilityIdentifier("editor.replaceCurrentButton")
                Button("全部替换", action: onReplaceAll)
                    .disabled(matchCount == 0)
                    .accessibilityIdentifier("editor.replaceAllButton")
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .accessibilityIdentifier("editor.searchCloseButton")
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
