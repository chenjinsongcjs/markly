//
//  NativeMarkdownEditor.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import AppKit
import SwiftUI
import QuartzCore

struct EditorSelectionState: Equatable {
    var line = 1
    var column = 1
    var selectedLength = 0
}

struct NativeMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectionState: EditorSelectionState
    @Binding var requestedLine: Int?
    @Binding var revealedLine: Int?
    var highlightedLineRange: ClosedRange<Int>?
    var softFoldedLineRanges: [ClosedRange<Int>] = []
    var editMode: EditorEditMode = .normal
    var fontSize: CGFloat = 14

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectionState: $selectionState,
            requestedLine: $requestedLine,
            revealedLine: $revealedLine,
            editMode: .constant(editMode)
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = MarklyTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 16)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.dropHandler = { [weak coordinator = context.coordinator] urls, point in
            coordinator?.handleDroppedFiles(urls, at: point)
        }
        textView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scheduleHighlighting(.immediate)
        context.coordinator.applyStructureAnnotations(
            highlightedLineRange: highlightedLineRange,
            softFoldedLineRanges: softFoldedLineRanges
        )
        context.coordinator.updateSelectionState(for: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange.clamped(to: text.utf16.count))
            context.coordinator.scheduleHighlighting(.immediate)
        }

        if textView.delegate == nil {
            textView.delegate = context.coordinator
        }

        context.coordinator.editMode = editMode
        if textView.font?.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        context.coordinator.applyStructureAnnotations(
            highlightedLineRange: highlightedLineRange,
            softFoldedLineRanges: softFoldedLineRanges
        )
        context.coordinator.scrollIfNeeded()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate enum HighlightMode {
            case immediate
            case deferred
        }

        @Binding private var text: String
        @Binding private var selectionState: EditorSelectionState
        @Binding private var requestedLine: Int?
        @Binding private var revealedLine: Int?
        @Binding var editMode: EditorEditMode
        private let highlighter = MarkdownSyntaxHighlighter()
        private let highlightDebounceInterval: TimeInterval = 0.06
        private var lastHandledRequestedLine: Int?
        private var pendingHighlightWorkItem: DispatchWorkItem?
        private var observers: [NSObjectProtocol] = []
        weak var textView: NSTextView?

        init(
            text: Binding<String>,
            selectionState: Binding<EditorSelectionState>,
            requestedLine: Binding<Int?>,
            revealedLine: Binding<Int?>,
            editMode: Binding<EditorEditMode>
        ) {
            _text = text
            _selectionState = selectionState
            _requestedLine = requestedLine
            _revealedLine = revealedLine
            _editMode = editMode
            super.init()
            registerForEditorCommands()
        }

        deinit {
            pendingHighlightWorkItem?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            scheduleHighlighting(.deferred)
            updateSelectionState(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            updateSelectionState(for: textView)

            // 在打字机模式下，光标移动时自动滚动
            if editMode == .typewriter {
                centerCursorVertically(in: textView)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleInsertNewline(in: textView)
            case #selector(NSResponder.insertTab(_:)):
                return handleIndent(in: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return handleOutdent(in: textView)
            default:
                return false
            }
        }

        func updateSelectionState(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let nsText = textView.string as NSString
            let location = min(selectedRange.location, nsText.length)
            let prefix = nsText.substring(to: location)
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            let line = max(1, lines.count)
            let column = (lines.last?.count ?? prefix.count) + 1

            selectionState = EditorSelectionState(
                line: line,
                column: column,
                selectedLength: selectedRange.length
            )
        }

        func applyHighlighting() {
            guard let textStorage = textView?.textStorage else { return }
            highlighter.highlight(textStorage: textStorage)
        }

        fileprivate func scheduleHighlighting(_ mode: HighlightMode) {
            pendingHighlightWorkItem?.cancel()
            pendingHighlightWorkItem = nil

            switch mode {
            case .immediate:
                applyHighlighting()
            case .deferred:
                let workItem = DispatchWorkItem { [weak self] in
                    self?.pendingHighlightWorkItem = nil
                    self?.applyHighlighting()
                }
                pendingHighlightWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + highlightDebounceInterval, execute: workItem)
            }
        }

        func applyStructureAnnotations(
            highlightedLineRange: ClosedRange<Int>?,
            softFoldedLineRanges: [ClosedRange<Int>]
        ) {
            guard
                let textView,
                let layoutManager = textView.layoutManager
            else { return }

            let nsText = textView.string as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

            // 应用标题高亮
            if let highlightedLineRange,
               let range = characterRange(forLines: highlightedLineRange, in: nsText) {
                layoutManager.addTemporaryAttributes(
                    [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.08)],
                    forCharacterRange: range
                )
            }

            // 应用折叠淡化
            for foldedRange in softFoldedLineRanges {
                guard let range = characterRange(forLines: foldedRange, in: nsText) else { continue }
                layoutManager.addTemporaryAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.42),
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.06)
                    ],
                    forCharacterRange: range
                )
            }

            // 应用专注模式注解
            if editMode == .focus {
                applyFocusModeAnnotations(in: textView, layoutManager: layoutManager, nsText: nsText)
            }
        }

        func scrollIfNeeded() {
            guard
                let textView,
                let requestedLine,
                requestedLine != lastHandledRequestedLine
            else { return }

            if let range = rangeForLine(requestedLine, in: textView.string as NSString) {
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
                textView.scrollRangeToVisible(range)
                updateSelectionState(for: textView)
            }

            lastHandledRequestedLine = requestedLine
            DispatchQueue.main.async { [weak self] in
                self?.requestedLine = nil
            }
        }

        func handleDroppedFiles(_ urls: [URL], at point: NSPoint) {
            guard let textView else { return }

            let markdownSnippets = urls.compactMap(markdownForDroppedFile)
            guard !markdownSnippets.isEmpty else { return }

            let insertionLocation = insertionLocationForDrop(in: textView, point: point)
            let replacementRange = NSRange(location: insertionLocation, length: 0)
            let markdown = wrappedDropInsertion(
                snippets: markdownSnippets,
                in: textView.string as NSString,
                at: insertionLocation
            )

            textView.setSelectedRange(replacementRange)
            textView.insertText(markdown, replacementRange: replacementRange)
            let focusLocation = insertionLocation + dropFocusOffset(for: markdown)
            textView.setSelectedRange(NSRange(location: focusLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: focusLocation, length: 0))
            syncState(from: textView)
            revealedLine = lineNumber(for: focusLocation, in: textView.string as NSString)
        }

        private func handleInsertNewline(in textView: NSTextView) -> Bool {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = currentLineRange(in: nsText, selectedRange: selectedRange)
            let line = nsText.substring(with: lineRange)

            if let removalRange = emptyListMarkerRange(for: line, lineRange: lineRange) {
                textView.setSelectedRange(removalRange)
                textView.insertText("", replacementRange: removalRange)
                textView.insertNewline(nil)
                syncState(from: textView)
                return true
            }

            let continuation = continuationPrefix(for: line)

            textView.insertNewline(nil)

            if !continuation.isEmpty {
                textView.insertText(continuation, replacementRange: textView.selectedRange())
            }

            syncState(from: textView)
            return true
        }

        private func handleIndent(in textView: NSTextView) -> Bool {
            adjustIndent(in: textView, addIndent: true)
            return true
        }

        private func handleOutdent(in textView: NSTextView) -> Bool {
            adjustIndent(in: textView, addIndent: false)
            return true
        }

        private func adjustIndent(in textView: NSTextView, addIndent: Bool) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            let block = nsText.substring(with: paragraphRange)
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

            let transformed = lines.map { line in
                if addIndent {
                    return "    " + line
                }

                if line.hasPrefix("    ") {
                    return String(line.dropFirst(4))
                }

                if line.hasPrefix("\t") {
                    return String(line.dropFirst())
                }

                return line
            }.joined(separator: "\n")

            textView.insertText(transformed, replacementRange: paragraphRange)

            let delta = transformed.utf16.count - paragraphRange.length
            let newRange = NSRange(
                location: paragraphRange.location,
                length: max(0, selectedRange.length + delta)
            )
            textView.setSelectedRange(newRange)
            syncState(from: textView)
        }

        private func syncState(from textView: NSTextView) {
            text = textView.string
            scheduleHighlighting(.immediate)
            updateSelectionState(for: textView)
        }

        private func currentLineRange(in text: NSString, selectedRange: NSRange) -> NSRange {
            let location = min(selectedRange.location, text.length)
            return text.paragraphRange(for: NSRange(location: location, length: 0))
        }

        private func continuationPrefix(for line: String) -> String {
            let trimmedNewline = line.trimmingCharacters(in: .newlines)
            guard !trimmedNewline.isEmpty else { return "" }

            let quotePrefix = quotePrefix(in: trimmedNewline)
            let contentAfterQuote = String(trimmedNewline.dropFirst(quotePrefix.count))

            if let unordered = match(in: contentAfterQuote, pattern: #"^(\s*)([-*+])\s+(.*)$"#) {
                let indent = unordered[1]
                let marker = unordered[2]
                let content = unordered[3].trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? "" : quotePrefix + indent + marker + " "
            }

            if let ordered = match(in: contentAfterQuote, pattern: #"^(\s*)(\d+)\.\s+(.*)$"#) {
                let indent = ordered[1]
                let number = (Int(ordered[2]) ?? 0) + 1
                let content = ordered[3].trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? "" : quotePrefix + indent + "\(number). "
            }

            if let task = match(in: contentAfterQuote, pattern: #"^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$"#) {
                let indent = task[1]
                let content = task[3].trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? "" : quotePrefix + indent + "- [ ] "
            }

            if !quotePrefix.isEmpty {
                return quotePrefix
            }

            return ""
        }

        private func emptyListMarkerRange(for line: String, lineRange: NSRange) -> NSRange? {
            let trimmedLine = line.trimmingCharacters(in: .newlines)

            if let unordered = match(in: trimmedLine, pattern: #"^((?:\s*>\s*)*)(\s*[-*+]\s*)$"#) {
                let content = unordered[2]
                let location = lineRange.location + (trimmedLine as NSString).length - (content as NSString).length
                return NSRange(location: location, length: (content as NSString).length)
            }

            if let ordered = match(in: trimmedLine, pattern: #"^((?:\s*>\s*)*)(\s*\d+\.\s*)$"#) {
                let content = ordered[2]
                let location = lineRange.location + (trimmedLine as NSString).length - (content as NSString).length
                return NSRange(location: location, length: (content as NSString).length)
            }

            if let task = match(in: trimmedLine, pattern: #"^((?:\s*>\s*)*)(\s*[-*+]\s+\[[ xX]\]\s*)$"#) {
                let content = task[2]
                let location = lineRange.location + (trimmedLine as NSString).length - (content as NSString).length
                return NSRange(location: location, length: (content as NSString).length)
            }

            return nil
        }

        private func quotePrefix(in line: String) -> String {
            guard let parts = match(in: line, pattern: #"^((?:\s*>\s*)+)(.*)$"#) else {
                return ""
            }
            return parts[1]
        }

        private func match(in text: String, pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            guard let result = regex.firstMatch(in: text, range: fullRange) else { return nil }

            return (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : nsText.substring(with: range)
            }
        }

        private func rangeForLine(_ lineNumber: Int, in text: NSString) -> NSRange? {
            guard lineNumber > 0 else { return nil }

            var currentLine = 1
            var index = 0

            while index < text.length {
                let range = text.paragraphRange(for: NSRange(location: index, length: 0))
                if currentLine == lineNumber {
                    return range
                }

                currentLine += 1
                index = NSMaxRange(range)
            }

            if lineNumber == 1 && text.length == 0 {
                return NSRange(location: 0, length: 0)
            }

            return nil
        }

        private func characterRange(forLines lineRange: ClosedRange<Int>, in text: NSString) -> NSRange? {
            guard
                let startRange = rangeForLine(lineRange.lowerBound, in: text),
                let endRange = rangeForLine(lineRange.upperBound, in: text)
            else { return nil }

            let location = startRange.location
            let upperBound = NSMaxRange(endRange)
            return NSRange(location: location, length: max(0, upperBound - location))
        }

        private func insertionLocationForDrop(in textView: NSTextView, point: NSPoint) -> Int {
            guard
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return textView.selectedRange().location
            }

            let containerOrigin = textView.textContainerOrigin
            let adjustedPoint = NSPoint(
                x: point.x - containerOrigin.x,
                y: point.y - containerOrigin.y
            )

            let index = layoutManager.characterIndex(
                for: adjustedPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            return min(index, textView.string.utf16.count)
        }

        private func registerForEditorCommands() {
            let observer = NotificationCenter.default.addObserver(
                forName: .marklyEditorCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let self,
                    let textView = self.textView
                else { return }

                if let request = notification.object as? MarkdownEditorCommandRequest {
                    self.perform(command: request.command, payload: request.payload, in: textView)
                } else if let command = notification.object as? MarkdownEditorCommand {
                    self.perform(command: command, payload: [:], in: textView)
                }
            }

            observers.append(observer)
        }

        private func perform(command: MarkdownEditorCommand, payload: [String: String], in textView: NSTextView) {
            switch command {
            case .heading:
                togglePrefixOnSelectedLines(in: textView, prefix: "# ")
            case .quote:
                togglePrefixOnSelectedLines(in: textView, prefix: "> ")
            case .bulletList:
                togglePrefixOnSelectedLines(in: textView, prefix: "- ")
            case .orderedList:
                toggleOrderedList(in: textView)
            case .taskList:
                togglePrefixOnSelectedLines(in: textView, prefix: "- [ ] ")
            case .toggleTaskCompletion:
                toggleTaskCompletion(in: textView)
            case .bold:
                toggleWrappedSelection(in: textView, prefix: "**", suffix: "**")
            case .italic:
                toggleWrappedSelection(in: textView, prefix: "*", suffix: "*")
            case .inlineCode:
                toggleWrappedSelection(in: textView, prefix: "`", suffix: "`")
            case .codeFence:
                toggleCodeFence(in: textView)
            case .insertLink:
                insertLink(in: textView, payload: payload)
            case .insertImage:
                insertImage(in: textView, payload: payload)
            case .toggleViewMode, .toggleEditMode,
                 .switchToNormalMode, .switchToFocusMode, .switchToTypewriterMode,
                 .switchToSourceMode, .switchToWysiwygMode, .switchToSplitMode:
                break
            }
        }

        private func toggleWrappedSelection(in textView: NSTextView, prefix: String, suffix: String) {
            let selectedRange = textView.selectedRange()
            let nsText = textView.string as NSString
            let selectedText = nsText.substring(with: selectedRange)

            let replacement: String
            let newSelection: NSRange

            if selectedText.hasPrefix(prefix), selectedText.hasSuffix(suffix), selectedText.count >= prefix.count + suffix.count {
                let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
                let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
                replacement = String(selectedText[start..<end])
                newSelection = NSRange(location: selectedRange.location, length: replacement.utf16.count)
            } else {
                replacement = prefix + selectedText + suffix
                newSelection = NSRange(
                    location: selectedRange.location + prefix.utf16.count,
                    length: selectedRange.length
                )
            }

            textView.insertText(replacement, replacementRange: selectedRange)
            textView.setSelectedRange(newSelection)
            syncState(from: textView)
        }

        private func togglePrefixOnSelectedLines(in textView: NSTextView, prefix: String) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            let lines = nsText.substring(with: paragraphRange)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            let allPrefixed = lines.allSatisfy { line in
                line.isEmpty || line.hasPrefix(prefix)
            }

            let updated = lines.map { line in
                if line.isEmpty {
                    return line
                }

                if allPrefixed, line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count))
                }

                return prefix + line
            }.joined(separator: "\n")

            textView.insertText(updated, replacementRange: paragraphRange)
            textView.setSelectedRange(NSRange(location: paragraphRange.location, length: updated.utf16.count))
            syncState(from: textView)
        }

        private func toggleOrderedList(in textView: NSTextView) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            let lines = nsText.substring(with: paragraphRange)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            let allOrdered = lines.allSatisfy { line in
                line.isEmpty || match(in: line, pattern: #"^\d+\.\s+"#) != nil
            }

            let updated = lines.enumerated().map { index, line in
                if line.isEmpty {
                    return line
                }

                if allOrdered, let matched = match(in: line, pattern: #"^(\d+\.\s+)(.*)$"#) {
                    return matched[2]
                }

                return "\(index + 1). \(line)"
            }.joined(separator: "\n")

            textView.insertText(updated, replacementRange: paragraphRange)
            textView.setSelectedRange(NSRange(location: paragraphRange.location, length: updated.utf16.count))
            syncState(from: textView)
        }

        private func toggleTaskCompletion(in textView: NSTextView) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            let lines = nsText.substring(with: paragraphRange)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            let hasTaskLine = lines.contains { match(in: $0, pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s+.*)$"#) != nil }
            let transformed = lines.map { line in
                guard let parts = match(in: line, pattern: #"^(\s*[-*+]\s+\[)([ xX])(\]\s+.*)$"#) else {
                    return hasTaskLine ? line : "- [ ] " + line
                }

                let updatedMark = parts[2].lowercased() == "x" ? " " : "x"
                return parts[1] + updatedMark + parts[3]
            }.joined(separator: "\n")

            textView.insertText(transformed, replacementRange: paragraphRange)
            textView.setSelectedRange(NSRange(location: paragraphRange.location, length: transformed.utf16.count))
            syncState(from: textView)
        }

        private func toggleCodeFence(in textView: NSTextView) {
            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            let blockText = nsText.substring(with: paragraphRange)
            let trimmedBlock = blockText.trimmingCharacters(in: .whitespacesAndNewlines)

            let replacement: String
            let newSelection: NSRange

            if isWrappedInCodeFence(trimmedBlock) {
                replacement = unwrapCodeFence(from: blockText)
                newSelection = NSRange(location: paragraphRange.location, length: replacement.utf16.count)
            } else {
                replacement = "```\n" + blockText.trimmingCharacters(in: .newlines) + "\n```"
                let selectedLength = max(selectedRange.length, blockText.trimmingCharacters(in: .newlines).utf16.count)
                newSelection = NSRange(
                    location: paragraphRange.location + 4,
                    length: min(selectedLength, max(0, replacement.utf16.count - 8))
                )
            }

            textView.insertText(replacement, replacementRange: paragraphRange)
            textView.setSelectedRange(newSelection)
            syncState(from: textView)
        }

        private func isWrappedInCodeFence(_ text: String) -> Bool {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2 else { return false }
            return lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true &&
                   lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true
        }

        private func unwrapCodeFence(from text: String) -> String {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if !lines.isEmpty {
                lines.removeFirst()
            }
            if !lines.isEmpty {
                lines.removeLast()
            }
            return lines.joined(separator: "\n")
        }

        private func insertLink(in textView: NSTextView, payload: [String: String]) {
            let selectedRange = textView.selectedRange()
            let nsText = textView.string as NSString
            let selectedText = selectedRange.length > 0 ? nsText.substring(with: selectedRange) : ""
            let title = payload["title"]?.nonEmpty ?? selectedText.nonEmpty ?? "链接文本"
            let destination = payload["url"]?.nonEmpty ?? "https://"
            let markdown = "[\(title)](\(destination))"

            textView.insertText(markdown, replacementRange: selectedRange)
            let titleRange = NSRange(location: selectedRange.location + 1, length: title.utf16.count)
            textView.setSelectedRange(titleRange)
            syncState(from: textView)
            revealedLine = lineNumber(for: selectedRange.location, in: textView.string as NSString)
        }

        private func insertImage(in textView: NSTextView, payload: [String: String]) {
            let selectedRange = textView.selectedRange()
            let alt = payload["alt"]?.nonEmpty ?? "图片描述"
            let source = payload["source"]?.nonEmpty ?? "/path/to/image.png"
            let markdown = "![\(alt)](\(source))"

            textView.insertText(markdown, replacementRange: selectedRange)
            let altRange = NSRange(location: selectedRange.location + 2, length: alt.utf16.count)
            textView.setSelectedRange(altRange)
            syncState(from: textView)
            revealedLine = lineNumber(for: selectedRange.location, in: textView.string as NSString)
        }

        private func markdownForDroppedFile(_ url: URL) -> String? {
            let path = escapedMarkdownPath(for: url)
            let name = url.deletingPathExtension().lastPathComponent

            if isImageURL(url) {
                return "![\(name.isEmpty ? "图片" : name)](\(path))"
            }

            return "[\(url.lastPathComponent)](\(path))"
        }

        private func isImageURL(_ url: URL) -> Bool {
            let imageExtensions: Set<String> = [
                "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "svg"
            ]
            return imageExtensions.contains(url.pathExtension.lowercased())
        }

        private func escapedMarkdownPath(for url: URL) -> String {
            let filePath = url.path(percentEncoded: false)
            return filePath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
        }

        private func wrappedDropInsertion(snippets: [String], in text: NSString, at location: Int) -> String {
            let prefixNewlines: String
            if location == 0 || precedingCharacter(in: text, at: location) == "\n" {
                prefixNewlines = ""
            } else if precedingCharacter(in: text, at: location) == "\n" {
                prefixNewlines = ""
            } else {
                prefixNewlines = "\n\n"
            }

            let suffixNewlines: String
            if location >= text.length || followingCharacter(in: text, at: location) == "\n" {
                suffixNewlines = ""
            } else {
                suffixNewlines = "\n\n"
            }

            return prefixNewlines + snippets.joined(separator: "\n") + suffixNewlines
        }

        private func dropFocusOffset(for markdown: String) -> Int {
            if let imageRange = markdown.range(of: "!["),
               let open = markdown[imageRange.upperBound...].firstIndex(of: "("),
               let close = markdown[open...].firstIndex(of: ")") {
                let distance = markdown.distance(from: markdown.startIndex, to: close)
                return max(0, min(distance + 1, markdown.utf16.count))
            }

            return markdown.utf16.count
        }

        private func precedingCharacter(in text: NSString, at location: Int) -> Character? {
            guard location > 0, location - 1 < text.length else { return nil }
            return Character(text.substring(with: NSRange(location: location - 1, length: 1)))
        }

        private func followingCharacter(in text: NSString, at location: Int) -> Character? {
            guard location < text.length else { return nil }
            return Character(text.substring(with: NSRange(location: location, length: 1)))
        }

        private func lineNumber(for location: Int, in text: NSString) -> Int {
            let clampedLocation = min(max(0, location), text.length)
            let prefix = text.substring(to: clampedLocation)
            return max(1, prefix.split(separator: "\n", omittingEmptySubsequences: false).count)
        }

        // MARK: - Focus Mode

        /// 应用专注模式注解：高亮当前段落，淡化其他内容
        private func applyFocusModeAnnotations(
            in textView: NSTextView,
            layoutManager: NSLayoutManager,
            nsText: NSString
        ) {
            var currentParagraphStart: Int = 0
            var currentParagraphEnd: Int = 0

            // 找到当前段落范围
            let selectedRange = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: selectedRange)
            currentParagraphStart = paragraphRange.location
            currentParagraphEnd = NSMaxRange(paragraphRange)

            // 淡化所有内容
            let fullRange = NSRange(location: 0, length: nsText.length)
            layoutManager.addTemporaryAttributes(
                [.foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.5)],
                forCharacterRange: fullRange
            )

            // 高亮当前段落
            let currentParagraphRange = NSRange(location: currentParagraphStart, length: currentParagraphEnd - currentParagraphStart)
            layoutManager.addTemporaryAttributes(
                [.foregroundColor: NSColor.labelColor],
                forCharacterRange: currentParagraphRange
            )

            // 添加高亮背景
            layoutManager.addTemporaryAttributes(
                [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(EditorPreferences.shared.focusModeHighlightOpacity)],
                forCharacterRange: currentParagraphRange
            )
        }

        // MARK: - Typewriter Mode

        /// 打字机模式：将光标垂直居中
        private func centerCursorVertically(in textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.location < textView.string.utf16.count else { return }

            guard
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let cursorPosition = glyphRect.midY

            let visibleHeight = scrollView.documentVisibleRect.height
            let targetOffset = cursorPosition - visibleHeight / 2

            let newOrigin = NSPoint(
                x: scrollView.documentVisibleRect.origin.x,
                y: max(0, targetOffset)
            )

            // 平滑滚动到目标位置
            let currentOrigin = scrollView.documentVisibleRect.origin
            let distance = abs(currentOrigin.y - newOrigin.y)

            // 如果距离较小，直接滚动；如果距离较大，使用动画
            if distance < 100 {
                scrollView.contentView.scroll(to: newOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.contentView.animator().setBoundsOrigin(newOrigin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
    }
}

private final class MarklyTextView: NSTextView {
    var dropHandler: (([URL], NSPoint) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        supportedDropURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !supportedDropURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = supportedDropURLs(from: sender)
        guard !urls.isEmpty else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        dropHandler?(urls, point)
        return true
    }

    private func supportedDropURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let pasteboardItems = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return []
        }

        return pasteboardItems.filter { $0.isFileURL }
    }
}

private extension NSRange {
    func clamped(to upperBound: Int) -> NSRange {
        NSRange(
            location: min(location, upperBound),
            length: min(length, max(0, upperBound - min(location, upperBound)))
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
