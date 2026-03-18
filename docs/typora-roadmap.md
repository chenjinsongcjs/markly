# Markly Typora Gap Roadmap

## Goal

Build Markly toward a Typora-like macOS Markdown editor with a continuous editing flow, strong Markdown structure handling, and consistent preview/export behavior.

## Scope

### In scope

- Single-document editing as the primary workflow
- Continuous WYSIWYG-like editing for headings, paragraphs, lists, quotes, code blocks, tables, and images
- Strong Markdown structure analysis and block editing behaviors
- Consistent rendering across editor, preview, HTML export, and PDF export
- Regression coverage for complex Markdown samples and high-frequency editor actions

### Out of scope for the first major milestone

- Multi-document workspace management
- Collaboration and sync
- Plugin architecture
- Advanced publishing pipelines

## Execution Plan

### Phase 0: Baseline

1. Define target capabilities and non-goals in project documentation.
2. Build a realistic Markdown fixture set for complex documents.
3. Create a manual QA checklist for Typora-style interaction paths.

### Phase 1: Markdown Structure Layer

1. Introduce stronger document structure modeling beyond lightweight line-based blocks.
2. Improve block recognition for nested and mixed structures.
3. Add APIs for locating, replacing, inserting, splitting, and merging blocks.
4. Expand parser tests around complex real-world Markdown.

### Phase 2: Unified Editing Data Flow

1. Introduce a shared editing controller/model for text, structure, and selection.
2. Move text mutation logic out of views and into the shared editing layer.
3. Route toolbar, keyboard shortcuts, menus, and block editing through one command path.
4. Unify selection and active block tracking across source and document modes.

### Phase 3: Continuous Typora-Style Editing

1. Convert paragraph editing to inline editing in document mode.
2. Support inline heading editing with outline synchronization.
3. Improve list editing with enter-to-continue, exit-on-empty, and indentation controls.
4. Support quote and code block inline editing behaviors.
5. Add strong keyboard navigation across blocks.

### Phase 4: Media and Complex Blocks

1. Improve image preview, editing, and file-path behavior.
2. Upgrade table editing for keyboard navigation and structure changes.
3. Improve link editing and open behavior.
4. Improve code block language, styling, and utilities.

### Phase 5: Rendering and Export Consistency

1. Replace regex-heavy rendering with shared semantic rendering.
2. Unify preview and export behavior.
3. Improve HTML/PDF export options and stability.
4. Add rendering and export regression tests.

### Phase 6: Experience Polish

1. Fill in Typora-like keyboard shortcuts and editing commands.
2. Improve search and replace across both modes.
3. Optimize long-document performance with cached or incremental structure analysis.
4. Strengthen autosave and recovery behavior.

### Phase 7: Quality Gates

1. Expand unit tests for parser, editing commands, and export.
2. Add UI coverage for high-frequency flows.
3. Turn every fixed edge case into a regression fixture and test.

## Recommended Implementation Order

1. Refactor `MarkdownAnalysis`
2. Add a unified editing controller/model
3. Convert paragraphs, headings, and lists to inline editing in document mode
4. Extend inline editing to quotes and code blocks
5. Upgrade tables, images, and links
6. Rework rendering and export consistency
7. Expand automated regression coverage
