# 10: Syntax Highlighting

## Goal

Implement syntax highlighting for code blocks in markdown and file content displays.

## Context

- Code blocks in assistant messages need highlighting
- Tool results showing file content need highlighting
- Support common languages: JavaScript/TypeScript, Python, Rust, Zig, Go, JSON, YAML, Bash
- Reference: codex uses tree-sitter-highlight

## Approach

Use regex-based highlighting (simpler than tree-sitter, but effective for terminal display):

1. Tokenize by language patterns
2. Apply colors to token types
3. Return styled segments

## Tasks

### 1. Create Highlighter Core (src/render/syntax.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");

pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SyntaxHighlighter {
        return .{ .allocator = allocator };
    }

    /// Highlight code and return styled segments
    pub fn highlight(self: *SyntaxHighlighter, code: []const u8, language: ?[]const u8) ![]Segment {
        const lang = detectLanguage(language, code);

        return switch (lang) {
            .javascript, .typescript => self.highlightJS(code),
            .python => self.highlightPython(code),
            .rust => self.highlightRust(code),
            .zig => self.highlightZig(code),
            .go => self.highlightGo(code),
            .json => self.highlightJSON(code),
            .yaml => self.highlightYAML(code),
            .bash, .shell => self.highlightBash(code),
            .unknown => self.highlightPlain(code),
        };
    }

    fn highlightJS(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "const", "let", "var", "function", "return", "if", "else",
            "for", "while", "do", "switch", "case", "break", "continue",
            "try", "catch", "finally", "throw", "new", "delete", "typeof",
            "instanceof", "class", "extends", "import", "export", "default",
            "async", "await", "yield", "static", "get", "set", "true", "false",
            "null", "undefined", "this", "super",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },      // Magenta
            .string = .{ .fg = .{ .index = 10 } },       // Green
            .number = .{ .fg = .{ .index = 14 } },       // Cyan
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .function = .{ .fg = .{ .index = 12 } },     // Blue
            .operator = .{ .fg = .{ .index = 7 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightPython(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "def", "class", "if", "elif", "else", "for", "while", "try",
            "except", "finally", "with", "as", "import", "from", "return",
            "yield", "raise", "pass", "break", "continue", "and", "or", "not",
            "in", "is", "None", "True", "False", "lambda", "global", "nonlocal",
            "async", "await",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },
            .string = .{ .fg = .{ .index = 10 } },
            .number = .{ .fg = .{ .index = 14 } },
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .function = .{ .fg = .{ .index = 12 } },
            .decorator = .{ .fg = .{ .index = 11 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightRust(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "fn", "let", "mut", "const", "static", "struct", "enum", "impl",
            "trait", "type", "pub", "crate", "mod", "use", "as", "if", "else",
            "match", "for", "while", "loop", "return", "break", "continue",
            "move", "ref", "self", "Self", "where", "async", "await", "dyn",
            "true", "false", "Some", "None", "Ok", "Err",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },
            .string = .{ .fg = .{ .index = 10 } },
            .number = .{ .fg = .{ .index = 14 } },
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .function = .{ .fg = .{ .index = 12 } },
            .type = .{ .fg = .{ .index = 11 } },
            .lifetime = .{ .fg = .{ .index = 9 } },
            .macro = .{ .fg = .{ .index = 14 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightZig(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "const", "var", "fn", "pub", "return", "if", "else", "while",
            "for", "break", "continue", "switch", "orelse", "catch", "try",
            "defer", "errdefer", "error", "unreachable", "undefined", "null",
            "true", "false", "and", "or", "struct", "enum", "union", "test",
            "comptime", "inline", "extern", "export", "align", "packed",
            "async", "await", "suspend", "resume", "nosuspend", "threadlocal",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },
            .string = .{ .fg = .{ .index = 10 } },
            .number = .{ .fg = .{ .index = 14 } },
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .function = .{ .fg = .{ .index = 12 } },
            .builtin = .{ .fg = .{ .index = 11 } },
            .type = .{ .fg = .{ .index = 14 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightGo(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "package", "import", "func", "var", "const", "type", "struct",
            "interface", "map", "chan", "if", "else", "for", "range", "switch",
            "case", "default", "break", "continue", "return", "go", "defer",
            "select", "fallthrough", "goto", "true", "false", "nil", "iota",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },
            .string = .{ .fg = .{ .index = 10 } },
            .number = .{ .fg = .{ .index = 14 } },
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .function = .{ .fg = .{ .index = 12 } },
            .type = .{ .fg = .{ .index = 11 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightJSON(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        var i: usize = 0;
        while (i < code.len) {
            const char = code[i];

            // String (key or value)
            if (char == '"') {
                const start = i;
                i += 1;
                while (i < code.len and code[i] != '"') : (i += 1) {
                    if (code[i] == '\\' and i + 1 < code.len) i += 1;
                }
                i += 1;

                // Check if key (followed by :)
                var j = i;
                while (j < code.len and (code[j] == ' ' or code[j] == '\t')) : (j += 1) {}
                const is_key = j < code.len and code[j] == ':';

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, code[start..i]),
                    .style = if (is_key) .{ .fg = .{ .index = 12 } } else .{ .fg = .{ .index = 10 } },
                });
                continue;
            }

            // Numbers
            if (char >= '0' and char <= '9' or char == '-') {
                const start = i;
                while (i < code.len and (code[i] >= '0' and code[i] <= '9' or
                    code[i] == '.' or code[i] == 'e' or code[i] == 'E' or
                    code[i] == '+' or code[i] == '-')) : (i += 1)
                {}

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, code[start..i]),
                    .style = .{ .fg = .{ .index = 14 } },
                });
                continue;
            }

            // Booleans and null
            if (std.mem.startsWith(u8, code[i..], "true") or
                std.mem.startsWith(u8, code[i..], "false") or
                std.mem.startsWith(u8, code[i..], "null"))
            {
                const word = if (std.mem.startsWith(u8, code[i..], "true")) "true" else if (std.mem.startsWith(u8, code[i..], "false")) "false" else "null";

                try segments.append(.{
                    .text = word,
                    .style = .{ .fg = .{ .index = 13 } },
                });
                i += word.len;
                continue;
            }

            // Default
            try segments.append(.{
                .text = try self.allocator.dupe(u8, code[i .. i + 1]),
                .style = .{},
            });
            i += 1;
        }

        return segments.toOwnedSlice();
    }

    fn highlightYAML(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        var lines = std.mem.split(u8, code, "\n");
        var first_line = true;

        while (lines.next()) |line| {
            if (!first_line) {
                try segments.append(.{ .text = "\n", .style = .{} });
            }
            first_line = false;

            // Comments
            if (std.mem.startsWith(u8, std.mem.trim(u8, line, " "), "#")) {
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, line),
                    .style = .{ .fg = .{ .index = 8 }, .italic = true },
                });
                continue;
            }

            // Key: value
            if (std.mem.indexOf(u8, line, ":")) |colon_idx| {
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, line[0 .. colon_idx + 1]),
                    .style = .{ .fg = .{ .index = 12 } },
                });
                if (colon_idx + 1 < line.len) {
                    try segments.append(.{
                        .text = try self.allocator.dupe(u8, line[colon_idx + 1 ..]),
                        .style = .{ .fg = .{ .index = 10 } },
                    });
                }
                continue;
            }

            // List items
            if (std.mem.startsWith(u8, std.mem.trim(u8, line, " "), "- ")) {
                const dash_idx = std.mem.indexOf(u8, line, "-").?;
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, line[0 .. dash_idx + 1]),
                    .style = .{ .fg = .{ .index = 8 } },
                });
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, line[dash_idx + 1 ..]),
                    .style = .{},
                });
                continue;
            }

            try segments.append(.{
                .text = try self.allocator.dupe(u8, line),
                .style = .{},
            });
        }

        return segments.toOwnedSlice();
    }

    fn highlightBash(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = std.ArrayList(Segment).init(self.allocator);

        const keywords = [_][]const u8{
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "while",
            "do", "done", "in", "function", "return", "exit", "local", "export",
            "readonly", "unset", "shift", "source", "true", "false",
        };

        try self.tokenize(&segments, code, &keywords, .{
            .keyword = .{ .fg = .{ .index = 13 } },
            .string = .{ .fg = .{ .index = 10 } },
            .number = .{ .fg = .{ .index = 14 } },
            .comment = .{ .fg = .{ .index = 8 }, .italic = true },
            .variable = .{ .fg = .{ .index = 14 } },
            .command = .{ .fg = .{ .index = 12 } },
        });

        return segments.toOwnedSlice();
    }

    fn highlightPlain(self: *SyntaxHighlighter, code: []const u8) ![]Segment {
        var segments = try self.allocator.alloc(Segment, 1);
        segments[0] = .{
            .text = try self.allocator.dupe(u8, code),
            .style = .{},
        };
        return segments;
    }

    const TokenStyles = struct {
        keyword: vaxis.Cell.Style = .{},
        string: vaxis.Cell.Style = .{},
        number: vaxis.Cell.Style = .{},
        comment: vaxis.Cell.Style = .{},
        function: vaxis.Cell.Style = .{},
        type: vaxis.Cell.Style = .{},
        operator: vaxis.Cell.Style = .{},
        variable: vaxis.Cell.Style = .{},
        decorator: vaxis.Cell.Style = .{},
        builtin: vaxis.Cell.Style = .{},
        lifetime: vaxis.Cell.Style = .{},
        macro: vaxis.Cell.Style = .{},
        command: vaxis.Cell.Style = .{},
    };

    fn tokenize(
        self: *SyntaxHighlighter,
        segments: *std.ArrayList(Segment),
        code: []const u8,
        keywords: []const []const u8,
        styles: TokenStyles,
    ) !void {
        var i: usize = 0;

        while (i < code.len) {
            const char = code[i];

            // Comments (// and #)
            if ((char == '/' and i + 1 < code.len and code[i + 1] == '/') or
                char == '#')
            {
                const start = i;
                while (i < code.len and code[i] != '\n') : (i += 1) {}
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, code[start..i]),
                    .style = styles.comment,
                });
                continue;
            }

            // Strings
            if (char == '"' or char == '\'' or char == '`') {
                const quote = char;
                const start = i;
                i += 1;
                while (i < code.len and code[i] != quote) : (i += 1) {
                    if (code[i] == '\\' and i + 1 < code.len) i += 1;
                }
                i += 1;
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, code[start..@min(i, code.len)]),
                    .style = styles.string,
                });
                continue;
            }

            // Numbers
            if (char >= '0' and char <= '9') {
                const start = i;
                while (i < code.len and ((code[i] >= '0' and code[i] <= '9') or
                    code[i] == '.' or code[i] == 'x' or code[i] == 'X' or
                    (code[i] >= 'a' and code[i] <= 'f') or
                    (code[i] >= 'A' and code[i] <= 'F'))) : (i += 1)
                {}
                try segments.append(.{
                    .text = try self.allocator.dupe(u8, code[start..i]),
                    .style = styles.number,
                });
                continue;
            }

            // Identifiers and keywords
            if (isIdentifierStart(char)) {
                const start = i;
                while (i < code.len and isIdentifierChar(code[i])) : (i += 1) {}
                const word = code[start..i];

                var is_keyword = false;
                for (keywords) |kw| {
                    if (std.mem.eql(u8, word, kw)) {
                        is_keyword = true;
                        break;
                    }
                }

                try segments.append(.{
                    .text = try self.allocator.dupe(u8, word),
                    .style = if (is_keyword) styles.keyword else .{},
                });
                continue;
            }

            // Default: single character
            try segments.append(.{
                .text = try self.allocator.dupe(u8, code[i .. i + 1]),
                .style = .{},
            });
            i += 1;
        }
    }

    fn isIdentifierStart(char: u8) bool {
        return (char >= 'a' and char <= 'z') or
            (char >= 'A' and char <= 'Z') or
            char == '_' or char == '@';
    }

    fn isIdentifierChar(char: u8) bool {
        return isIdentifierStart(char) or (char >= '0' and char <= '9');
    }
};

pub const Segment = struct {
    text: []const u8,
    style: vaxis.Cell.Style = .{},
};

pub const Language = enum {
    javascript,
    typescript,
    python,
    rust,
    zig,
    go,
    json,
    yaml,
    bash,
    shell,
    unknown,
};

fn detectLanguage(hint: ?[]const u8, code: []const u8) Language {
    if (hint) |h| {
        if (std.mem.eql(u8, h, "js") or std.mem.eql(u8, h, "javascript")) return .javascript;
        if (std.mem.eql(u8, h, "ts") or std.mem.eql(u8, h, "typescript")) return .typescript;
        if (std.mem.eql(u8, h, "py") or std.mem.eql(u8, h, "python")) return .python;
        if (std.mem.eql(u8, h, "rs") or std.mem.eql(u8, h, "rust")) return .rust;
        if (std.mem.eql(u8, h, "zig")) return .zig;
        if (std.mem.eql(u8, h, "go") or std.mem.eql(u8, h, "golang")) return .go;
        if (std.mem.eql(u8, h, "json")) return .json;
        if (std.mem.eql(u8, h, "yaml") or std.mem.eql(u8, h, "yml")) return .yaml;
        if (std.mem.eql(u8, h, "bash") or std.mem.eql(u8, h, "sh") or std.mem.eql(u8, h, "shell")) return .bash;
    }

    // Try to detect from content
    if (std.mem.indexOf(u8, code, "fn main()") != null and std.mem.indexOf(u8, code, "::") != null) return .rust;
    if (std.mem.indexOf(u8, code, "package ") != null and std.mem.indexOf(u8, code, "func ") != null) return .go;
    if (std.mem.indexOf(u8, code, "const std = @import") != null) return .zig;
    if (std.mem.startsWith(u8, std.mem.trim(u8, code, " \n"), "{") or
        std.mem.startsWith(u8, std.mem.trim(u8, code, " \n"), "["))
    {
        return .json;
    }
    if (std.mem.startsWith(u8, code, "#!/bin/bash") or std.mem.startsWith(u8, code, "#!/bin/sh")) return .bash;

    return .unknown;
}
```

## Acceptance Criteria

- [ ] JavaScript/TypeScript keywords highlighted
- [ ] Python keywords and decorators highlighted
- [ ] Rust lifetimes, macros, types highlighted
- [ ] Zig builtins and types highlighted
- [ ] Go packages and types highlighted
- [ ] JSON keys vs values distinguished
- [ ] YAML keys and comments highlighted
- [ ] Bash commands and variables highlighted
- [ ] Strings in all languages highlighted
- [ ] Comments in all languages highlighted (italic)
- [ ] Numbers highlighted
- [ ] Language auto-detection works
- [ ] Unknown languages render as plain text

## Files to Create

1. `tui-zig/src/render/syntax.zig`

## Next

Proceed to `11_diff_renderer.md` for unified diff visualization.
