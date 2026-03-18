//
//  EditorMode.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation

/// 编辑器视图模式
enum EditorViewMode: String, CaseIterable {
    /// 文档模式 - 默认的 Typora 风格单文档编辑体验
    case document

    /// 源码模式 - 显示原始 Markdown 语法
    case source

    var localizedName: String {
        switch self {
        case .document:
            return "文档"
        case .source:
            return "源码"
        }
    }

    var systemImage: String {
        switch self {
        case .document:
            return "doc.richtext"
        case .source:
            return "text.cursor"
        }
    }
}

/// 编辑器编辑模式
enum EditorEditMode: String, CaseIterable {
    /// 普通模式
    case normal

    /// 专注模式 - 高亮当前段落，淡化其他内容
    case focus

    /// 打字机模式 - 光标始终垂直居中
    case typewriter

    var localizedName: String {
        switch self {
        case .normal:
            return "普通"
        case .focus:
            return "专注"
        case .typewriter:
            return "打字机"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:
            return "rectangle"
        case .focus:
            return "sun.max.fill"
        case .typewriter:
            return "text.aligncenter"
        }
    }
}
