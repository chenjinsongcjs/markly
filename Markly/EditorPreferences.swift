//
//  EditorPreferences.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation

enum EditorImageDisplayMode: String, CaseIterable {
    case full
    case compact
    case markdownOnly

    var localizedName: String {
        switch self {
        case .full:
            return "完整预览"
        case .compact:
            return "紧凑预览"
        case .markdownOnly:
            return "仅 Markdown"
        }
    }
}

/// 编辑器用户偏好设置
final class EditorPreferences {
    // MARK: - Singleton
    static let shared = EditorPreferences()

    // MARK: - View Mode
    /// 视图模式
    var viewMode: EditorViewMode = .document {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: Keys.viewMode)
        }
    }

    // MARK: - Edit Mode
    /// 编辑模式
    var editMode: EditorEditMode = .normal {
        didSet {
            UserDefaults.standard.set(editMode.rawValue, forKey: Keys.editMode)
        }
    }

    // MARK: - Typewriter Mode
    /// 打字机模式：光标到顶部/底部的最小距离（行数）
    var typewriterMinLinesFromEdge: Int = 10 {
        didSet {
            UserDefaults.standard.set(typewriterMinLinesFromEdge, forKey: Keys.typewriterMinLinesFromEdge)
        }
    }

    // MARK: - Focus Mode
    /// 专注模式：其他内容的透明度
    var focusModeDimOpacity: Double = 0.25 {
        didSet {
            UserDefaults.standard.set(focusModeDimOpacity, forKey: Keys.focusModeDimOpacity)
        }
    }

    /// 专注模式：当前段落的背景色透明度
    var focusModeHighlightOpacity: Double = 0.05 {
        didSet {
            UserDefaults.standard.set(focusModeHighlightOpacity, forKey: Keys.focusModeHighlightOpacity)
        }
    }

    // MARK: - Font Settings
    /// 编辑器字体大小
    var fontSize: Int = 14 {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: Keys.fontSize)
        }
    }

    /// 编辑器字体名称
    var fontFamily: String? {
        didSet {
            if let fontFamily {
                UserDefaults.standard.set(fontFamily, forKey: Keys.fontFamily)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.fontFamily)
            }
        }
    }

    /// 文档视图的内容宽度
    var documentContentWidth: Double = 860 {
        didSet {
            UserDefaults.standard.set(documentContentWidth, forKey: Keys.documentContentWidth)
        }
    }

    /// 图片显示策略
    var imageDisplayMode: EditorImageDisplayMode = .full {
        didSet {
            UserDefaults.standard.set(imageDisplayMode.rawValue, forKey: Keys.imageDisplayMode)
        }
    }

    // MARK: - Auto Save
    /// 自动保存间隔（秒），0 表示禁用
    var autoSaveInterval: TimeInterval = 30 {
        didSet {
            UserDefaults.standard.set(autoSaveInterval, forKey: Keys.autoSaveInterval)
        }
    }

    // MARK: - Theme
    /// 使用系统外观
    var useSystemAppearance: Bool = true {
        didSet {
            UserDefaults.standard.set(useSystemAppearance, forKey: Keys.useSystemAppearance)
        }
    }

    // MARK: - Initialization
    private init() {
        loadFromUserDefaults()
    }

    private func loadFromUserDefaults() {
        if let viewModeRaw = UserDefaults.standard.string(forKey: Keys.viewMode),
           let savedViewMode = EditorViewMode(rawValue: viewModeRaw) {
            viewMode = savedViewMode
        }

        if let editModeRaw = UserDefaults.standard.string(forKey: Keys.editMode),
           let savedEditMode = EditorEditMode(rawValue: editModeRaw) {
            editMode = savedEditMode
        }

        typewriterMinLinesFromEdge = UserDefaults.standard.integer(forKey: Keys.typewriterMinLinesFromEdge)
        if typewriterMinLinesFromEdge == 0 {
            typewriterMinLinesFromEdge = 10
        }

        focusModeDimOpacity = UserDefaults.standard.double(forKey: Keys.focusModeDimOpacity)
        if focusModeDimOpacity == 0 {
            focusModeDimOpacity = 0.25
        }

        focusModeHighlightOpacity = UserDefaults.standard.double(forKey: Keys.focusModeHighlightOpacity)
        if focusModeHighlightOpacity == 0 {
            focusModeHighlightOpacity = 0.05
        }

        fontSize = UserDefaults.standard.integer(forKey: Keys.fontSize)
        if fontSize == 0 {
            fontSize = 14
        }

        fontFamily = UserDefaults.standard.string(forKey: Keys.fontFamily)

        autoSaveInterval = UserDefaults.standard.double(forKey: Keys.autoSaveInterval)
        if autoSaveInterval == 0 {
            autoSaveInterval = 30
        }

        documentContentWidth = UserDefaults.standard.double(forKey: Keys.documentContentWidth)
        if documentContentWidth == 0 {
            documentContentWidth = 860
        }

        if let imageDisplayModeRaw = UserDefaults.standard.string(forKey: Keys.imageDisplayMode),
           let savedImageDisplayMode = EditorImageDisplayMode(rawValue: imageDisplayModeRaw) {
            imageDisplayMode = savedImageDisplayMode
        }

        if UserDefaults.standard.object(forKey: Keys.useSystemAppearance) == nil {
            useSystemAppearance = true
        } else {
            useSystemAppearance = UserDefaults.standard.bool(forKey: Keys.useSystemAppearance)
        }
    }

    // MARK: - Keys
    private enum Keys {
        static let viewMode = "editor.viewMode"
        static let editMode = "editor.editMode"
        static let typewriterMinLinesFromEdge = "editor.typewriterMinLinesFromEdge"
        static let focusModeDimOpacity = "editor.focusModeDimOpacity"
        static let focusModeHighlightOpacity = "editor.focusModeHighlightOpacity"
        static let fontSize = "editor.fontSize"
        static let fontFamily = "editor.fontFamily"
        static let documentContentWidth = "editor.documentContentWidth"
        static let imageDisplayMode = "editor.imageDisplayMode"
        static let autoSaveInterval = "editor.autoSaveInterval"
        static let useSystemAppearance = "editor.useSystemAppearance"
    }
}
