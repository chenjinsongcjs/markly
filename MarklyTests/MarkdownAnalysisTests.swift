import XCTest
@testable import Markly

final class MarkdownAnalysisTests: XCTestCase {
    func testBlocksRecognizeImagesTablesAndLists() {
        let markdown = """
        # Title

        ![Alt](images/demo.png)

        | Name | Value |
        | --- | --- |
        | One | 1 |

        - item
        - [ ] task
        1. ordered
        > quote
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)

        XCTAssertEqual(blocks.map(\.kind), [.heading, .image, .table, .unorderedList, .taskList, .orderedList, .quote])
    }

    func testReplaceBlockPreservesOtherContent() {
        let markdown = """
        # Title

        Paragraph one

        Paragraph two
        """

        let block = MarkdownAnalysis.blocks(in: markdown).first { $0.kind == .paragraph }
        XCTAssertNotNil(block)

        let updated = MarkdownAnalysis.replaceBlock(block!, with: "Updated paragraph", in: markdown)

        XCTAssertTrue(updated.contains("Updated paragraph"))
        XCTAssertTrue(updated.contains("# Title"))
        XCTAssertTrue(updated.contains("Paragraph two"))
    }

    func testInsertBlockAfterLinePlacesMarkdownAtExpectedLocation() {
        let markdown = """
        # Title

        Paragraph
        """

        let inserted = MarkdownAnalysis.insertBlock("\n- [ ] next", afterLine: 3, in: markdown)
        let lines = MarkdownAnalysis.lines(in: inserted)

        XCTAssertEqual(lines[3], "")
        XCTAssertEqual(lines[4], "- [ ] next")
    }

    func testHeadingSectionsStopAtNextSiblingOrParent() {
        let markdown = """
        # One
        text
        ## Child
        child
        # Two
        tail
        """

        let sections = MarkdownAnalysis.headingSections(in: markdown)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].contentLineEnd, 4)
        XCTAssertEqual(sections[1].contentLineEnd, 4)
        XCTAssertEqual(sections[2].contentLineEnd, 6)
    }

    func testBlocksRecognizeNestedListsAndQuotedLists() {
        let markdown = """
        - parent
          - child
          1. nested ordered

        > - quoted bullet
        > 1. quoted ordered
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)

        XCTAssertEqual(blocks.map(\.kind), [.unorderedList, .quote])
        XCTAssertEqual(blocks[0].lineStart, 1)
        XCTAssertEqual(blocks[0].lineEnd, 3)
        XCTAssertEqual(blocks[1].lineStart, 5)
        XCTAssertEqual(blocks[1].lineEnd, 6)
    }

    func testCodeFenceWinsOverInnerMarkdownSyntax() {
        let markdown = """
        ```swift
        # Not a heading
        | not | a | table |
        - not a list
        ```
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.kind, .codeFence)
        XCTAssertEqual(blocks.first?.lineStart, 1)
        XCTAssertEqual(blocks.first?.lineEnd, 5)
    }

    func testThematicBreakAllowsInternalWhitespace() {
        let markdown = """
        Paragraph

        - - -
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)

        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .thematicBreak])
    }
}
