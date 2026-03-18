//
//  MarkdownEditorCommands.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum MarkdownEditorCommand: String {
    // 格式化命令
    case heading
    case bold
    case italic
    case inlineCode
    case codeFence
    case quote
    case bulletList
    case orderedList
    case taskList
    case toggleTaskCompletion
    case insertLink
    case insertImage

    // 模式切换命令
    case toggleViewMode
    case toggleEditMode
    case switchToNormalMode
    case switchToFocusMode
    case switchToTypewriterMode
    case switchToSourceMode
    case switchToWysiwygMode
    case switchToSplitMode
}

struct MarkdownEditorCommandRequest {
    let command: MarkdownEditorCommand
    let payload: [String: String]
}

extension Notification.Name {
    static let marklyEditorCommand = Notification.Name("MarklyEditorCommand")
}
