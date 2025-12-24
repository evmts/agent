const std = @import("std");

/// Token types for syntax highlighting
pub const TokenType = enum {
    keyword,
    string,
    number,
    comment,
    function,
    type,
    operator,
    punctuation,
    identifier,
    whitespace,
};

/// A token with position and type information
pub const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,
    text: []const u8,
};

/// Generic tokenizer state
pub const Tokenizer = struct {
    source: []const u8,
    pos: usize = 0,
    keywords: ?std.StaticStringMap(void) = null,
    types: ?std.StaticStringMap(void) = null,

    pub fn init(source: []const u8) Tokenizer {
        return .{ .source = source };
    }

    pub fn setKeywords(self: *Tokenizer, keywords: std.StaticStringMap(void)) void {
        self.keywords = keywords;
    }

    pub fn setTypes(self: *Tokenizer, types: std.StaticStringMap(void)) void {
        self.types = types;
    }

    pub fn next(self: *Tokenizer) ?Token {
        if (self.pos >= self.source.len) return null;

        const start = self.pos;
        const c = self.source[self.pos];

        // Whitespace
        if (std.ascii.isWhitespace(c)) {
            while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
                self.pos += 1;
            }
            return Token{
                .type = .whitespace,
                .start = start,
                .end = self.pos,
                .text = self.source[start..self.pos],
            };
        }

        // Line comments: // and #
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            return self.tokenizeLineComment("//");
        }
        if (c == '#') {
            return self.tokenizeLineComment("#");
        }

        // Block comments: /* */
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
            return self.tokenizeBlockComment();
        }

        // Strings
        if (c == '"' or c == '\'' or c == '`') {
            return self.tokenizeString(c);
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            return self.tokenizeNumber();
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.tokenizeIdentifier();
        }

        // Operators and punctuation
        return self.tokenizeOperatorOrPunctuation();
    }

    fn tokenizeLineComment(self: *Tokenizer, prefix: []const u8) Token {
        const start = self.pos;
        self.pos += prefix.len;

        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }

        return Token{
            .type = .comment,
            .start = start,
            .end = self.pos,
            .text = self.source[start..self.pos],
        };
    }

    fn tokenizeBlockComment(self: *Tokenizer) Token {
        const start = self.pos;
        self.pos += 2; // Skip /*

        while (self.pos + 1 < self.source.len) {
            if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                self.pos += 2;
                break;
            }
            self.pos += 1;
        }

        return Token{
            .type = .comment,
            .start = start,
            .end = self.pos,
            .text = self.source[start..self.pos],
        };
    }

    fn tokenizeString(self: *Tokenizer, quote: u8) Token {
        const start = self.pos;
        self.pos += 1; // Skip opening quote

        var escaped = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == quote) {
                self.pos += 1;
                break;
            }
            self.pos += 1;
        }

        return Token{
            .type = .string,
            .start = start,
            .end = self.pos,
            .text = self.source[start..self.pos],
        };
    }

    fn tokenizeNumber(self: *Tokenizer) Token {
        const start = self.pos;

        // Handle hex numbers (0x...)
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            if (next == 'x' or next == 'X') {
                self.pos += 2;
                while (self.pos < self.source.len and std.ascii.isHex(self.source[self.pos])) {
                    self.pos += 1;
                }
                return Token{
                    .type = .number,
                    .start = start,
                    .end = self.pos,
                    .text = self.source[start..self.pos],
                };
            }
        }

        // Regular numbers
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }

        // Decimal point
        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
        }

        // Scientific notation
        if (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == 'e' or c == 'E') {
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                }
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.pos += 1;
                }
            }
        }

        return Token{
            .type = .number,
            .start = start,
            .end = self.pos,
            .text = self.source[start..self.pos],
        };
    }

    fn tokenizeIdentifier(self: *Tokenizer) Token {
        const start = self.pos;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const text = self.source[start..self.pos];

        // Check if it's a keyword
        if (self.keywords) |keywords| {
            if (keywords.has(text)) {
                return Token{
                    .type = .keyword,
                    .start = start,
                    .end = self.pos,
                    .text = text,
                };
            }
        }

        // Check if it's a type
        if (self.types) |types| {
            if (types.has(text)) {
                return Token{
                    .type = .type,
                    .start = start,
                    .end = self.pos,
                    .text = text,
                };
            }
        }

        // Check if next char is '(' - likely a function
        if (self.pos < self.source.len and self.source[self.pos] == '(') {
            return Token{
                .type = .function,
                .start = start,
                .end = self.pos,
                .text = text,
            };
        }

        return Token{
            .type = .identifier,
            .start = start,
            .end = self.pos,
            .text = text,
        };
    }

    fn tokenizeOperatorOrPunctuation(self: *Tokenizer) Token {
        const start = self.pos;
        const c = self.source[self.pos];
        self.pos += 1;

        // Multi-character operators
        if (self.pos < self.source.len) {
            const next = self.source[self.pos];
            const two_char = [2]u8{ c, next };

            // Check common two-character operators
            if (std.mem.eql(u8, &two_char, "==") or
                std.mem.eql(u8, &two_char, "!=") or
                std.mem.eql(u8, &two_char, "<=") or
                std.mem.eql(u8, &two_char, ">=") or
                std.mem.eql(u8, &two_char, "&&") or
                std.mem.eql(u8, &two_char, "||") or
                std.mem.eql(u8, &two_char, "<<") or
                std.mem.eql(u8, &two_char, ">>") or
                std.mem.eql(u8, &two_char, "++") or
                std.mem.eql(u8, &two_char, "--") or
                std.mem.eql(u8, &two_char, "+=") or
                std.mem.eql(u8, &two_char, "-=") or
                std.mem.eql(u8, &two_char, "*=") or
                std.mem.eql(u8, &two_char, "/=") or
                std.mem.eql(u8, &two_char, "->") or
                std.mem.eql(u8, &two_char, "=>"))
            {
                self.pos += 1;
            }
        }

        const token_type: TokenType = switch (c) {
            '+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~' => .operator,
            else => .punctuation,
        };

        return Token{
            .type = token_type,
            .start = start,
            .end = self.pos,
            .text = self.source[start..self.pos],
        };
    }
};

test "tokenize basic tokens" {
    var tokenizer = Tokenizer.init("hello world");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.identifier, t1.type);
    try std.testing.expectEqualStrings("hello", t1.text);

    const t2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.whitespace, t2.type);

    const t3 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.identifier, t3.type);
    try std.testing.expectEqualStrings("world", t3.text);
}

test "tokenize strings" {
    var tokenizer = Tokenizer.init("\"hello\" 'world'");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.string, t1.type);
    try std.testing.expectEqualStrings("\"hello\"", t1.text);

    _ = tokenizer.next(); // whitespace

    const t2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.string, t2.type);
    try std.testing.expectEqualStrings("'world'", t2.text);
}

test "tokenize numbers" {
    var tokenizer = Tokenizer.init("123 3.14 0xFF");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.number, t1.type);
    try std.testing.expectEqualStrings("123", t1.text);

    _ = tokenizer.next(); // whitespace

    const t2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.number, t2.type);
    try std.testing.expectEqualStrings("3.14", t2.text);

    _ = tokenizer.next(); // whitespace

    const t3 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.number, t3.type);
    try std.testing.expectEqualStrings("0xFF", t3.text);
}

test "tokenize comments" {
    var tokenizer = Tokenizer.init("// comment\n# another");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.comment, t1.type);
    try std.testing.expectEqualStrings("// comment", t1.text);

    _ = tokenizer.next(); // newline

    const t2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.comment, t2.type);
    try std.testing.expectEqualStrings("# another", t2.text);
}

test "tokenize block comment" {
    var tokenizer = Tokenizer.init("/* block\ncomment */");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.comment, t1.type);
    try std.testing.expectEqualStrings("/* block\ncomment */", t1.text);
}

test "tokenize operators" {
    var tokenizer = Tokenizer.init("+ == && ->");

    const t1 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.operator, t1.type);
    try std.testing.expectEqualStrings("+", t1.text);

    _ = tokenizer.next(); // whitespace

    const t2 = tokenizer.next().?;
    try std.testing.expectEqual(TokenType.operator, t2.type);
    try std.testing.expectEqualStrings("==", t2.text);
}
