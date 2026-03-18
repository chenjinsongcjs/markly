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
}
