import XCTest
@testable import Markly

final class EditorDocumentControllerTests: XCTestCase {
    func testDeleteBlockRemovesBlockAndFocusesNearbyLine() {
        let markdown = """
        # Title

        Paragraph one

        Paragraph two
        """

        let block = MarkdownAnalysis.blocks(in: markdown).first { $0.kind == .paragraph }
        let mutation = EditorDocumentController.deleteBlock(in: markdown, block: block!)

        XCTAssertEqual(mutation?.focusLine, 3)
        XCTAssertFalse(mutation?.text.contains("Paragraph one") ?? true)
        XCTAssertTrue(mutation?.text.contains("Paragraph two") ?? false)
    }

    func testDuplicateBlockCopiesTrailingBlankLineGroup() {
        let markdown = """
        # Title

        Paragraph one

        Paragraph two
        """

        let block = MarkdownAnalysis.blocks(in: markdown).first { $0.kind == .paragraph }
        let mutation = EditorDocumentController.duplicateBlock(in: markdown, block: block!)

        XCTAssertEqual(mutation?.focusLine, 5)
        XCTAssertEqual(mutation?.text.components(separatedBy: "Paragraph one").count, 3)
    }

    func testMoveBlockDownSwapsWithNextBlock() {
        let markdown = """
        # One

        First

        Second
        """

        let blocks = MarkdownAnalysis.blocks(in: markdown)
        let firstParagraph = blocks.first { $0.text == "First" }!
        let mutation = EditorDocumentController.moveBlock(in: markdown, block: firstParagraph, direction: .down)

        XCTAssertNotNil(mutation)
        let movedBlocks = MarkdownAnalysis.blocks(in: mutation!.text)
        XCTAssertEqual(movedBlocks.map(\.text), ["# One", "Second", "First"])
    }

    func testToggleTaskItemFlipsCompletionMarker() {
        let markdown = """
        - [ ] todo
        """

        let mutation = EditorDocumentController.toggleTaskItem(in: markdown, lineNumber: 1)

        XCTAssertEqual(mutation?.focusLine, 1)
        XCTAssertEqual(mutation?.text, "- [x] todo")
    }

    func testMergeBlocksPreservesMergedContentAndFocusesPreviousBlock() {
        let markdown = """
        First

        Second
        """
        let blocks = MarkdownAnalysis.blocks(in: markdown)

        let mutation = EditorDocumentController.mergeBlocks(
            in: markdown,
            previous: blocks[0],
            current: blocks[1]
        )

        XCTAssertEqual(mutation?.focusLine, 1)
        XCTAssertEqual(mutation?.text, "First\nSecond")
    }
}
