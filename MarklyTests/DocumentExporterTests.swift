import XCTest
@testable import Markly

@MainActor
final class DocumentExporterTests: XCTestCase {
    func testPreparedExportHTMLRewritesRelativeImageSourceToFileURL() {
        let markdown = "![Demo](../assets/image.png)"
        let documentURL = URL(fileURLWithPath: "/tmp/project/docs/note.md")

        let html = DocumentExporter.preparedExportHTML(
            markdown: markdown,
            sourceDocumentURL: documentURL
        )

        XCTAssertTrue(html.contains("file:///tmp/project/assets/image.png"))
    }

    func testPreparedExportHTMLPreservesRemoteImageSource() {
        let markdown = "![Demo](https://example.com/image.png)"

        let html = DocumentExporter.preparedExportHTML(
            markdown: markdown,
            sourceDocumentURL: URL(fileURLWithPath: "/tmp/project/docs/note.md")
        )

        XCTAssertTrue(html.contains("https://example.com/image.png"))
    }

    func testPreparedExportHTMLPreservesSemanticBlockStructure() {
        let markdown = """
        # Title

        - [ ] todo

        ```swift
        print("hi")
        ```

        | Name | Value |
        | --- | ---: |
        | One | 1 |
        """

        let html = DocumentExporter.preparedExportHTML(
            markdown: markdown,
            sourceDocumentURL: URL(fileURLWithPath: "/tmp/project/docs/note.md")
        )

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled> todo"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">print(&quot;hi&quot;)</code></pre>"))
        XCTAssertTrue(html.contains("<table><thead><tr>"))
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">1</td>"))
    }
}
