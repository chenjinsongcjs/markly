//
//  MarklyApp.swift
//  Markly
//
//  Created by 陈进松 on 2026/3/7.
//

import SwiftUI

@main
struct MarklyApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorRootView(document: file.$document)
        }
    }
}
