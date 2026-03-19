//
//  MarklyUITests.swift
//  MarklyUITests
//
//  Created by Codex on 2026/3/19.
//

import XCTest

final class MarklyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesInDocumentModeWithFixtureContent() throws {
        let app = launchApp(
            viewModeRawValue: "document",
            markdown: """
            # Typora Path

            - [ ] Verify preview
            """
        )

        XCTAssertTrue(app.staticTexts["editor.documentPaneTitleLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["editor.documentSummary"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchesInSourceModeAndOpensSearchSheet() throws {
        let app = launchApp(
            viewModeRawValue: "source",
            markdown: """
            # Search Fixture

            Paragraph for search.
            """
        )

        XCTAssertTrue(app.staticTexts["editor.sourcePaneTitleLabel"].waitForExistence(timeout: 5))

        let searchButton = app.buttons["editor.searchToolbarButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.click()

        XCTAssertTrue(app.staticTexts["editor.searchSheetTitle"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSwitchesModesWithKeyboardShortcuts() throws {
        let app = launchApp(
            viewModeRawValue: "source",
            markdown: """
            # Mode Fixture

            Shortcut flow
            """
        )

        XCTAssertTrue(app.staticTexts["editor.sourcePaneTitleLabel"].waitForExistence(timeout: 5))

        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["editor.documentPaneTitleLabel"].waitForExistence(timeout: 2))

        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["editor.sourcePaneTitleLabel"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testReplaceAllUpdatesSourceEditorText() throws {
        let app = launchApp(
            viewModeRawValue: "source",
            markdown: """
            # Replace Fixture

            alpha beta alpha
            """
        )

        XCTAssertTrue(app.staticTexts["editor.sourcePaneTitleLabel"].waitForExistence(timeout: 5))

        let searchButton = app.buttons["editor.searchToolbarButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.click()

        let searchField = app.textFields["editor.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.click()
        searchField.typeText("alpha")

        let replaceField = app.textFields["editor.replaceField"]
        XCTAssertTrue(replaceField.waitForExistence(timeout: 2))
        replaceField.click()
        replaceField.typeText("omega")

        let replaceAllButton = app.buttons["editor.replaceAllButton"]
        XCTAssertTrue(replaceAllButton.waitForExistence(timeout: 2))
        replaceAllButton.click()

        let sourceTextView = app.textViews["editor.sourceTextView"]
        XCTAssertTrue(sourceTextView.waitForExistence(timeout: 2))
        let renderedText = sourceTextView.value as? String
        XCTAssertEqual(renderedText, """
        # Replace Fixture

        omega beta omega
        """)
    }

    @MainActor
    func testSearchNavigationUpdatesStatus() throws {
        let app = launchApp(
            viewModeRawValue: "source",
            markdown: """
            alpha
            beta alpha
            """
        )

        XCTAssertTrue(app.staticTexts["editor.sourcePaneTitleLabel"].waitForExistence(timeout: 5))

        app.buttons["editor.searchToolbarButton"].click()
        let searchField = app.textFields["editor.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.click()
        searchField.typeText("alpha")

        let searchStatus = app.staticTexts["editor.searchStatusLabel"]
        XCTAssertTrue(searchStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(searchStatus.label, "搜索结果 1/2")

        app.buttons["editor.searchNextButton"].click()
        XCTAssertEqual(searchStatus.label, "搜索结果 2/2")

        app.buttons["editor.searchPreviousButton"].click()
        XCTAssertEqual(searchStatus.label, "搜索结果 1/2")
    }

    @MainActor
    func testToggleTaskItemInDocumentMode() throws {
        let app = launchApp(
            viewModeRawValue: "document",
            markdown: """
            # Tasks

            - [ ] Ship UI tests
            """
        )

        XCTAssertTrue(app.staticTexts["editor.documentPaneTitleLabel"].waitForExistence(timeout: 5))

        let taskToggleButton = app.buttons["editor.task.3.toggle"]
        XCTAssertTrue(taskToggleButton.waitForExistence(timeout: 2))
        taskToggleButton.click()
        taskToggleButton.click()

        XCTAssertTrue(taskToggleButton.waitForExistence(timeout: 2))
    }

    @MainActor
    func testFoldHeadingHidesNestedTaskBlock() throws {
        let app = launchApp(
            viewModeRawValue: "document",
            markdown: """
            # Fold Me

            - [ ] Hidden after fold
            """
        )

        XCTAssertTrue(app.staticTexts["editor.documentPaneTitleLabel"].waitForExistence(timeout: 5))

        let foldButton = app.buttons["editor.heading.1.foldButton"]
        let taskToggleButton = app.buttons["editor.task.3.toggle"]
        XCTAssertTrue(foldButton.waitForExistence(timeout: 2))
        XCTAssertTrue(taskToggleButton.waitForExistence(timeout: 2))

        foldButton.click()
        XCTAssertFalse(taskToggleButton.waitForExistence(timeout: 1))

        foldButton.click()
        XCTAssertTrue(taskToggleButton.waitForExistence(timeout: 2))
    }

    @MainActor
    func testDoubleClickBlockEntersEditorAndAppliesChanges() throws {
        let app = launchApp(
            viewModeRawValue: "document",
            markdown: """
            # Edit Block

            Original paragraph
            """
        )

        XCTAssertTrue(app.staticTexts["editor.documentPaneTitleLabel"].waitForExistence(timeout: 5))

        let blockCard = app.otherElements["editor.block.3.card"]
        XCTAssertTrue(blockCard.waitForExistence(timeout: 2))
        blockCard.doubleClick()

        let editorCard = app.otherElements["editor.block.3.editorCard"]
        XCTAssertTrue(editorCard.waitForExistence(timeout: 2))

        let blockTextView = app.textViews["editor.block.3.textView"]
        XCTAssertTrue(blockTextView.waitForExistence(timeout: 2))
        blockTextView.click()
        app.typeKey("a", modifierFlags: .command)
        blockTextView.typeText("Updated paragraph")

        let applyButton = app.buttons["editor.block.3.applyButton"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 2))
        applyButton.click()

        XCTAssertFalse(editorCard.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Updated paragraph"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func launchApp(viewModeRawValue: String, markdown: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-markly-ui-testing")
        app.launchEnvironment["MARKLY_UI_TEST_VIEW_MODE"] = viewModeRawValue
        app.launchEnvironment["MARKLY_UI_TEST_TEXT"] = markdown
        app.launch()
        return app
    }
}
