//
//  MarkdownRenderer.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import AppKit

/// Markdown 渲染引擎
/// 提供基础的 Markdown 到 HTML 和 AttributedString 的转换功能
@MainActor
final class MarkdownRenderer {
    // MARK: - Singleton
    static let shared = MarkdownRenderer()

    // MARK: - AttributedString Rendering

    /// 将 Markdown 文本转换为 AttributedString
    /// - Parameters:
    ///   - markdown: Markdown 源文本
    ///   - fontSize: 字体大小，默认为 14
    /// - Returns: 渲染后的 AttributedString
    func renderToAttributedString(
        _ markdown: String,
        fontSize: CGFloat = 14
    ) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: markdown)
        let fullRange = NSRange(location: 0, length: attributedString.length)

        // 设置基础样式
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        attributedString.setAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )

        // 渲染标题
        renderHeadings(in: attributedString, fontSize: fontSize)

        // 渲染粗体
        renderBold(in: attributedString, fontSize: fontSize)

        // 渲染斜体
        renderItalic(in: attributedString)

        // 渲染行内代码
        renderInlineCode(in: attributedString)

        // 渲染链接
        renderLinks(in: attributedString)

        return attributedString
    }

    // MARK: - HTML Rendering

    /// 将 Markdown 文本转换为 HTML
    /// - Parameter markdown: Markdown 源文本
    /// - Returns: HTML 字符串
    func renderToHTML(_ markdown: String) -> String {
        var html = markdown

        // 转义 HTML 特殊字符
        html = escapeHTML(html)

        // 渲染标题
        html = renderHeadingsHTML(html)

        // 渲染粗体
        html = html.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"__([^_]+)__"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // 渲染斜体
        html = html.replacingOccurrences(
            of: #"\*([^*]+)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #" _([^_]+)_"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // 渲染行内代码
        html = html.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // 渲染链接
        html = html.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // 渲染图片
        html = html.replacingOccurrences(
            of: #"!\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\">",
            options: .regularExpression
        )

        // 渲染换行
        html = html.replacingOccurrences(of: "\n\n", with: "<p>")
        html = html.replacingOccurrences(of: "\n", with: "<br>")

        return html
    }

    /// 将 Markdown 渍染为完整的 HTML 文档
    /// - Parameter markdown: Markdown 源文本
    /// - Returns: 完整的 HTML 文档
    func renderToCompleteHTML(_ markdown: String) -> String {
        let bodyHTML = renderToHTML(markdown)

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 20px;
                    background-color: #fff;
                }
                h1 { font-size: 2em; margin: 0.67em 0; border-bottom: 1px solid #eee; padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; margin: 0.83em 0; border-bottom: 1px solid #eee; padding-bottom: 0.3em; }
                h3 { font-size: 1.17em; margin: 1em 0; }
                h4 { font-size: 1em; margin: 1.33em 0; }
                h5 { font-size: 0.83em; margin: 1.67em 0; }
                h6 { font-size: 0.67em; margin: 2.33em 0; color: #666; }
                code { font-family: 'SF Mono', Monaco, Consolas, monospace; background: #f5f5f5; padding: 2px 4px; border-radius: 3px; font-size: 0.9em; }
                a { color: #0066cc; text-decoration: none; }
                a:hover { text-decoration: underline; }
                img { max-width: 100%; height: auto; }
                pre { background: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; }
                pre code { background: none; padding: 0; }
                blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid #ddd; color: #666; }
                ul, ol { padding-left: 2em; }
                table { border-collapse: collapse; width: 100%; margin: 1em 0; }
                th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                th { background: #f5f5f5; }
            </style>
        </head>
        <body>
            \(bodyHTML)
        </body>
        </html>
        """
    }

    // MARK: - Private Helpers

    /// 转义 HTML 特殊字符
    private func escapeHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    /// 在 AttributedString 中渲染标题
    private func renderHeadings(in attributedString: NSMutableAttributedString, fontSize: CGFloat) {
        let pattern = #"^(#{1,6})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return
        }

        let swiftText = attributedString.string
        let text = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: swiftText, range: fullRange) { match, _, _ in
            guard let match else { return }

            let level = match.range(at: 1).length
            let titleRange = match.range(at: 2)

            // 根据标题级别设置字体大小
            let titleFontSize: CGFloat
            switch level {
            case 1: titleFontSize = fontSize * 2.0
            case 2: titleFontSize = fontSize * 1.5
            case 3: titleFontSize = fontSize * 1.3
            case 4: titleFontSize = fontSize * 1.1
            case 5: titleFontSize = fontSize * 0.95
            default: titleFontSize = fontSize * 0.85
            }

            attributedString.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: titleFontSize, weight: .bold),
                    .foregroundColor: NSColor.labelColor
                ],
                range: titleRange
            )

            // 设置 # 标记为灰色
            attributedString.addAttributes(
                [
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: match.range(at: 1)
            )
        }
    }

    /// 在 HTML 中渲染标题
    private func renderHeadingsHTML(_ html: String) -> String {
        var result = html

        // 处理各级标题
        for level in 1...6 {
            let pattern = "(?m)^(#{\(level)})\\s+(.+)$"
            let replacement = "<h\(level)>$2</h\(level)>"
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return result
    }

    /// 在 AttributedString 中渲染粗体
    private func renderBold(in attributedString: NSMutableAttributedString, fontSize: CGFloat) {
        let pattern = #"\*\*[^*]+\*\*|__[^_]+__"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let swiftText = attributedString.string
        let text = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: swiftText, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributedString.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                range: match.range
            )
        }
    }

    /// 在 AttributedString 中渲染斜体
    private func renderItalic(in attributedString: NSMutableAttributedString) {
        let pattern = #"\*[^*]+\*|_[^_\n]+_"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let text = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: attributedString.string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributedString.addAttribute(
                .obliqueness,
                value: 0.18,
                range: match.range
            )
        }
    }

    /// 在 AttributedString 中渲染行内代码
    private func renderInlineCode(in attributedString: NSMutableAttributedString) {
        let pattern = #"`[^`\n]+`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let text = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: attributedString.string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributedString.addAttributes(
                [
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15),
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                ],
                range: match.range
            )
        }
    }

    /// 在 AttributedString 中渲染链接
    private func renderLinks(in attributedString: NSMutableAttributedString) {
        let pattern = #"\[[^\]]+\]\([^)]+\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let text = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: attributedString.string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributedString.addAttribute(
                .foregroundColor,
                value: NSColor.systemBlue,
                range: match.range
            )
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: match.range
            )
        }
    }
}
