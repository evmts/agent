const std = @import("std");
const testing = std.testing;

pub const YamlParserError = error{
    InvalidYaml,
    UnexpectedToken,
    IndentationError,
    UnterminatedString,
    InvalidEscape,
    RecursionLimit,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const YamlNodeType = enum {
    scalar,
    sequence,
    mapping,
    null_value,
};

pub const YamlNode = struct {
    type: YamlNodeType,
    value: union(YamlNodeType) {
        scalar: []const u8,
        sequence: []YamlNode,
        mapping: std.StringHashMap(YamlNode),
        null_value: void,
    },
    line: u32 = 0,
    column: u32 = 0,

    pub fn deinit(self: *YamlNode, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .scalar => |scalar| allocator.free(scalar),
            .sequence => |sequence| {
                for (sequence) |*node| {
                    node.deinit(allocator);
                }
                allocator.free(sequence);
            },
            .mapping => |*mapping| {
                var iterator = mapping.iterator();
                while (iterator.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                mapping.deinit();
            },
            .null_value => {},
        }
    }

    pub fn asString(self: *const YamlNode) ?[]const u8 {
        return switch (self.value) {
            .scalar => |scalar| scalar,
            else => null,
        };
    }

    pub fn asSequence(self: *const YamlNode) ?[]YamlNode {
        return switch (self.value) {
            .sequence => |sequence| sequence,
            else => null,
        };
    }

    pub fn asMapping(self: *const YamlNode) ?*const std.StringHashMap(YamlNode) {
        return switch (self.value) {
            .mapping => |*mapping| mapping,
            else => null,
        };
    }

    pub fn get(self: *const YamlNode, key: []const u8) ?*const YamlNode {
        return switch (self.value) {
            .mapping => |*mapping| mapping.getPtr(key),
            else => null,
        };
    }
};

pub const YamlDocument = struct {
    root: YamlNode,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *YamlDocument) void {
        self.root.deinit(self.allocator);
    }

    pub fn getNode(self: *const YamlDocument, path: []const u8) ?*const YamlNode {
        if (path.len == 0) return &self.root;
        
        const segments = std.mem.splitScalar(u8, path, '.');
        var current = &self.root;
        
        var segment_iter = segments;
        while (segment_iter.next()) |segment| {
            current = current.get(segment) orelse return null;
        }
        
        return current;
    }
};

const TokenType = enum {
    key,
    value,
    sequence_item,
    indent,
    dedent,
    newline,
    eof,
    colon,
    dash,
    string,
    number,
    boolean,
    null_token,
};

const Token = struct {
    type: TokenType,
    value: []const u8,
    line: u32,
    column: u32,
};

const Lexer = struct {
    input: []const u8,
    position: usize = 0,
    line: u32 = 1,
    column: u32 = 1,
    indent_stack: std.ArrayList(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Lexer {
        return Lexer{
            .input = input,
            .indent_stack = std.ArrayList(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.indent_stack.deinit();
    }

    fn currentChar(self: *const Lexer) ?u8 {
        if (self.position >= self.input.len) return null;
        return self.input[self.position];
    }

    fn advance(self: *Lexer) void {
        if (self.position < self.input.len) {
            if (self.input[self.position] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.position += 1;
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.currentChar()) |ch| {
            if (ch == ' ' or ch == '\t') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn skipToNextLine(self: *Lexer) void {
        while (self.currentChar()) |ch| {
            self.advance();
            if (ch == '\n') break;
        }
    }

    fn readString(self: *Lexer, quote_char: u8) ![]const u8 {
        const start = self.position;
        self.advance(); // Skip opening quote

        while (self.currentChar()) |ch| {
            if (ch == quote_char) {
                const content = self.input[start + 1..self.position];
                self.advance(); // Skip closing quote
                return try self.allocator.dupe(u8, content);
            } else if (ch == '\\') {
                // TODO: Handle escape sequences properly
                self.advance();
                if (self.currentChar() != null) {
                    self.advance();
                }
            } else {
                self.advance();
            }
        }

        return error.UnterminatedString;
    }

    fn readUnquotedString(self: *Lexer) ![]const u8 {
        const start = self.position;

        while (self.currentChar()) |ch| {
            if (ch == ':' or ch == '\n' or ch == '#' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
                break;
            }
            self.advance();
        }

        const content = std.mem.trim(u8, self.input[start..self.position], " \t\r");
        return try self.allocator.dupe(u8, content);
    }

    pub fn nextToken(self: *Lexer) !Token {
        // Handle comments
        if (self.currentChar() == '#') {
            self.skipToNextLine();
        }

        // Handle line beginnings and indentation
        if (self.position == 0 or (self.position > 0 and self.input[self.position - 1] == '\n')) {
            var indent_level: u32 = 0;
            while (self.currentChar()) |ch| {
                if (ch == ' ') {
                    indent_level += 1;
                    self.advance();
                } else if (ch == '\t') {
                    indent_level += 8; // Treat tab as 8 spaces
                    self.advance();
                } else {
                    break;
                }
            }

            // Handle empty lines
            if (self.currentChar() == null or self.currentChar() == '\n' or self.currentChar() == '#') {
                if (self.currentChar() == '\n') {
                    self.advance();
                }
                return Token{
                    .type = .newline,
                    .value = "",
                    .line = self.line,
                    .column = self.column,
                };
            }

            // Handle indentation changes
            const current_indent = if (self.indent_stack.items.len > 0) self.indent_stack.items[self.indent_stack.items.len - 1] else 0;
            
            if (indent_level > current_indent) {
                try self.indent_stack.append(indent_level);
                return Token{
                    .type = .indent,
                    .value = "",
                    .line = self.line,
                    .column = self.column,
                };
            } else if (indent_level < current_indent) {
                // May need multiple dedents
                while (self.indent_stack.items.len > 0 and self.indent_stack.items[self.indent_stack.items.len - 1] > indent_level) {
                    _ = self.indent_stack.pop();
                }
                return Token{
                    .type = .dedent,
                    .value = "",
                    .line = self.line,
                    .column = self.column,
                };
            }
        }

        self.skipWhitespace();

        const ch = self.currentChar() orelse {
            return Token{
                .type = .eof,
                .value = "",
                .line = self.line,
                .column = self.column,
            };
        };

        const token_line = self.line;
        const token_column = self.column;

        switch (ch) {
            ':' => {
                self.advance();
                return Token{
                    .type = .colon,
                    .value = ":",
                    .line = token_line,
                    .column = token_column,
                };
            },
            '-' => {
                // Check if this is a sequence item or part of a string
                const next_ch = if (self.position + 1 < self.input.len) self.input[self.position + 1] else 0;
                if (next_ch == ' ' or next_ch == '\t' or next_ch == '\n') {
                    self.advance();
                    return Token{
                        .type = .dash,
                        .value = "-",
                        .line = token_line,
                        .column = token_column,
                    };
                } else {
                    // Part of a string
                    const value = try self.readUnquotedString();
                    return Token{
                        .type = .string,
                        .value = value,
                        .line = token_line,
                        .column = token_column,
                    };
                }
            },
            '\n' => {
                self.advance();
                return Token{
                    .type = .newline,
                    .value = "\n",
                    .line = token_line,
                    .column = token_column,
                };
            },
            '"', '\'' => {
                const value = try self.readString(ch);
                return Token{
                    .type = .string,
                    .value = value,
                    .line = token_line,
                    .column = token_column,
                };
            },
            else => {
                const value = try self.readUnquotedString();
                
                // Determine token type based on value
                if (std.mem.eql(u8, value, "null") or std.mem.eql(u8, value, "~")) {
                    return Token{
                        .type = .null_token,
                        .value = value,
                        .line = token_line,
                        .column = token_column,
                    };
                } else if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) {
                    return Token{
                        .type = .boolean,
                        .value = value,
                        .line = token_line,
                        .column = token_column,
                    };
                } else if (std.fmt.parseInt(i64, value, 10)) |_| {
                    return Token{
                        .type = .number,
                        .value = value,
                        .line = token_line,
                        .column = token_column,
                    };
                } else |_| {
                    return Token{
                        .type = .string,
                        .value = value,
                        .line = token_line,
                        .column = token_column,
                    };
                }
            },
        }
    }
};

pub const YamlParser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    current_token: ?Token = null,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) YamlParser {
        return YamlParser{
            .allocator = allocator,
            .lexer = Lexer.init(allocator, input),
        };
    }

    pub fn deinit(self: *YamlParser) void {
        self.lexer.deinit();
    }

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !YamlDocument {
        var parser = YamlParser.init(allocator, content);
        defer parser.deinit();
        
        const root = try parser.parseDocument();
        
        return YamlDocument{
            .root = root,
            .allocator = allocator,
        };
    }

    fn nextToken(self: *YamlParser) !Token {
        if (self.current_token) |token| {
            self.current_token = null;
            return token;
        }
        return try self.lexer.nextToken();
    }

    fn peekToken(self: *YamlParser) !Token {
        if (self.current_token == null) {
            self.current_token = try self.lexer.nextToken();
        }
        return self.current_token.?;
    }

    fn parseDocument(self: *YamlParser) !YamlNode {
        // Skip any leading newlines
        var token = try self.peekToken();
        while (token.type == .newline) {
            _ = try self.nextToken();
            token = try self.peekToken();
        }

        if (token.type == .eof) {
            return YamlNode{
                .type = .null_value,
                .value = .{ .null_value = {} },
            };
        }

        return try self.parseValue();
    }

    fn parseValue(self: *YamlParser) YamlParserError!YamlNode {
        const token = try self.peekToken();
        
        switch (token.type) {
            .string => {
                const str_token = try self.nextToken();
                const next_token = try self.peekToken();
                
                if (next_token.type == .colon) {
                    // This is a mapping key
                    return try self.parseMapping(str_token.value);
                } else {
                    // This is a scalar value
                    return YamlNode{
                        .type = .scalar,
                        .value = .{ .scalar = str_token.value },
                        .line = str_token.line,
                        .column = str_token.column,
                    };
                }
            },
            .number => {
                const num_token = try self.nextToken();
                return YamlNode{
                    .type = .scalar,
                    .value = .{ .scalar = num_token.value },
                    .line = num_token.line,
                    .column = num_token.column,
                };
            },
            .boolean => {
                const bool_token = try self.nextToken();
                return YamlNode{
                    .type = .scalar,
                    .value = .{ .scalar = bool_token.value },
                    .line = bool_token.line,
                    .column = bool_token.column,
                };
            },
            .null_token => {
                const null_token = try self.nextToken();
                return YamlNode{
                    .type = .null_value,
                    .value = .{ .null_value = {} },
                    .line = null_token.line,
                    .column = null_token.column,
                };
            },
            .dash => {
                return try self.parseSequence();
            },
            .indent => {
                // Look ahead to see what's in the indented block
                _ = try self.nextToken(); // consume indent
                const next_token = try self.peekToken();
                
                if (next_token.type == .dash) {
                    return try self.parseSequence();
                } else {
                    return try self.parseMapping(null);
                }
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }

    fn parseMapping(self: *YamlParser, first_key: ?[]const u8) !YamlNode {
        var mapping = std.StringHashMap(YamlNode).init(self.allocator);
        errdefer {
            var iterator = mapping.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            mapping.deinit();
        }

        const line = self.lexer.line;
        const column = self.lexer.column;

        // Handle first key if provided
        if (first_key) |key| {
            _ = try self.nextToken(); // consume colon
            const value = try self.parseValue();
            try mapping.put(try self.allocator.dupe(u8, key), value);
        }

        // Parse additional key-value pairs
        while (true) {
            const token = try self.peekToken();
            
            if (token.type == .newline) {
                _ = try self.nextToken();
                continue;
            }
            
            if (token.type == .dedent or token.type == .eof) {
                break;
            }
            
            if (token.type == .string) {
                const key_token = try self.nextToken();
                const colon_token = try self.peekToken();
                
                if (colon_token.type != .colon) {
                    return error.UnexpectedToken;
                }
                
                _ = try self.nextToken(); // consume colon
                
                const value = try self.parseValue();
                try mapping.put(try self.allocator.dupe(u8, key_token.value), value);
            } else {
                break;
            }
        }

        return YamlNode{
            .type = .mapping,
            .value = .{ .mapping = mapping },
            .line = line,
            .column = column,
        };
    }

    fn parseSequence(self: *YamlParser) !YamlNode {
        var sequence = std.ArrayList(YamlNode).init(self.allocator);
        errdefer {
            for (sequence.items) |*node| {
                node.deinit(self.allocator);
            }
            sequence.deinit();
        }

        const line = self.lexer.line;
        const column = self.lexer.column;

        while (true) {
            const token = try self.peekToken();
            
            if (token.type == .newline) {
                _ = try self.nextToken();
                continue;
            }
            
            if (token.type != .dash) {
                break;
            }
            
            _ = try self.nextToken(); // consume dash
            
            const value = try self.parseValue();
            try sequence.append(value);
        }

        return YamlNode{
            .type = .sequence,
            .value = .{ .sequence = try sequence.toOwnedSlice() },
            .line = line,
            .column = column,
        };
    }
};

// Tests
test "parses simple scalar values" {
    const allocator = testing.allocator;
    
    const yaml = "hello";
    var doc = try YamlParser.parse(allocator, yaml);
    defer doc.deinit();
    
    try testing.expectEqual(YamlNodeType.scalar, doc.root.type);
    try testing.expectEqualStrings("hello", doc.root.asString().?);
}

test "parses simple mapping" {
    const allocator = testing.allocator;
    
    const yaml = 
        \\name: test
        \\version: 1
    ;
    
    var doc = try YamlParser.parse(allocator, yaml);
    defer doc.deinit();
    
    try testing.expectEqual(YamlNodeType.mapping, doc.root.type);
    
    const name_node = doc.root.get("name");
    try testing.expect(name_node != null);
    try testing.expectEqualStrings("test", name_node.?.asString().?);
    
    const version_node = doc.root.get("version");
    try testing.expect(version_node != null);
    try testing.expectEqualStrings("1", version_node.?.asString().?);
}

test "parses simple sequence" {
    const allocator = testing.allocator;
    
    const yaml = 
        \\- item1
        \\- item2
        \\- item3
    ;
    
    var doc = try YamlParser.parse(allocator, yaml);
    defer doc.deinit();
    
    try testing.expectEqual(YamlNodeType.sequence, doc.root.type);
    
    const sequence = doc.root.asSequence().?;
    try testing.expectEqual(@as(usize, 3), sequence.len);
    try testing.expectEqualStrings("item1", sequence[0].asString().?);
    try testing.expectEqualStrings("item2", sequence[1].asString().?);
    try testing.expectEqualStrings("item3", sequence[2].asString().?);
}

test "parses nested structures" {
    const allocator = testing.allocator;
    
    const yaml = 
        \\name: workflow
        \\jobs:
        \\  test:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - name: checkout
        \\        uses: actions/checkout@v4
        \\      - name: test
        \\        run: npm test
    ;
    
    var doc = try YamlParser.parse(allocator, yaml);
    defer doc.deinit();
    
    try testing.expectEqual(YamlNodeType.mapping, doc.root.type);
    
    const name = doc.getNode("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("workflow", name.?.asString().?);
    
    const jobs = doc.getNode("jobs");
    try testing.expect(jobs != null);
    try testing.expectEqual(YamlNodeType.mapping, jobs.?.type);
}