import Foundation
import XCTest
@testable import Markly

final class BlockEditingBehaviorTests: XCTestCase {
    func testEmptyStructureLinesExitTheirBlocks() {
        XCTAssertTrue(BlockEditingBehavior.shouldExitStructure(for: .quote, currentLineText: "> "))
        XCTAssertTrue(BlockEditingBehavior.shouldExitStructure(for: .unorderedList, currentLineText: "- "))
        XCTAssertTrue(BlockEditingBehavior.shouldExitStructure(for: .orderedList, currentLineText: "3. "))
        XCTAssertTrue(BlockEditingBehavior.shouldExitStructure(for: .taskList, currentLineText: "- [ ] "))
        XCTAssertFalse(BlockEditingBehavior.shouldExitStructure(for: .paragraph, currentLineText: "text"))
    }

    func testOrderedListContinuationUsesNextNumber() {
        let block = MarkdownBlock(kind: .orderedList, lineStart: 1, lineEnd: 2, text: "2. one\n3. two")
        let continuation = BlockEditingBehavior.continuationMarkdown(after: block, editedText: block.text)

        XCTAssertEqual(continuation, "\n4. ")
    }

    func testContinuationMarkdownMatchesStructureType() {
        let unordered = MarkdownBlock(kind: .unorderedList, lineStart: 1, lineEnd: 1, text: "- item")
        let task = MarkdownBlock(kind: .taskList, lineStart: 1, lineEnd: 1, text: "- [x] done")
        let quote = MarkdownBlock(kind: .quote, lineStart: 1, lineEnd: 1, text: "> note")
        let paragraph = MarkdownBlock(kind: .paragraph, lineStart: 1, lineEnd: 1, text: "Paragraph")

        XCTAssertEqual(
            BlockEditingBehavior.continuationMarkdown(after: unordered, editedText: unordered.text),
            "\n- "
        )
        XCTAssertEqual(
            BlockEditingBehavior.continuationMarkdown(after: task, editedText: task.text),
            "\n- [ ] "
        )
        XCTAssertEqual(
            BlockEditingBehavior.continuationMarkdown(after: quote, editedText: quote.text),
            "\n> "
        )
        XCTAssertEqual(
            BlockEditingBehavior.continuationMarkdown(after: paragraph, editedText: paragraph.text),
            "\n新段落"
        )
    }

    func testNonEmptyStructureLinesDoNotExitTheirBlocks() {
        XCTAssertFalse(BlockEditingBehavior.shouldExitStructure(for: .quote, currentLineText: "> keep"))
        XCTAssertFalse(BlockEditingBehavior.shouldExitStructure(for: .unorderedList, currentLineText: "- keep"))
        XCTAssertFalse(BlockEditingBehavior.shouldExitStructure(for: .orderedList, currentLineText: "1. keep"))
        XCTAssertFalse(BlockEditingBehavior.shouldExitStructure(for: .taskList, currentLineText: "- [x] keep"))
    }

    func testOrderedListContinuationFallsBackToOneWhenContentLacksMarker() {
        let block = MarkdownBlock(kind: .orderedList, lineStart: 1, lineEnd: 1, text: "plain text")
        let continuation = BlockEditingBehavior.continuationMarkdown(after: block, editedText: block.text)

        XCTAssertEqual(continuation, "\n1. ")
    }

    func testIndentationAddsLeadingSpacesAndUpdatesSelection() {
        let original = "- item\n- next"
        let result = BlockEditingBehavior.adjustingIndentation(
            in: original,
            selectedRange: NSRange(location: 0, length: (original as NSString).length),
            direction: .right
        )

        XCTAssertEqual(result.text, "  - item\n  - next")
        XCTAssertEqual(result.selection.location, 2)
        XCTAssertGreaterThan(result.selection.length, (original as NSString).length)
    }

    func testOutdentationRemovesLeadingSpaces() {
        let original = "  - item\n  - next"
        let result = BlockEditingBehavior.adjustingIndentation(
            in: original,
            selectedRange: NSRange(location: 0, length: (original as NSString).length),
            direction: .left
        )

        XCTAssertEqual(result.text, "- item\n- next")
        XCTAssertEqual(result.selection.location, 0)
    }
}
