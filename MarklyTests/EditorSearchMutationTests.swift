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
}
