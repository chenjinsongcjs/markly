# Typora-Style QA Checklist

## Core Document Flow

- Open an existing `.md` file and preserve content exactly.
- Create a new untitled document and confirm recovery works after relaunch.
- Switch between source mode and document mode without losing selection or edits.
- Confirm autosave updates file-backed documents and untitled drafts.

## Block Editing

- Click a paragraph in document mode and edit in place.
- Edit a heading and confirm the outline updates immediately.
- Press Return in a paragraph and create a new paragraph below.
- Delete an empty block and merge with the previous editable block.

## Lists and Quotes

- Press Return in a bullet list item and continue the list.
- Press Return in an empty bullet item and exit the list.
- Press Return in an ordered list and increment the marker.
- Press Tab and Shift-Tab to indent and outdent list items.
- Edit task list items and toggle completion from document mode.
- Press Return in a quote and continue the quote.
- Press Return in an empty quote line and exit the quote.

## Code, Tables, Media

- Edit a fenced code block without breaking its fence markers.
- Change a code block language and preserve content.
- Open table editing and add/remove rows and columns.
- Navigate table cells with keyboard only.
- Drag an image file into the editor and create Markdown at the drop position.
- Edit image alt text and source from the document UI.

## Navigation and Search

- Click an outline heading and jump to the right location.
- Fold and unfold heading sections without corrupting content.
- Search in both modes and step through all matches.
- Replace one match and replace all matches correctly.

## Export

- Export HTML and confirm heading, list, table, image, and code block structure.
- Export PDF and confirm the content matches the document view closely.
- Export documents containing local images and verify image paths resolve as expected.

## Progress Notes

- 2026-03-19: Block editing for fenced code blocks now preserves fences and supports language editing in document mode.
- 2026-03-19: Table editor supports keyboard-only navigation, including `Tab`, `Shift-Tab`, arrow keys, and append-row at table end.
- 2026-03-19: Image drag/drop and document-mode image source editing now share relative-path resolution logic.
- 2026-03-19: HTML/PDF export now preserves semantic code block, table, quote, list, and local-image behavior more consistently, with regression coverage in renderer/export tests.
- 2026-03-19: Search replace, heading-section range analysis, task toggling, and folded-block visibility now have dedicated regression coverage for high-frequency editor flows.
- 2026-03-19: Added a `MarklyUITests` smoke path covering configured launch in document/source mode plus opening the find/replace sheet, using dedicated UI-test launch arguments and accessibility identifiers.
- 2026-03-19: Expanded `MarklyUITests` smoke coverage to include keyboard-based view-mode switching and replace-all flow wiring for the source editor/search sheet path.
- 2026-03-19: Added document-mode UI smoke coverage for task toggling and heading fold/unfold behavior, with stable accessibility identifiers for heading and task block actions.
- 2026-03-20: Expanded `MarklyUITests` with search result next/previous navigation status checks and block double-click edit/apply flow coverage in document mode.
- 2026-03-20: Existing links and images in document mode now support lower-interruption quick editing through inline popovers instead of always opening a sheet.
