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

## Current Gap Plan

### Remaining Gaps Versus Typora

1. Preview and export are still not backed by one fully shared semantic rendering layer.
2. Complex blocks such as tables, links, and images still rely too much on modal or sheet-based editing compared with Typora's low-interruption flow.
3. Automated coverage is strong at the unit level but still lacks UI-path regression coverage.
4. Autosave, recovery, and long-document polish exist, but still need stronger validation and refinement.

### Next Execution Order

1. Introduce a shared semantic render model and route export through it first.
2. Reuse that semantic model in document-mode preview to reduce preview/export drift.
3. Reduce interruption in table, link, and image editing flows.
4. Add UI automation for the highest-frequency Typora-style paths.
5. Finish polish for autosave, recovery, and long-document responsiveness.

### Started On 2026-03-19

- Added Phase 5 implementation kickoff: a shared `MarkdownRenderModel` now exists as the semantic layer used by HTML rendering/export, with dedicated regression coverage.
- Wired document-mode preview snapshots to reuse `MarkdownRenderModel` for task lists, tables, images, and code fence metadata, so preview and export now begin from the same semantic block interpretation.
- Added the first `MarklyUITests` smoke target, launch-configuration hooks, and accessibility identifiers for pane titles and toolbar actions, so Phase 7 now has a real UI-path automation starting point.
- Reduced interruption for existing link and image edits in document mode by replacing the old sheet-first path with lightweight popover editors, while keeping sheet-based insertion for new content.
