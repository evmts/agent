# Syntax Highlighting Implementation

This directory contains a complete syntax highlighting system for code blocks in the TUI.

## Architecture

The syntax highlighting system consists of three main components:

### 1. Tokenizer (`tokenizer.zig`)

A generic tokenizer that breaks source code into tokens:

- **Token Types**: keyword, string, number, comment, function, type, operator, punctuation, identifier, whitespace
- **Features**:
  - String detection (single, double, and backtick quotes)
  - Comment detection (`//`, `/* */`, `#`)
  - Number detection (integers, floats, hex, scientific notation)
  - Operator and punctuation detection
  - Context-aware identifier classification

**Example**:
```zig
var tok = Tokenizer.init("const x: u32 = 42;");
tok.setKeywords(zig_keywords);
tok.setTypes(zig_types);

while (tok.next()) |token| {
    // Process token
    std.debug.print("{s}: {s}\n", .{@tagName(token.type), token.text});
}
```

### 2. Syntax Highlighter (`syntax.zig`)

Language-specific syntax highlighting using the tokenizer:

- **Supported Languages**:
  - Zig
  - JavaScript/TypeScript
  - Python
  - Rust
  - Bash/Shell
  - JSON
  - Unknown (fallback with basic highlighting)

- **Color Scheme**:
  - Keywords: Blue (12)
  - Strings: Green (10)
  - Numbers: Magenta (13)
  - Comments: Gray (8)
  - Functions: Cyan (14)
  - Types: Yellow (11)
  - Operators/Punctuation: White (7)

**Example**:
```zig
const code = "const x: u32 = 42;";
const segments = try syntax.highlight(allocator, code, .zig);
defer segments.deinit();

for (segments.items) |seg| {
    // seg.text contains the token text
    // seg.color contains the color index
}
```

### 3. Markdown Integration (`markdown.zig`)

Automatic syntax highlighting for markdown code blocks:

- Detects language from fence markers (e.g., ` ```zig`)
- Applies syntax highlighting to code block content
- Integrates seamlessly with other markdown features

**Example**:
```zig
var renderer = MarkdownRenderer.init(allocator);
const segments = try renderer.render(
    \\```zig
    \\const x: u32 = 42;
    \\```
);
defer allocator.free(segments);
```

## Language Definitions

Each language has its own keyword and type definitions:

### Zig
- **Keywords**: `const`, `var`, `fn`, `pub`, `return`, `if`, `else`, `while`, `for`, etc.
- **Types**: `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, `bool`, `void`, etc.

### JavaScript
- **Keywords**: `const`, `let`, `var`, `function`, `async`, `await`, `class`, `return`, etc.

### TypeScript
- **Keywords**: All JS keywords + `interface`, `type`, `namespace`, `enum`, `implements`, etc.
- **Types**: `string`, `number`, `boolean`, `any`, `unknown`, `never`, etc.

### Python
- **Keywords**: `def`, `class`, `if`, `elif`, `else`, `for`, `while`, `return`, `import`, etc.
- **Types**: `int`, `float`, `str`, `bool`, `list`, `dict`, `tuple`, etc.

### Rust
- **Keywords**: `fn`, `let`, `mut`, `const`, `struct`, `enum`, `impl`, `trait`, etc.
- **Types**: `u8`, `u16`, `u32`, `i8`, `i16`, `i32`, `bool`, `String`, `Vec`, etc.

### Bash
- **Keywords**: `if`, `then`, `else`, `for`, `while`, `do`, `function`, etc.

### JSON
- Special handling: only highlights strings and numbers

## Testing

Comprehensive test coverage in:
- `tests/syntax_test.zig` - Core syntax highlighting tests
- `tests/markdown_syntax_test.zig` - Markdown integration tests

Run tests:
```bash
cd /Users/williamcory/plue/tui-zig
zig build test
```

## Implementation Details

### Tokenization Strategy

The tokenizer uses a simple state machine approach:

1. **Whitespace**: Consumed in bulk
2. **Comments**: Line (`//`, `#`) and block (`/* */`) comments
3. **Strings**: Handles escape sequences and different quote types
4. **Numbers**: Integers, floats, hex (0x), scientific notation
5. **Identifiers**: Checked against keyword/type maps
6. **Operators**: Single and multi-character operators

### Performance Considerations

- **StaticStringMap**: Used for O(1) keyword lookups at compile time
- **Single-pass**: Tokenization happens in one pass through the source
- **No Regex**: Uses simple character-by-character parsing for speed
- **Memory Efficient**: Tokens reference original source string (no copies)

### Limitations

This is a **simple pattern-based highlighter**, not a full parser:

- No context-aware highlighting (e.g., variable names after declarations)
- No semantic analysis
- Basic function detection (only when followed by `(`)
- Approximate 90% accuracy - good enough for visual distinction

For more accurate highlighting, consider integrating tree-sitter in the future.

## Future Enhancements

Potential improvements:

1. **More Languages**: Add support for Go, C, C++, Java, etc.
2. **Tree-sitter Integration**: For semantic highlighting
3. **Theme Support**: Customizable color schemes
4. **Bracket Matching**: Highlight matching brackets
5. **Error Highlighting**: Detect and highlight syntax errors
6. **Semantic Tokens**: Variable/function name tracking

## Usage in TUI

The syntax highlighting is automatically applied to all markdown code blocks
rendered in the TUI. No additional configuration needed.

When the markdown renderer encounters:

\`\`\`zig
const x: u32 = 42;
\`\`\`

It will automatically:
1. Detect the language (`zig`)
2. Tokenize the code
3. Apply appropriate colors
4. Render with indentation

## Color Reference

| Token Type | Color | Index | Usage |
|------------|-------|-------|-------|
| Keyword | Blue | 12 | `const`, `fn`, `if`, `return` |
| String | Green | 10 | `"hello"`, `'world'` |
| Number | Magenta | 13 | `42`, `3.14`, `0xFF` |
| Comment | Gray | 8 | `// comment`, `/* block */` |
| Function | Cyan | 14 | `main`, `println` |
| Type | Yellow | 11 | `u32`, `String`, `int` |
| Operator | White | 7 | `+`, `==`, `->` |
| Punctuation | White | 7 | `{`, `}`, `;` |

## Examples

See `examples/syntax_demo.zig` for a standalone demo of the syntax highlighting system.
