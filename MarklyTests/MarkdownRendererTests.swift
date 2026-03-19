import XCTest
@testable import Markly

@MainActor
final class MarkdownRendererTests: XCTestCase {
    func testRenderToHTMLTreatsCodeFenceAsCodeBlock() {
        let markdown = """
        ```swift
        # Not a heading
        let value = 42
        ```
        """

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(html.contains("# Not a heading"))
        XCTAssertFalse(html.contains("<h1>Not a heading</h1>"))
    }

    func testRenderToHTMLRendersMarkdownTableSemantically() {
        let markdown = """
        | Name | Value |
        | :--- | ---: |
        | One | 1 |
        """

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:left\">Name</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:right\">Value</th>"))
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">1</td>"))
    }

    func testRenderToHTMLRendersBlockquoteWithoutQuoteMarkers() {
        let markdown = """
        > quoted line
        > second line
        """

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<blockquote><p>quoted line<br>second line</p></blockquote>"))
        XCTAssertFalse(html.contains("&gt;"))
    }

    func testRenderToHTMLRendersTaskListWithCheckboxStates() {
        let markdown = """
        - [ ] todo
        - [x] done
        """

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled> todo"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked> done"))
    }

    func testRenderToHTMLRendersInlineLinksAndImagesInsideParagraph() {
        let markdown = "Read [Guide](https://example.com) ![Logo](images/logo.png)"

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<a href=\"https://example.com\">Guide</a>"))
        XCTAssertTrue(html.contains("<img src=\"images/logo.png\" alt=\"Logo\">"))
        XCTAssertTrue(html.contains("<p>"))
    }

    func testRenderToHTMLRendersSharedInlineStylesSemantically() {
        let markdown = "Use **bold** *italic* and `code`"

        let html = MarkdownRenderer.shared.renderToHTML(markdown)

        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }
}
