//
//  StatusBarView.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import SwiftUI

/// 编辑器状态栏视图
struct StatusBarView: View {
    let text: String
    let selectionState: EditorSelectionState
    let currentBlock: MarkdownBlock?
    let isDirty: Bool
    let autoSaveStatus: String?

    var body: some View {
        HStack(spacing: 16) {
            // 行列信息
            Group {
                Label("Ln \(selectionState.line)", systemImage: "list.number")
                Label("Col \(selectionState.column)", systemImage: "character")
                Label("\(selectionState.selectedLength) 已选中", systemImage: "checkmark.circle")
            }

            Divider()
                .frame(height: 14)

            // 字数统计
            Group {
                Label("\(wordCount) 字", systemImage: "textformat")
                Label("\(characterCount) 字符", systemImage: "character")
                Label("\(lineCount) 行", systemImage: "list.number")
                Label("\(paragraphCount) 段", systemImage: "paragraph")
            }

            Divider()
                .frame(height: 14)

            // 当前块信息
            if let currentBlock {
                Label(blockStatusText(for: currentBlock), systemImage: blockSystemImage(for: currentBlock.kind))
            }

            Spacer()

            if let autoSaveStatus {
                Label(autoSaveStatus, systemImage: "clock.arrow.circlepath")
            }

            Label(isDirty ? "未保存" : "已保存", systemImage: isDirty ? "circle.fill" : "checkmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isDirty ? .orange : .secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        words(in: text).count
    }

    private var characterCount: Int {
        text.count
    }

    private var lineCount: Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private var paragraphCount: Int {
        paragraphs(in: text).count
    }

    // MARK: - Helpers

    /// 计算单词数量
    private func words(in text: String) -> [String] {
        let pattern = #"[\p{L}\p{N}]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        return matches.map { (text as NSString).substring(with: $0.range) }
    }

    /// 计算段落数量
    private func paragraphs(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// 块状态文本
    private func blockStatusText(for block: MarkdownBlock) -> String {
        "\(blockDisplayName(for: block.kind)) · \(block.lineStart)-\(block.lineEnd) 行"
    }

    /// 块类型显示名称
    private func blockDisplayName(for kind: MarkdownBlockKind) -> String {
        switch kind {
        case .heading:
            return "标题"
        case .paragraph:
            return "段落"
        case .unorderedList:
            return "无序列表"
        case .orderedList:
            return "有序列表"
        case .taskList:
            return "任务列表"
        case .quote:
            return "引用"
        case .codeFence:
            return "代码块"
        case .table:
            return "表格"
        case .image:
            return "图片"
        case .thematicBreak:
            return "分隔线线"
        }
    }

    /// 块类型系统图标
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
}
