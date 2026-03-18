//
//  EditorDocumentCommands.swift
//  Markly
//
//  Created by Codex on 2026/3/19.
//

import Foundation

enum EditorDocumentCommand {
    case insertParagraph(after: MarkdownBlock)
    case toggleTaskItem(lineNumber: Int)
    case convertBlockToHeading(block: MarkdownBlock, level: Int)
    case convertBlock(block: MarkdownBlock, kind: MarkdownBlockKind)
    case duplicateBlock(MarkdownBlock)
    case moveBlock(MarkdownBlock, direction: BlockMoveDirection)
    case deleteBlock(MarkdownBlock)
}
