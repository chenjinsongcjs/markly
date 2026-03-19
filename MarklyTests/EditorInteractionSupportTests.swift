import XCTest
@testable import Markly

final class EditorInteractionSupportTests: XCTestCase {
    func testTableNavigatorMovesForwardWithinRow() {
        let result = TableCellNavigator.navigate(
            from: TableCellCoordinate(row: 0, column: 0),
            direction: .forward,
            rowCount: 2,
            columnCount: 3
        )

        XCTAssertEqual(result, .focus(TableCellCoordinate(row: 0, column: 1)))
    }

    func testTableNavigatorAppendsRowWhenAdvancingPastLastCell() {
        let result = TableCellNavigator.navigate(
            from: TableCellCoordinate(row: 1, column: 2),
            direction: .forward,
            rowCount: 2,
            columnCount: 3
        )

        XCTAssertEqual(result, .appendRowAndFocus(TableCellCoordinate(row: 2, column: 0)))
    }

    func testTableNavigatorMovesBackwardToPreviousRowEnd() {
        let result = TableCellNavigator.navigate(
            from: TableCellCoordinate(row: 1, column: 0),
            direction: .backward,
            rowCount: 2,
            columnCount: 3
        )

        XCTAssertEqual(result, .focus(TableCellCoordinate(row: 0, column: 2)))
    }

    func testMarkdownAssetPathingPrefersRelativePathForNearbyFiles() {
        let documentURL = URL(fileURLWithPath: "/tmp/project/docs/note.md")
        let imageURL = URL(fileURLWithPath: "/tmp/project/assets/image one.png")

        let path = MarkdownAssetPathing.markdownPath(for: imageURL, relativeTo: documentURL)

        XCTAssertEqual(path, "../assets/image one.png")
    }

    func testMarkdownAssetPathingEscapesParentheses() {
        let imageURL = URL(fileURLWithPath: "/tmp/demo(image).png")

        let path = MarkdownAssetPathing.markdownPath(for: imageURL, relativeTo: nil)

        XCTAssertEqual(path, "/tmp/demo\\(image\\).png")
    }

    func testMarkdownAssetPathingResolvesRelativeSourceAgainstDocument() {
        let documentURL = URL(fileURLWithPath: "/tmp/project/docs/note.md")

        let resolvedURL = MarkdownAssetPathing.resolvedAssetURL(
            for: "../assets/image.png",
            relativeTo: documentURL
        )

        XCTAssertEqual(resolvedURL?.path(percentEncoded: false), "/tmp/project/assets/image.png")
    }

    func testVisibleBlocksHideFoldedSectionContentButKeepHeading() {
        let markdown = """
        # One
        intro
        ## Child
        child text
        # Two
        tail
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)
        let sections = MarkdownAnalysis.headingSections(in: markdown)

        let visible = DocumentOutlineBehavior.visibleBlocks(
            from: blocks,
            headingSections: sections,
            foldedHeadingLines: [1]
        )

        XCTAssertEqual(visible.map(\.text), ["# One", "# Two", "tail"])
    }

    func testFoldedEditorRangesMatchCollapsedHeadingSections() {
        let markdown = """
        # One
        intro
        ## Child
        child text
        # Two
        tail
        """

        let sections = MarkdownAnalysis.headingSections(in: markdown)
        let ranges = DocumentOutlineBehavior.foldedEditorRanges(
            headingSections: sections,
            foldedHeadingLines: [1, 3]
        )

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0], 2...4)
        XCTAssertEqual(ranges[1], 4...4)
    }

    func testDocumentPreviewSupportBuildsOrderedListRowsWithMarkersAndInlineNodes() {
        let content = DocumentPreviewSupport.content(
            for: .orderedList(items: ["**Bold** item", "next"], startIndex: 3)
        )

        guard case .list(let rows) = content else {
            return XCTFail("Expected list preview content")
        }

        XCTAssertEqual(rows.map(\.marker), ["3.", "4."])
        XCTAssertEqual(rows[0].inlineNodes, [.strong("Bold"), .text(" item")])
        XCTAssertEqual(rows[1].inlineNodes, [.text("next")])
    }

    func testDocumentPreviewSupportBuildsQuoteRowsPerLine() {
        let content = DocumentPreviewSupport.content(
            for: .quote(text: "first line\n`code` line")
        )

        guard case .quote(let rows) = content else {
            return XCTFail("Expected quote preview content")
        }

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].inlineNodes, [.text("first line")])
        XCTAssertEqual(rows[1].inlineNodes, [.inlineCode("code"), .text(" line")])
    }

    func testDocumentPreviewSupportBuildsTaskRowsFromInlineText() {
        let content = DocumentPreviewSupport.content(
            for: .taskList(items: [
                MarkdownTaskItemModel(text: "Ship [docs](https://example.com)", isCompleted: false)
            ])
        )

        guard case .taskList(let rows) = content else {
            return XCTFail("Expected task list preview content")
        }

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(
            rows[0].inlineNodes,
            [
                .text("Ship "),
                .link(title: "docs", destination: "https://example.com", markdown: "[docs](https://example.com)")
            ]
        )
    }
}
