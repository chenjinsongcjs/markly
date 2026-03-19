//
//  DocumentExporter.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 文档导出器
struct DocumentExporter {

    // MARK: - Export Formats

    enum ExportFormat: String, CaseIterable {
        case html
        case pdf

        var displayName: String {
            switch self {
            case .html:
                return "HTML"
            case .pdf:
                return "PDF"
            }
        }

        var fileExtension: String {
            switch self {
            case .html:
                return "html"
            case .pdf:
                return "pdf"
            }
        }

        var systemImage: String {
            switch self {
            case .html:
                return "doc.text"
            case .pdf:
                return "doc.richtext"
            }
        }

        var contentType: UTType {
            switch self {
            case .html:
                return .html
            case .pdf:
                return .pdf
            }
        }
    }

    // MARK: - Export Methods

    /// 导出文档
    /// - Parameters:
    ///   - markdown: Markdown 源文本
    ///   - format: 导出格式
    ///   - suggestedURL: 建议的文件 URL
    ///   - completion: 完成回调，返回成功/失败和文件 URL
    static func export(
        markdown: String,
        format: ExportFormat,
        sourceDocumentURL: URL? = nil,
        suggestedURL: URL? = nil,
        completion: @escaping (Bool, URL?) -> Void
    ) {
        // 保存面板
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.nameFieldStringValue = suggestedURL?.deletingPathExtension().lastPathComponent ?? "untitled"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                completion(false, nil)
                return
            }

            let finalURL = url.pathExtension == format.fileExtension ? url : url.appendingPathExtension(format.fileExtension)

            switch format {
            case .html:
                exportToHTML(
                    markdown: markdown,
                    sourceDocumentURL: sourceDocumentURL,
                    to: finalURL,
                    completion: completion
                )
            case .pdf:
                exportToPDF(
                    markdown: markdown,
                    sourceDocumentURL: sourceDocumentURL,
                    to: finalURL,
                    completion: completion
                )
            }
        }
    }

    /// 导出为 HTML
    private static func exportToHTML(
        markdown: String,
        sourceDocumentURL: URL?,
        to url: URL,
        completion: @escaping (Bool, URL?) -> Void
    ) {
        let html = preparedExportHTML(markdown: markdown, sourceDocumentURL: sourceDocumentURL)

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            completion(true, url)
        } catch {
            NSLog("HTML 导出失败: \(error.localizedDescription)")
            completion(false, nil)
        }
    }

    /// 导出为 PDF
    private static func exportToPDF(
        markdown: String,
        sourceDocumentURL: URL?,
        to url: URL,
        completion: @escaping (Bool, URL?) -> Void
    ) {
        // 创建用于渲染的 WebView
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
        webView.isHidden = true

        let html = preparedExportHTML(markdown: markdown, sourceDocumentURL: sourceDocumentURL)
        webView.loadHTMLString(html, baseURL: sourceDocumentURL?.deletingLastPathComponent())

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let configuration = WKPDFConfiguration()
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                        completion(true, url)
                    } catch {
                        NSLog("PDF 导出失败: \(error.localizedDescription)")
                        completion(false, nil)
                    }
                case .failure(let error):
                    NSLog("PDF 导出失败: \(error.localizedDescription)")
                    completion(false, nil)
                }
            }
        }
    }

    static func preparedExportHTML(markdown: String, sourceDocumentURL: URL?) -> String {
        let baseHTML = MarkdownRenderer.shared.renderToCompleteHTML(markdown)
        return rewritingImageSources(in: baseHTML, sourceDocumentURL: sourceDocumentURL)
    }

    private static func rewritingImageSources(in html: String, sourceDocumentURL: URL?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<img\s+src="([^"]+)" alt="([^"]*)">"#) else {
            return html
        }

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        let matches = regex.matches(in: html, range: range)
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            let source = nsHTML.substring(with: match.range(at: 1))
            guard let resolvedURL = MarkdownAssetPathing.resolvedAssetURL(for: source, relativeTo: sourceDocumentURL) else {
                continue
            }

            let escapedSource = resolvedURL.isFileURL ? resolvedURL.absoluteString : resolvedURL.absoluteString
            if let sourceRange = Range(match.range(at: 1), in: result) {
                result.replaceSubrange(sourceRange, with: escapedSource)
            }
        }

        return result
    }
}

// MARK: - Export Sheet View

/// 导出选项视图
struct ExportSheetView: View {
    let markdown: String
    let sourceDocumentURL: URL?
    let onComplete: (Bool, URL?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: DocumentExporter.ExportFormat = .html
    @State private var includeTitle: Bool = true
    @State private var titleText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("导出文档")
                .font(.title3.weight(.semibold))

            Divider()

            // 格式选择
            VStack(alignment: .leading, spacing: 8) {
                Text("导出格式")
                    .font(.headline)

                Picker("导出格式", selection: $selectedFormat) {
                    ForEach(DocumentExporter.ExportFormat.allCases, id: \.self) { format in
                        Label(format.displayName, systemImage: format.systemImage)
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 标题选项（仅 HTML）
            if selectedFormat == .html {
                Toggle("包含标题", isOn: $includeTitle)

                if includeTitle {
                    TextField("文档标题", text: $titleText)
                }
            }

            Spacer()

            // 预览信息
            exportPreview
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear {
            extractTitle(from: markdown)
        }
    }

    private var exportPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预览信息")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Label(selectedFormat.displayName, systemImage: selectedFormat.systemImage)
                Spacer()
                Text("文件扩展名: .\(selectedFormat.fileExtension)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("将要导出 \(markdown.count) 个字符")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary)
        .cornerRadius(8)
    }

    private func extractTitle(from markdown: String) {
        guard includeTitle, titleText.isEmpty else { return }

        // 尝试从第一行提取标题
        if let firstLine = markdown.split(separator: "\n").first {
            let line = String(firstLine)
            if line.hasPrefix("# ") {
                titleText = String(line.dropFirst(2))
            } else {
                titleText = line.trimmingCharacters(in: .whitespaces)
            }
        }
    }
}

/// 导出按钮包装器
struct ExportButton: View {
    let markdown: String
    let sourceDocumentURL: URL?
    let suggestedURL: URL?
    var onExportComplete: ((Bool, URL?) -> Void)?

    var body: some View {
        Menu {
            ForEach(DocumentExporter.ExportFormat.allCases, id: \.self) { format in
                Button {
                    export(format)
                } label: {
                    Label(format.displayName, systemImage: format.systemImage)
                }
            }
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
    }

    private func export(_ format: DocumentExporter.ExportFormat) {
        DocumentExporter.export(
            markdown: markdown,
            format: format,
            sourceDocumentURL: sourceDocumentURL,
            suggestedURL: suggestedURL
        ) { success, url in
            onExportComplete?(success, url)
        }
    }
}

// MARK: - Print Support

extension DocumentExporter {
    /// 打印文档
    /// - Parameter markdown: Markdown 源文本
    static func print(markdown: String) {
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.scalingFactor = 1.0

        let printOperation = NSPrintOperation.printOperation(with: markdown)
        printOperation.showsPrintPanel = true
        printOperation.run()
    }
}

// MARK: - NSPrintOperation Extension

private extension NSPrintOperation {
    static func printOperation(with markdown: String) -> NSPrintOperation {
        // 创建文本视图进行打印
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        let html = MarkdownRenderer.shared.renderToCompleteHTML(markdown)

        // 创建 WebView 渲染 HTML
        let webView = WKWebView(frame: textView.bounds)
        webView.loadHTMLString(html, baseURL: nil)

        // 创建打印操作
        let printOp = NSPrintOperation(view: webView, printInfo: NSPrintInfo.shared)
        return printOp
    }
}
