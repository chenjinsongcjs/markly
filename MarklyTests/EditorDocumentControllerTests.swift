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

    func testToggleTaskItemCanUncheckCompletedItem() {
        let markdown = """
        - [x] done
        """

        let mutation = EditorDocumentController.toggleTaskItem(in: markdown, lineNumber: 1)

        XCTAssertEqual(mutation?.focusLine, 1)
        XCTAssertEqual(mutation?.text, "- [ ] done")
    }

    func testToggleTaskItemOnlyChangesRequestedLine() {
        let markdown = """
        - [ ] first
        - [x] second
        """

        let mutation = EditorDocumentController.toggleTaskItem(in: markdown, lineNumber: 2)

        XCTAssertEqual(mutation?.text, "- [ ] first\n- [ ] second")
        XCTAssertEqual(mutation?.focusLine, 2)
    }

    func testToggleTaskItemReturnsNilForNonTaskLine() {
        let markdown = """
        plain paragraph
        """

        let mutation = EditorDocumentController.toggleTaskItem(in: markdown, lineNumber: 1)

        XCTAssertNil(mutation)
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

    func testConvertBlockToHeadingNormalizesMarkdownSyntax() {
        let markdown = """
        - [ ] todo item
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.convertBlockToHeading(
            in: markdown,
            block: block,
            level: 2
        )

        XCTAssertEqual(mutation.text, "## todo item")
        XCTAssertEqual(mutation.focusLine, 1)
    }

    func testConvertBlockToCodeFenceWrapsPlainParagraph() {
        let markdown = """
        print("hello")
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.convertBlock(
            in: markdown,
            block: block,
            to: .codeFence
        )

        XCTAssertEqual(mutation.text, "```\nprint(\"hello\")\n```")
    }

    func testConvertCodeFenceToParagraphUnwrapsFence() {
        let markdown = """
        ```swift
        print("hello")
        ```
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.convertBlock(
            in: markdown,
            block: block,
            to: .paragraph
        )

        XCTAssertEqual(mutation.text, "print(\"hello\")")
    }

    func testConvertCodeFenceToHeadingUsesInnerContent() {
        let markdown = """
        ```swift
        print("hello")
        ```
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.convertBlockToHeading(
            in: markdown,
            block: block,
            level: 2
        )

        XCTAssertEqual(mutation.text, "## print(\"hello\")")
    }

    func testConvertCodeFenceToQuoteDropsFenceMarkers() {
        let markdown = """
        ```swift
        let answer = 42
        print(answer)
        ```
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.convertBlock(
            in: markdown,
            block: block,
            to: .quote
        )

        XCTAssertEqual(mutation.text, "> let answer = 42\n> print(answer)")
    }

    func testUpdateCodeFenceLanguagePreservesBodyAndFenceStyle() {
        let markdown = """
        ```swift
        print("hello")
        ```
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.updateCodeFenceLanguage(
            in: markdown,
            block: block,
            language: "python"
        )

        XCTAssertEqual(mutation.text, "```python\nprint(\"hello\")\n```")
        XCTAssertEqual(mutation.focusLine, 1)
    }

    func testUpdateCodeFenceLanguageCanClearLanguageMarker() {
        let markdown = """
        ~~~swift
        print("hello")
        ~~~
        """
        let block = MarkdownAnalysis.blocks(in: markdown)[0]

        let mutation = EditorDocumentController.updateCodeFenceLanguage(
            in: markdown,
            block: block,
            language: ""
        )

        XCTAssertEqual(mutation.text, "~~~\nprint(\"hello\")\n~~~")
    }
}
