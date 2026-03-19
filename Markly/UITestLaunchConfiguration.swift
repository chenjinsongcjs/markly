//
//  UITestLaunchConfiguration.swift
//  Markly
//
//  Created by Codex on 2026/3/19.
//

import Foundation

struct UITestLaunchConfiguration {
    static let enabledArgument = "-markly-ui-testing"
    static let initialTextEnvironmentKey = "MARKLY_UI_TEST_TEXT"
    static let initialViewModeEnvironmentKey = "MARKLY_UI_TEST_VIEW_MODE"

    let initialText: String?
    let initialViewMode: EditorViewMode?

    static var current: UITestLaunchConfiguration? {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains(enabledArgument) else { return nil }

        let environment = processInfo.environment
        let initialText = environment[initialTextEnvironmentKey].flatMap { value -> String? in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }
        let initialViewMode = environment[initialViewModeEnvironmentKey]
            .flatMap(EditorViewMode.init(rawValue:))

        return UITestLaunchConfiguration(
            initialText: initialText,
            initialViewMode: initialViewMode
        )
    }
}
