# Utils

Utility functions for text processing, file operations, and input handling.

## Files

| File | Purpose |
|------|---------|
| `wrap.zig` | Text wrapping and line height calculation |
| `mentions.zig` | File mention (@file) parsing and completion |
| `file_search.zig` | Fuzzy file search for autocomplete |

## Text Wrapping

Calculate line heights and wrap text to terminal width:

```zig
const wrap = @import("utils/wrap.zig");

// Calculate wrapped height
const height = wrap.wrapHeight("Long text...", 80);

// Wrap text into lines
const lines = try wrap.wrapText(allocator, "Long text...", 80);
defer lines.deinit();

for (lines.items) |line| {
    // Render each wrapped line
}
```

### Wrapping Algorithm

```
Input: "Hello world this is a long line"
Width: 10

Output:
┌──────────┐
│Hello     │
│world this│
│is a long │
│line      │
└──────────┘

Handles:
- UTF-8 characters (multi-byte)
- Newlines (\n)
- Word boundaries
- Zero-width and full-width chars
```

## File Mentions

Parse and autocomplete file mentions in messages:

```zig
const mentions = @import("utils/mentions.zig");

// Detect mentions in text
const has_mention = mentions.containsMention("Check @README.md");  // true

// Extract mention at cursor
const mention = mentions.extractMentionAtCursor(
    "Check @REA",
    9,  // cursor position
);
// mention = "REA"

// Complete mention
const files = mentions.findMatchingFiles(
    allocator,
    "REA",
    "/path/to/repo",
);
// files = ["README.md", "READABILITY.txt", ...]
```

### Mention Syntax

```
@filename          Match by filename
@path/to/file      Match by path
@*.zig            Match by extension (future)

Examples:
  "Check @README.md for docs"
  "See @src/main.zig"
  "Fix bug in @app.zig"
```

## File Search

Fuzzy search for files in a directory:

```zig
const file_search = @import("utils/file_search.zig");

// Search for files
const results = try file_search.fuzzySearch(
    allocator,
    "main",           // query
    "/path/to/repo",  // root directory
    10,               // max results
);
defer results.deinit();

for (results.items) |result| {
    std.debug.print("{s} (score: {})\n", .{
        result.path,
        result.score,
    });
}
```

### Search Algorithm

```
Query: "main"

Results (ranked by score):
1. main.zig           (exact match)
2. src/main.zig       (exact in subdir)
3. domain.zig         (contains 'main')
4. README.md          (weak match)

Score factors:
- Exact filename match: highest
- Substring match: high
- Character distance: medium
- Directory depth: penalty
```

## Usage in Widgets

### Composer with Mentions

```zig
// In composer widget
if (mentions.containsMention(state.input_buffer.items)) {
    const mention = mentions.extractMentionAtCursor(
        state.input_buffer.items,
        state.input_cursor,
    );

    if (mention) |m| {
        const files = try mentions.findMatchingFiles(
            allocator,
            m,
            state.working_directory,
        );

        // Show autocomplete dropdown with files
        try autocomplete.show(files);
    }
}
```

### Text Wrapping in Chat

```zig
// In chat_history widget
const message_height = wrap.wrapHeight(
    message.content,
    available_width,
);

const lines = try wrap.wrapText(
    ctx.arena,
    message.content,
    available_width,
);

for (lines.items, 0..) |line, i| {
    try surface.writeCell(0, i, line.text, STYLE);
}
```

## Testing

```bash
zig build test:tui

# Specific tests
zig test tui/utils/wrap.zig
zig test tui/utils/mentions.zig
```
