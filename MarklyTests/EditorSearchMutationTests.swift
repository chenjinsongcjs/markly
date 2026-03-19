import XCTest
@testable import Markly

final class EditorSearchMutationTests: XCTestCase {
    func testReplaceCurrentSearchMatchKeepsFocusNearOriginalLine() {
        let markdown = """
        alpha
        beta alpha
        """
        let range = markdown.range(of: "alpha", options: [], range: markdown.index(markdown.startIndex, offsetBy: 6)..<markdown.endIndex)!

        let mutation = EditorDocumentController.replaceCurrentSearchMatch(
            in: markdown,
            matchRange: range,
            replacement: "omega"
        )

        XCTAssertEqual(mutation.focusLine, 2)
        XCTAssertEqual(mutation.text, "alpha\nbeta omega")
    }

    func testReplaceAllSearchMatchesReturnsUpdatedText() {
        let markdown = """
        Alpha
        alpha
        """

        let mutation = EditorDocumentController.replaceAllSearchMatches(
            in: markdown,
            query: "alpha",
            replacement: "omega"
        )

        XCTAssertEqual(mutation.text, "omega\nomega")
        XCTAssertEqual(mutation.focusLine, 1)
    }

    func testReplaceCurrentSearchMatchOnlyChangesSelectedOccurrence() {
        let markdown = """
        alpha
        alpha
        """
        let firstRange = markdown.range(of: "alpha")!

        let mutation = EditorDocumentController.replaceCurrentSearchMatch(
            in: markdown,
            matchRange: firstRange,
            replacement: "omega"
        )

        XCTAssertEqual(mutation.text, "omega\nalpha")
        XCTAssertEqual(mutation.focusLine, 1)
    }

    func testReplaceAllSearchMatchesIsCaseInsensitiveAndUpdatesFocusLine() {
        let markdown = """
        beta
        ALPHA
        gamma alpha
        """

        let mutation = EditorDocumentController.replaceAllSearchMatches(
            in: markdown,
            query: "alpha",
            replacement: "omega"
        )

        XCTAssertEqual(mutation.text, "beta\nomega\ngamma omega")
        XCTAssertEqual(mutation.focusLine, 2)
    }
}
