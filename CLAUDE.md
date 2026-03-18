# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Markly is a macOS Markdown editor built with SwiftUI, using a custom NSTextView-based editor with real-time syntax highlighting. The app aims to provide a Typora-like editing experience with live preview capabilities.

## Build and Run

Open `Markly.xcodeproj` in Xcode and build/run) target "Markly". The project uses SwiftUI + AppKit and requires macOS.

## Architecture

### App Entry Point
- **MarklyApp.swift**: Main app using SwiftUI `DocumentGroup` for file document handling
- **MarkdownMarkdown.swift**: FileDocument implementation for `.md` and `.txt` files

### Editor Core
- **EditorRootView.swift**: Main SwiftUI view coordinating editor and preview, managing:
  - Split-pane editor/preview layout
  - Document outline navigation
  - Folding state for heading sections
  - Link/image insertion sheets

### Native Editor
- **NativeMarkdownEditor.swift**: NSViewRepresentable wrapping `NSTextView` with:
  - **MarklyTextView**: Custom NSTextView subclass with drag-and-drop file support
  - **Coordinator**: Handles all editor behavior including:
    - Syntax highlighting via `MarkdownSyntaxHighlighter`
    - Line continuation (lists, quotes, code blocks)
    - Indent/outdent with Tab/Shift+Tab
    - Markdown formatting commands via NotificationCenter
    - File drag-and-drop for images/links

### Markdown Analysis
- **MarkdownAnalysis.swift**: Static utilities for parsing markdown:
  - Block detection (headings, lists, quotes, code fences, paragraphs)
  - Heading extraction and section computation
  - Block counting and lookup by line number

### Syntax Highlighting
- **MarkdownSyntaxHighlighter.swift**: Regex-based color coding for:
  - Headings (color-coded by level)
  - Lists, task items, quotes
  - Code blocks and inline code
  - Bold, italic, links

### Command System
- **MarkdownEditorCommands.swift**: Defines `MarkdownEditorCommand` enum and NotificationCenter-based command dispatch. Commands are sent via `.marklyEditorCommand` notification and handled in Coordinator's `perform(_:payload:in:)` method.

## Key Patterns

### Editor Commands
To trigger editor commands from SwiftUI, post a notification:
```swift
NotificationCenter.default.post(name: .marklyEditorCommand, object: MarkdownEditorCommand.heading)
```

The Coordinator listens for these and manipulates the NSTextView directly.

### Text Analysis
Use `MarkdownAnalysis` static methods to parse document structure:
- `blocks(in:)` - Get all markdown blocks
- `headings(in:)` - Extract heading hierarchy
- `headingSections(in:)` - Compute heading sections for folding
- `block(containingLine:in:)` - Find block at cursor position

### State Synchronization
The EditorRootView binds to document text and coordinates with NativeMarkdownEditor through:
- `requestedLine`: Scroll to specific line
- `revealedLine`: Last line revealed to user
- `selectionState`: Current cursor position
- `highlightedLineRange/softFoldedLineRanges`: Visual annotations

## File Organization

All source files are in the `Markly/` directory. The project uses Xcode's file system synchronization, so adding/removing Swift files there automatically updates the project.
