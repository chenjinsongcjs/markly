//
//  MarklyApp.swift
//  Markly
//
//  Created by 陈进松 on 2026/3/7.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct MarklyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorRootView(document: file.$document, fileURL: file.fileURL)
        }
    }
}
