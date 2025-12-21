# Render Module

This module contains rendering utilities for the Plue TUI.

## Diff Renderer

The diff renderer provides parsing and rendering of unified diff format (git diff output).

### Files

- `diff.zig` - Diff parser and data structures
- `diff_widget.zig` - Widget for rendering diffs in the TUI

### Usage

#### Parsing a Diff

```zig
const diff_module = @import("render/diff.zig");

// Parse unified diff text
var diff = try diff_module.parse(allocator, diff_text);
defer diff.deinit();

// Get statistics
const stats = diff.getStats();
std.debug.print("Added: {d}, Deleted: {d}\n", .{stats.additions, stats.deletions});
```

#### Rendering in TUI

```zig
const DiffWidget = @import("render/diff_widget.zig").DiffWidget;

// Create widget
var widget = DiffWidget.init(&diff);

// Calculate height needed
const height = widget.height(width);

// Draw to surface
widget.draw(surface, start_row, width);
```

### Data Structures

#### `Diff`
- `old_file: ?[]const u8` - Path to old file (null if new file)
- `new_file: ?[]const u8` - Path to new file (null if deleted file)
- `hunks: ArrayList(Hunk)` - List of hunks in the diff

#### `Hunk`
- `old_start: u32` - Starting line in old file
- `old_count: u32` - Number of lines in old file
- `new_start: u32` - Starting line in new file
- `new_count: u32` - Number of lines in new file
- `lines: ArrayList(Line)` - Lines in this hunk

#### `Line`
- `kind: Kind` - Type of line (context, addition, deletion, header)
- `content: []const u8` - Line content (without prefix)

### Color Scheme

The diff widget uses the following colors:

| Element | Color Index | Color |
|---------|-------------|-------|
| Addition | 10 | Green |
| Deletion | 9 | Red |
| Context | 7 | White |
| Header | 14 | Cyan |
| Line Number | 8 | Gray |
| File Path | 12 | Blue |

### Diff Format Support

The parser supports:

- ✅ Unified diff format (`git diff`)
- ✅ Multiple hunks per file
- ✅ New files (`/dev/null` → file)
- ✅ Deleted files (file → `/dev/null`)
- ✅ Modified files
- ✅ Context lines
- ✅ Empty lines in diff
- ✅ Line number ranges with or without count
- ✅ Binary file markers

### Testing

Run tests with:

```bash
cd /Users/williamcory/plue/tui-zig
zig build test
```

Tests are located in:
- `src/render/diff.zig` - Inline tests for parser
- `src/render/diff_widget.zig` - Inline tests for widget
- `tests/diff_test.zig` - Comprehensive test suite

### Example

See `examples/diff_example.zig` for a complete example of parsing and inspecting a diff.

### Integration with TUI

To integrate diff rendering into chat history:

1. Parse tool results that contain diffs
2. Create a `DiffWidget` for each diff
3. Render as part of the tool call result display
4. Use syntax highlighting for code within diff lines (future enhancement)
