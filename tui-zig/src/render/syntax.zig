const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Tokenizer = tokenizer.Tokenizer;
const TokenType = tokenizer.TokenType;
const Token = tokenizer.Token;

/// Color indices for syntax highlighting (8-bit color palette)
pub const Colors = struct {
    pub const keyword: u8 = 12; // Blue
    pub const string: u8 = 10; // Green
    pub const number: u8 = 13; // Magenta
    pub const comment: u8 = 8; // Gray
    pub const function: u8 = 14; // Cyan
    pub const type: u8 = 11; // Yellow
    pub const operator: u8 = 7; // White
    pub const punctuation: u8 = 7; // White
    pub const identifier: u8 = 7; // White
};

/// A styled text segment for rendering
pub const StyledSegment = struct {
    text: []const u8,
    color: u8,
};

/// Language definitions with keywords and types
const zig_keywords = std.StaticStringMap(void).initComptime(.{
    .{"const"},  .{"var"},      .{"fn"},       .{"pub"},     .{"export"},
    .{"extern"}, .{"packed"},   .{"struct"},   .{"enum"},    .{"union"},
    .{"error"},  .{"return"},   .{"if"},       .{"else"},    .{"switch"},
    .{"while"},  .{"for"},      .{"break"},    .{"continue"}, .{"defer"},
    .{"errdefer"}, .{"try"},    .{"catch"},    .{"async"},   .{"await"},
    .{"suspend"}, .{"resume"},  .{"comptime"}, .{"inline"},  .{"noinline"},
    .{"asm"},    .{"volatile"}, .{"allowzero"}, .{"align"},  .{"linksection"},
    .{"callconv"}, .{"noalias"}, .{"threadlocal"}, .{"test"}, .{"and"},
    .{"or"},     .{"orelse"},   .{"unreachable"}, .{"usingnamespace"},
});

const zig_types = std.StaticStringMap(void).initComptime(.{
    .{"u8"},   .{"u16"},  .{"u32"},  .{"u64"},  .{"u128"},
    .{"i8"},   .{"i16"},  .{"i32"},  .{"i64"},  .{"i128"},
    .{"f16"},  .{"f32"},  .{"f64"},  .{"f80"},  .{"f128"},
    .{"bool"}, .{"void"}, .{"noreturn"}, .{"type"}, .{"anyerror"},
    .{"comptime_int"}, .{"comptime_float"}, .{"anytype"}, .{"anyopaque"},
    .{"c_char"}, .{"c_short"}, .{"c_int"}, .{"c_long"}, .{"c_longlong"},
    .{"c_uchar"}, .{"c_ushort"}, .{"c_uint"}, .{"c_ulong"}, .{"c_ulonglong"},
    .{"c_longdouble"}, .{"isize"}, .{"usize"},
});

const js_keywords = std.StaticStringMap(void).initComptime(.{
    .{"const"},    .{"let"},      .{"var"},      .{"function"}, .{"async"},
    .{"await"},    .{"class"},    .{"extends"},  .{"new"},      .{"this"},
    .{"super"},    .{"static"},   .{"return"},   .{"if"},       .{"else"},
    .{"switch"},   .{"case"},     .{"default"},  .{"for"},      .{"while"},
    .{"do"},       .{"break"},    .{"continue"}, .{"try"},      .{"catch"},
    .{"finally"},  .{"throw"},    .{"import"},   .{"export"},   .{"from"},
    .{"as"},       .{"typeof"},   .{"instanceof"}, .{"in"},     .{"of"},
    .{"delete"},   .{"void"},     .{"yield"},    .{"null"},     .{"undefined"},
    .{"true"},     .{"false"},    .{"debugger"}, .{"with"},
});

const ts_keywords = std.StaticStringMap(void).initComptime(.{
    // All JS keywords plus TypeScript-specific ones
    .{"const"},    .{"let"},      .{"var"},      .{"function"}, .{"async"},
    .{"await"},    .{"class"},    .{"extends"},  .{"new"},      .{"this"},
    .{"super"},    .{"static"},   .{"return"},   .{"if"},       .{"else"},
    .{"switch"},   .{"case"},     .{"default"},  .{"for"},      .{"while"},
    .{"do"},       .{"break"},    .{"continue"}, .{"try"},      .{"catch"},
    .{"finally"},  .{"throw"},    .{"import"},   .{"export"},   .{"from"},
    .{"as"},       .{"typeof"},   .{"instanceof"}, .{"in"},     .{"of"},
    .{"delete"},   .{"void"},     .{"yield"},    .{"null"},     .{"undefined"},
    .{"true"},     .{"false"},    .{"debugger"}, .{"with"},
    .{"interface"}, .{"type"},    .{"namespace"}, .{"enum"},    .{"implements"},
    .{"public"},   .{"private"},  .{"protected"}, .{"readonly"}, .{"abstract"},
    .{"declare"},  .{"is"},       .{"keyof"},    .{"infer"},    .{"never"},
    .{"unknown"},  .{"any"},
});

const ts_types = std.StaticStringMap(void).initComptime(.{
    .{"string"},   .{"number"},   .{"boolean"},  .{"object"},   .{"symbol"},
    .{"bigint"},   .{"any"},      .{"unknown"},  .{"never"},    .{"void"},
    .{"Array"},    .{"Promise"},  .{"Map"},      .{"Set"},      .{"Date"},
});

const python_keywords = std.StaticStringMap(void).initComptime(.{
    .{"def"},      .{"class"},    .{"if"},       .{"elif"},     .{"else"},
    .{"for"},      .{"while"},    .{"break"},    .{"continue"}, .{"return"},
    .{"try"},      .{"except"},   .{"finally"},  .{"raise"},    .{"with"},
    .{"as"},       .{"import"},   .{"from"},     .{"pass"},     .{"lambda"},
    .{"yield"},    .{"async"},    .{"await"},    .{"and"},      .{"or"},
    .{"not"},      .{"in"},       .{"is"},       .{"None"},     .{"True"},
    .{"False"},    .{"global"},   .{"nonlocal"}, .{"assert"},   .{"del"},
});

const python_types = std.StaticStringMap(void).initComptime(.{
    .{"int"},      .{"float"},    .{"str"},      .{"bool"},     .{"list"},
    .{"dict"},     .{"tuple"},    .{"set"},      .{"bytes"},    .{"bytearray"},
    .{"object"},   .{"type"},
});

const rust_keywords = std.StaticStringMap(void).initComptime(.{
    .{"fn"},       .{"let"},      .{"mut"},      .{"const"},    .{"static"},
    .{"struct"},   .{"enum"},     .{"union"},    .{"trait"},    .{"impl"},
    .{"type"},     .{"where"},    .{"pub"},      .{"mod"},      .{"use"},
    .{"as"},       .{"crate"},    .{"super"},    .{"self"},     .{"Self"},
    .{"extern"},   .{"if"},       .{"else"},     .{"match"},    .{"for"},
    .{"while"},    .{"loop"},     .{"break"},    .{"continue"}, .{"return"},
    .{"async"},    .{"await"},    .{"move"},     .{"ref"},      .{"unsafe"},
    .{"dyn"},      .{"box"},      .{"true"},     .{"false"},
});

const rust_types = std.StaticStringMap(void).initComptime(.{
    .{"u8"},   .{"u16"},  .{"u32"},  .{"u64"},  .{"u128"}, .{"usize"},
    .{"i8"},   .{"i16"},  .{"i32"},  .{"i64"},  .{"i128"}, .{"isize"},
    .{"f32"},  .{"f64"},  .{"bool"}, .{"char"}, .{"str"},
    .{"String"}, .{"Vec"}, .{"Option"}, .{"Result"}, .{"Box"},
});

const bash_keywords = std.StaticStringMap(void).initComptime(.{
    .{"if"},       .{"then"},     .{"else"},     .{"elif"},     .{"fi"},
    .{"case"},     .{"esac"},     .{"for"},      .{"while"},    .{"do"},
    .{"done"},     .{"function"}, .{"select"},   .{"until"},    .{"in"},
    .{"break"},    .{"continue"}, .{"return"},   .{"export"},   .{"local"},
    .{"readonly"}, .{"declare"},  .{"shift"},    .{"unset"},
});

/// Detect language from language identifier
pub fn detectLanguage(lang: []const u8) Language {
    if (std.mem.eql(u8, lang, "zig")) return .zig;
    if (std.mem.eql(u8, lang, "javascript") or std.mem.eql(u8, lang, "js")) return .javascript;
    if (std.mem.eql(u8, lang, "typescript") or std.mem.eql(u8, lang, "ts")) return .typescript;
    if (std.mem.eql(u8, lang, "python") or std.mem.eql(u8, lang, "py")) return .python;
    if (std.mem.eql(u8, lang, "rust") or std.mem.eql(u8, lang, "rs")) return .rust;
    if (std.mem.eql(u8, lang, "bash") or std.mem.eql(u8, lang, "sh")) return .bash;
    if (std.mem.eql(u8, lang, "json")) return .json;
    return .unknown;
}

pub const Language = enum {
    zig,
    javascript,
    typescript,
    python,
    rust,
    bash,
    json,
    unknown,
};

/// Highlight code and return styled segments
/// Caller owns the returned ArrayList
pub fn highlight(
    allocator: std.mem.Allocator,
    code: []const u8,
    lang: Language,
) !std.ArrayList(StyledSegment) {
    var segments = std.ArrayList(StyledSegment).init(allocator);
    errdefer segments.deinit();

    var tok = Tokenizer.init(code);

    // Set language-specific keywords and types
    switch (lang) {
        .zig => {
            tok.setKeywords(zig_keywords);
            tok.setTypes(zig_types);
        },
        .javascript => {
            tok.setKeywords(js_keywords);
        },
        .typescript => {
            tok.setKeywords(ts_keywords);
            tok.setTypes(ts_types);
        },
        .python => {
            tok.setKeywords(python_keywords);
            tok.setTypes(python_types);
        },
        .rust => {
            tok.setKeywords(rust_keywords);
            tok.setTypes(rust_types);
        },
        .bash => {
            tok.setKeywords(bash_keywords);
        },
        .json => {
            // JSON uses simple highlighting - just strings and numbers
        },
        .unknown => {
            // No keyword highlighting for unknown languages
        },
    }

    while (tok.next()) |token| {
        const color = colorForToken(token.type, lang);
        try segments.append(.{
            .text = token.text,
            .color = color,
        });
    }

    return segments;
}

fn colorForToken(token_type: TokenType, lang: Language) u8 {
    // JSON special handling - only highlight strings and numbers
    if (lang == .json) {
        return switch (token_type) {
            .string => Colors.string,
            .number => Colors.number,
            else => Colors.identifier,
        };
    }

    return switch (token_type) {
        .keyword => Colors.keyword,
        .string => Colors.string,
        .number => Colors.number,
        .comment => Colors.comment,
        .function => Colors.function,
        .type => Colors.type,
        .operator => Colors.operator,
        .punctuation => Colors.punctuation,
        .identifier => Colors.identifier,
        .whitespace => Colors.identifier, // No special color for whitespace
    };
}

test "highlight zig code" {
    const allocator = std.testing.allocator;
    const code = "const x: u32 = 42;";

    const segments = try highlight(allocator, code, .zig);
    defer segments.deinit();

    // Should have: const, space, x, :, space, u32, space, =, space, 42, ;
    try std.testing.expect(segments.items.len > 5);

    // First token should be 'const' keyword (blue)
    try std.testing.expectEqualStrings("const", segments.items[0].text);
    try std.testing.expectEqual(Colors.keyword, segments.items[0].color);
}

test "highlight javascript code" {
    const allocator = std.testing.allocator;
    const code = "const foo = \"hello\";";

    const segments = try highlight(allocator, code, .javascript);
    defer segments.deinit();

    try std.testing.expect(segments.items.len > 0);
}

test "highlight python code" {
    const allocator = std.testing.allocator;
    const code = "def hello():\n    return 42";

    const segments = try highlight(allocator, code, .python);
    defer segments.deinit();

    try std.testing.expect(segments.items.len > 0);
}

test "highlight with comments" {
    const allocator = std.testing.allocator;
    const code = "// comment\nconst x = 1;";

    const segments = try highlight(allocator, code, .zig);
    defer segments.deinit();

    // First segment should be comment
    try std.testing.expectEqual(Colors.comment, segments.items[0].color);
}

test "highlight strings" {
    const allocator = std.testing.allocator;
    const code = "\"hello world\"";

    const segments = try highlight(allocator, code, .zig);
    defer segments.deinit();

    try std.testing.expectEqual(@as(usize, 1), segments.items.len);
    try std.testing.expectEqual(Colors.string, segments.items[0].color);
}

test "highlight numbers" {
    const allocator = std.testing.allocator;
    const code = "42 3.14 0xFF";

    const segments = try highlight(allocator, code, .zig);
    defer segments.deinit();

    // Should find at least 3 number tokens
    var number_count: usize = 0;
    for (segments.items) |seg| {
        if (seg.color == Colors.number) {
            number_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), number_count);
}

test "detect language" {
    try std.testing.expectEqual(Language.zig, detectLanguage("zig"));
    try std.testing.expectEqual(Language.javascript, detectLanguage("javascript"));
    try std.testing.expectEqual(Language.javascript, detectLanguage("js"));
    try std.testing.expectEqual(Language.typescript, detectLanguage("typescript"));
    try std.testing.expectEqual(Language.typescript, detectLanguage("ts"));
    try std.testing.expectEqual(Language.python, detectLanguage("python"));
    try std.testing.expectEqual(Language.python, detectLanguage("py"));
    try std.testing.expectEqual(Language.rust, detectLanguage("rust"));
    try std.testing.expectEqual(Language.bash, detectLanguage("bash"));
    try std.testing.expectEqual(Language.bash, detectLanguage("sh"));
    try std.testing.expectEqual(Language.json, detectLanguage("json"));
    try std.testing.expectEqual(Language.unknown, detectLanguage("unknown"));
}
