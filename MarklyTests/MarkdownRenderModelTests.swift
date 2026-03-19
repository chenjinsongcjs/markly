import XCTest
@testable import Markly

final class MarkdownRenderModelTests: XCTestCase {
    func testBuildProducesSemanticNodesForComplexMarkdown() {
        let markdown = """
        # Title

        3. third
        4. fourth

        - [ ] todo
        - [x] done

        > quoted

        ```swift
        print("hi")
        ```

        | Name | Value |
        | :--- | ---: |
        | One | 1 |
        """

        let nodes = MarkdownRenderModelBuilder.build(from: markdown)

        XCTAssertEqual(nodes.count, 6)

        XCTAssertEqual(nodes[0], .heading(level: 1, text: "Title"))
        XCTAssertEqual(nodes[1], .orderedList(items: ["third", "fourth"], startIndex: 3))
        XCTAssertEqual(
            nodes[2],
            .taskList(items: [
                MarkdownTaskItemModel(text: "todo", isCompleted: false),
                MarkdownTaskItemModel(text: "done", isCompleted: true)
            ])
        )
        XCTAssertEqual(nodes[3], .quote(text: "quoted"))

        if case let .codeBlock(language, code) = nodes[4] {
            XCTAssertEqual(language, "swift")
            XCTAssertEqual(code, "print(\"hi\")")
        } else {
            XCTFail("Expected code block node")
        }

        guard case .table = nodes[5] else {
            return XCTFail("Expected trailing table node")
        }
    }

    func testBuildProducesTableNodeWithAlignments() {
        let markdown = """
        | Name | Value |
        | :--- | ---: |
        | One | 1 |
        """

        let nodes = MarkdownRenderModelBuilder.build(from: markdown)

        guard case let .table(headers, rows) = nodes.first else {
            return XCTFail("Expected table node")
        }

        XCTAssertEqual(headers.map(\.text), ["Name", "Value"])
        XCTAssertEqual(headers.map(\.alignment), [.left, .right])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].columns.map(\.text), ["One", "1"])
        XCTAssertEqual(rows[0].columns.map(\.alignment), [.left, .right])
    }

    func testInlineParserProducesSharedLinkAndImageNodes() {
        let nodes = MarkdownInlineParser.parse("Start [OpenAI](https://openai.com) and ![Logo](logo.png) end")

        XCTAssertEqual(
            nodes,
            [
                .text("Start "),
                .link(title: "OpenAI", destination: "https://openai.com", markdown: "[OpenAI](https://openai.com)"),
                .text(" and "),
                .image(alt: "Logo", source: "logo.png", markdown: "![Logo](logo.png)"),
                .text(" end")
            ]
        )
    }

    func testInlineParserProducesStrongEmphasisAndCodeNodes() {
        let nodes = MarkdownInlineParser.parse("Mix **bold** *italic* `code` and __strong__ _soft_")

        XCTAssertEqual(
            nodes,
            [
                .text("Mix "),
                .strong("bold"),
                .text(" "),
                .emphasis("italic"),
                .text(" "),
                .inlineCode("code"),
                .text(" and "),
                .strong("strong"),
                .text(" "),
                .emphasis("soft")
            ]
        )
    }
}
