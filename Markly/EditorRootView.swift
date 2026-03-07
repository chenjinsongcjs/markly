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

private enum EditorInsertSheet: String, Identifiable {
    case link
    case image

    var id: String { rawValue }
}

private struct LinkEditingContext {
    let blockLineStart: Int
    let originalMarkdown: String
}

private struct ImageEditingContext {
    let lineNumber: Int
}

struct EditorRootView: View {
    @Binding var document: MarkdownDocument
    @State private var showsPreview = true
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
        MarkdownAnalysis.block(containingLine: selectionState.line, in: document.text)
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
            guard
                foldedHeadingLines.contains(section.heading.lineNumber),
                section.hasContent
            else { return nil }

            return section.contentLineStart...section.contentLineEnd
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            editorPane
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
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

                Button {
                    showsPreview.toggle()
                } label: {
                    Label(
                        showsPreview ? "隐藏预览" : "显示预览",
                        systemImage: showsPreview ? "sidebar.right" : "sidebar.right"
                    )
                }
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
    }

    private var sidebar: some View {
        List {
            Section("文档") {
                Label("Markdown", systemImage: "doc.text")
                Label("\(wordCount) 字", systemImage: "textformat")
                Label("\(lineCount) 行", systemImage: "list.number")
                Label("\(blocks.count) 块", systemImage: "square.stack.3d.up")
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
                blockCountRow("代码块", kind: .codeFence, systemImage: "chevron.left.forwardslash.chevron.right")
                Label("已折叠 · \(foldedHeadingLines.count)", systemImage: "arrowtriangle.right.square")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Markly")
    }

    private var editorPane: some View {
        Group {
            if showsPreview {
                HSplitView {
                    sourceEditor
                    renderedPreview
                }
            } else {
                sourceEditor
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("编辑")

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
                softFoldedLineRanges: softFoldedEditorRanges
            )
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack(spacing: 16) {
                Label("Ln \(selectionState.line)", systemImage: "list.number")
                Label("Col \(selectionState.column)", systemImage: "character")
                Label("\(selectionState.selectedLength) 已选中", systemImage: "checkmark.circle")
                if let currentBlock {
                    Label(blockStatusText(for: currentBlock), systemImage: blockSystemImage(for: currentBlock.kind))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var renderedPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("预览")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        previewSummary

                        ForEach(visiblePreviewBlocks) { block in
                            previewBlockView(block)
                                .id(block.id)
                        }
                    }
                    .padding(24)
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
            }
        }
    }

    private var previewSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文档结构")
                .font(.headline)

            HStack(spacing: 10) {
                previewChip(title: "标题", value: blockCounts[.heading, default: 0], color: .red)
                previewChip(title: "段落", value: blockCounts[.paragraph, default: 0], color: .blue)
                previewChip(title: "列表", value: listBlockCount, color: .green)
                previewChip(title: "代码块", value: blockCounts[.codeFence, default: 0], color: .indigo)
            }

            if let dominantBlockKind {
                Text("当前文档以\(blockDisplayName(for: dominantBlockKind))为主。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func paneTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
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
            NotificationCenter.default.post(name: .marklyEditorCommand, object: command)
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

    @ViewBuilder
    private func previewBlockView(_ block: MarkdownBlock) -> some View {
        if block.kind == .thematicBreak {
            Divider()
        } else if block.kind == .heading {
            previewHeadingView(block)
        } else if block.kind == .taskList {
            previewTaskListView(block)
        } else if block.kind == .codeFence {
            previewCodeFenceView(block)
        } else if let image = imageItem(in: block) {
            previewImageView(block, image: image)
        } else {
            previewTextBlockView(block)
        }
    }

    private func previewTextBlockView(_ block: MarkdownBlock) -> some View {
        let links = previewLinks(in: block.text)

        return VStack(alignment: .leading, spacing: 10) {
            Text(markdownAttributedString(for: block.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isBlockCurrent(block) ? 1 : 0.94)

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

                            Button("复制链接") {
                                copyToPasteboard(link.destination.absoluteString)
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .background(blockBackground(for: block))
        .contentShape(Rectangle())
        .onTapGesture {
            requestedLine = block.lineStart
        }
    }

    private func previewHeadingView(_ block: MarkdownBlock) -> some View {
        let heading = headings.first(where: { $0.lineNumber == block.lineStart })
        let isFolded = foldedHeadingLines.contains(block.lineStart)

        return VStack(alignment: .leading, spacing: 10) {
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
        .onTapGesture {
            requestedLine = block.lineStart
        }
    }

    private func previewTaskListView(_ block: MarkdownBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.vertical, 2)
        .background(blockBackground(for: block))
        .contentShape(Rectangle())
        .onTapGesture {
            requestedLine = block.lineStart
        }
    }

    private func previewCodeFenceView(_ block: MarkdownBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Button("定位到编辑区") {
                requestedLine = block.lineStart
            }
        }
        .onTapGesture {
            requestedLine = block.lineStart
        }
    }

    private func previewImageView(_ block: MarkdownBlock, image: PreviewImageItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                Text(image.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let nsImage = localImage(for: image.source) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let remoteURL = URL(string: image.source), ["http", "https"].contains(remoteURL.scheme?.lowercased()) {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    case .failure, .empty:
                        previewImagePlaceholder(for: image.source)
                    @unknown default:
                        previewImagePlaceholder(for: image.source)
                    }
                }
            } else {
                previewImagePlaceholder(for: image.source)
            }
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

            Button("复制图片路径") {
                copyToPasteboard(image.source)
            }

            if let fileURL = image.url, fileURL.isFileURL {
                Button("在 Finder 中显示") {
                    revealInFinder(fileURL)
                }
            }
        }
        .onTapGesture {
            requestedLine = block.lineStart
        }
    }

    private func previewImagePlaceholder(for source: String) -> some View {
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
        .frame(height: 180)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var wordCount: Int {
        document.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var lineCount: Int {
        max(1, document.text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private var listBlockCount: Int {
        blockCounts[.unorderedList, default: 0] +
        blockCounts[.orderedList, default: 0] +
        blockCounts[.taskList, default: 0]
    }

    private var dominantBlockKind: MarkdownBlockKind? {
        blockCounts.max { lhs, rhs in lhs.value < rhs.value }?.key
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
        case .thematicBreak:
            return "分隔线"
        }
    }

    private func isBlockCurrent(_ block: MarkdownBlock) -> Bool {
        currentBlock?.id == block.id
    }

    private func isBlockRevealed(_ block: MarkdownBlock) -> Bool {
        guard let revealedLine else { return false }
        return (block.lineStart...block.lineEnd).contains(revealedLine)
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

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

        return PreviewImageItem(
            alt: nsText.substring(with: match.range(at: 1)),
            source: nsText.substring(with: match.range(at: 2)),
            url: imageURL(from: nsText.substring(with: match.range(at: 2)))
        )
    }

    private func localImage(for source: String) -> NSImage? {
        if source.hasPrefix("file://"), let url = URL(string: source) {
            return NSImage(contentsOf: url)
        }

        if source.hasPrefix("/") {
            return NSImage(contentsOfFile: source)
        }

        return nil
    }

    private func imageURL(from source: String) -> URL? {
        if source.hasPrefix("file://") {
            return URL(string: source)
        }

        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }

        return URL(string: source)
    }

    private func replaceLine(_ lineNumber: Int, with replacement: String) {
        var lines = document.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let index = lineNumber - 1
        guard lines.indices.contains(index) else { return }
        lines[index] = replacement
        document.text = lines.joined(separator: "\n")
        requestedLine = lineNumber
    }

    private func replaceFirstOccurrenceInBlock(startingAt lineNumber: Int, target: String, replacement: String) {
        guard let block = blocks.first(where: { $0.lineStart == lineNumber }) else { return }
        guard let range = block.text.range(of: target) else { return }
        let updatedBlockText = block.text.replacingCharacters(in: range, with: replacement)
        replaceBlock(block, with: updatedBlockText)
    }

    private func replaceBlock(_ block: MarkdownBlock, with replacement: String) {
        var lines = document.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let startIndex = block.lineStart - 1
        let endIndex = block.lineEnd - 1
        guard startIndex >= 0, endIndex < lines.count, startIndex <= endIndex else { return }

        lines.replaceSubrange(startIndex...endIndex, with: replacement.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        document.text = lines.joined(separator: "\n")
        requestedLine = block.lineStart
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
        var lines = document.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let index = lineNumber - 1
        guard lines.indices.contains(index), let parts = taskMatch(in: lines[index]) else { return }

        lines[index] = parts.prefix + (parts.isCompleted ? " " : "x") + parts.suffix
        document.text = lines.joined(separator: "\n")
        requestedLine = lineNumber
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
        foldedHeadingLines = Set(
            headingSections
                .filter(\.hasContent)
                .map(\.heading.lineNumber)
        )
    }

    private func expandAllHeadings() {
        foldedHeadingLines.removeAll()
    }

    @ViewBuilder
    private func blockBackground(for block: MarkdownBlock) -> some View {
        if isBlockRevealed(block) {
            Color.accentColor.opacity(0.14)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if isBlockCurrent(block) {
            Color.accentColor.opacity(0.06)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Color.clear
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

    private func postEditorCommand(_ command: MarkdownEditorCommand, payload: [String: String] = [:]) {
        if payload.isEmpty {
            NotificationCenter.default.post(name: .marklyEditorCommand, object: command)
        } else {
            NotificationCenter.default.post(
                name: .marklyEditorCommand,
                object: MarkdownEditorCommandRequest(command: command, payload: payload)
            )
        }
    }

    private func blockStatusText(for block: MarkdownBlock) -> String {
        "\(blockDisplayName(for: block.kind)) · \(block.lineStart)-\(block.lineEnd) 行"
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
        case .thematicBreak:
            return "minus"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
