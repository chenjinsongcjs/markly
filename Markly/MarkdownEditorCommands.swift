//
//  MarkdownEditorCommands.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum MarkdownEditorCommand: String {
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
}

struct MarkdownEditorCommandRequest {
    let command: MarkdownEditorCommand
    let payload: [String: String]
}

extension Notification.Name {
    static let marklyEditorCommand = Notification.Name("MarklyEditorCommand")
}
