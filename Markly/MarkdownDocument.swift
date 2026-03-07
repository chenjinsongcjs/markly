//
//  MarkdownDocument.swift
//  Markly
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let marklyMarkdown = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] = [
        .marklyMarkdown,
        .plainText
    ]

    var text: String

    init(text: String = Self.sampleText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            text = ""
            return
        }

        if let content = String(data: data, encoding: .utf8) {
            text = content
            return
        }

        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return .init(regularFileWithContents: data)
    }

    private static let sampleText = """
    # Markly

    一个面向 macOS 的原生 Markdown 编辑器骨架。

    ## 第一阶段目标

    - 打开与保存 `.md` 文件
    - 实时编辑
    - 实时渲染预览
    - 为后续类 Typora 的所见即所得体验预留结构

    > 下一步会重点补齐编辑器能力、文档大纲、图片与代码块体验。

    参考链接：[SwiftUI 文档](https://developer.apple.com/documentation/swiftui)

    ![本地图片路径示例](/tmp/markly-demo.png)
    """
}
