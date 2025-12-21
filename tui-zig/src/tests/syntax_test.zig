const std = @import("std");
const syntax = @import("../render/syntax.zig");
const tokenizer = @import("../render/tokenizer.zig");

test "tokenize zig keywords" {
    var tok = tokenizer.Tokenizer.init("const fn pub return");
    tok.setKeywords(syntax.zig_keywords);

    const t1 = tok.next().?;
    try std.testing.expectEqual(tokenizer.TokenType.keyword, t1.type);
    try std.testing.expectEqualStrings("const", t1.text);

    _ = tok.next(); // whitespace

    const t2 = tok.next().?;
    try std.testing.expectEqual(tokenizer.TokenType.keyword, t2.type);
    try std.testing.expectEqualStrings("fn", t2.text);
}

test "tokenize zig types" {
    var tok = tokenizer.Tokenizer.init("u32 i64 bool");
    tok.setTypes(syntax.zig_types);

    const t1 = tok.next().?;
    try std.testing.expectEqual(tokenizer.TokenType.type, t1.type);
    try std.testing.expectEqualStrings("u32", t1.text);

    _ = tok.next(); // whitespace

    const t2 = tok.next().?;
    try std.testing.expectEqual(tokenizer.TokenType.type, t2.type);
    try std.testing.expectEqualStrings("i64", t2.text);
}

test "highlight zig function declaration" {
    const allocator = std.testing.allocator;
    const code = "pub fn main() void {}";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    try std.testing.expect(segments.items.len > 0);

    // Find 'pub' and 'fn' keywords
    var pub_found = false;
    var fn_found = false;
    var main_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "pub")) {
            pub_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "fn")) {
            fn_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "main")) {
            main_found = true;
            try std.testing.expectEqual(syntax.Colors.function, seg.color);
        }
    }

    try std.testing.expect(pub_found);
    try std.testing.expect(fn_found);
    try std.testing.expect(main_found);
}

test "highlight zig with string literals" {
    const allocator = std.testing.allocator;
    const code = "const msg = \"hello\";";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    var string_found = false;
    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "\"hello\"")) {
            string_found = true;
            try std.testing.expectEqual(syntax.Colors.string, seg.color);
        }
    }
    try std.testing.expect(string_found);
}

test "highlight zig with comments" {
    const allocator = std.testing.allocator;
    const code = "// This is a comment\nconst x = 1;";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    // First segment should be comment
    try std.testing.expectEqual(syntax.Colors.comment, segments.items[0].color);
    try std.testing.expectEqualStrings("// This is a comment", segments.items[0].text);
}

test "highlight zig multiline code" {
    const allocator = std.testing.allocator;
    const code =
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    const x: u32 = 42;
        \\}
    ;

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    try std.testing.expect(segments.items.len > 10);

    // Should find keywords, types, and numbers
    var has_const = false;
    var has_pub = false;
    var has_u32 = false;
    var has_number = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "const")) has_const = true;
        if (std.mem.eql(u8, seg.text, "pub")) has_pub = true;
        if (std.mem.eql(u8, seg.text, "u32")) has_u32 = true;
        if (std.mem.eql(u8, seg.text, "42")) has_number = true;
    }

    try std.testing.expect(has_const);
    try std.testing.expect(has_pub);
    try std.testing.expect(has_u32);
    try std.testing.expect(has_number);
}

test "highlight javascript code" {
    const allocator = std.testing.allocator;
    const code = "const foo = async () => { return 42; };";

    const segments = try syntax.highlight(allocator, code, .javascript);
    defer segments.deinit();

    var const_found = false;
    var async_found = false;
    var return_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "const")) {
            const_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "async")) {
            async_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "return")) {
            return_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
    }

    try std.testing.expect(const_found);
    try std.testing.expect(async_found);
    try std.testing.expect(return_found);
}

test "highlight typescript code" {
    const allocator = std.testing.allocator;
    const code = "interface Foo { bar: string; }";

    const segments = try syntax.highlight(allocator, code, .typescript);
    defer segments.deinit();

    var interface_found = false;
    var string_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "interface")) {
            interface_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "string")) {
            string_found = true;
            try std.testing.expectEqual(syntax.Colors.type, seg.color);
        }
    }

    try std.testing.expect(interface_found);
    try std.testing.expect(string_found);
}

test "highlight python code" {
    const allocator = std.testing.allocator;
    const code = "def hello(name: str) -> int:\n    return 42";

    const segments = try syntax.highlight(allocator, code, .python);
    defer segments.deinit();

    var def_found = false;
    var return_found = false;
    var str_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "def")) {
            def_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "return")) {
            return_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "str")) {
            str_found = true;
            try std.testing.expectEqual(syntax.Colors.type, seg.color);
        }
    }

    try std.testing.expect(def_found);
    try std.testing.expect(return_found);
    try std.testing.expect(str_found);
}

test "highlight rust code" {
    const allocator = std.testing.allocator;
    const code = "fn main() { let x: u32 = 42; }";

    const segments = try syntax.highlight(allocator, code, .rust);
    defer segments.deinit();

    var fn_found = false;
    var let_found = false;
    var u32_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "fn")) {
            fn_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "let")) {
            let_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "u32")) {
            u32_found = true;
            try std.testing.expectEqual(syntax.Colors.type, seg.color);
        }
    }

    try std.testing.expect(fn_found);
    try std.testing.expect(let_found);
    try std.testing.expect(u32_found);
}

test "highlight bash code" {
    const allocator = std.testing.allocator;
    const code = "if [ -f file.txt ]; then echo 'exists'; fi";

    const segments = try syntax.highlight(allocator, code, .bash);
    defer segments.deinit();

    var if_found = false;
    var then_found = false;
    var fi_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "if")) {
            if_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "then")) {
            then_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "fi")) {
            fi_found = true;
            try std.testing.expectEqual(syntax.Colors.keyword, seg.color);
        }
    }

    try std.testing.expect(if_found);
    try std.testing.expect(then_found);
    try std.testing.expect(fi_found);
}

test "highlight json code" {
    const allocator = std.testing.allocator;
    const code = "{\"name\": \"value\", \"count\": 42}";

    const segments = try syntax.highlight(allocator, code, .json);
    defer segments.deinit();

    // JSON should highlight strings and numbers differently
    var string_count: usize = 0;
    var number_found = false;

    for (segments.items) |seg| {
        if (seg.color == syntax.Colors.string) {
            string_count += 1;
        }
        if (std.mem.eql(u8, seg.text, "42")) {
            number_found = true;
            try std.testing.expectEqual(syntax.Colors.number, seg.color);
        }
    }

    try std.testing.expect(string_count >= 2); // At least "name" and "value"
    try std.testing.expect(number_found);
}

test "highlight unknown language" {
    const allocator = std.testing.allocator;
    const code = "some unknown code 123 \"string\"";

    const segments = try syntax.highlight(allocator, code, .unknown);
    defer segments.deinit();

    // Should still tokenize, but without keyword highlighting
    try std.testing.expect(segments.items.len > 0);

    // Numbers and strings should still be highlighted
    var number_found = false;
    var string_found = false;

    for (segments.items) |seg| {
        if (std.mem.eql(u8, seg.text, "123")) {
            number_found = true;
            try std.testing.expectEqual(syntax.Colors.number, seg.color);
        }
        if (std.mem.eql(u8, seg.text, "\"string\"")) {
            string_found = true;
            try std.testing.expectEqual(syntax.Colors.string, seg.color);
        }
    }

    try std.testing.expect(number_found);
    try std.testing.expect(string_found);
}

test "detect various languages" {
    try std.testing.expectEqual(syntax.Language.zig, syntax.detectLanguage("zig"));
    try std.testing.expectEqual(syntax.Language.javascript, syntax.detectLanguage("javascript"));
    try std.testing.expectEqual(syntax.Language.javascript, syntax.detectLanguage("js"));
    try std.testing.expectEqual(syntax.Language.typescript, syntax.detectLanguage("typescript"));
    try std.testing.expectEqual(syntax.Language.typescript, syntax.detectLanguage("ts"));
    try std.testing.expectEqual(syntax.Language.python, syntax.detectLanguage("python"));
    try std.testing.expectEqual(syntax.Language.python, syntax.detectLanguage("py"));
    try std.testing.expectEqual(syntax.Language.rust, syntax.detectLanguage("rust"));
    try std.testing.expectEqual(syntax.Language.rust, syntax.detectLanguage("rs"));
    try std.testing.expectEqual(syntax.Language.bash, syntax.detectLanguage("bash"));
    try std.testing.expectEqual(syntax.Language.bash, syntax.detectLanguage("sh"));
    try std.testing.expectEqual(syntax.Language.json, syntax.detectLanguage("json"));
    try std.testing.expectEqual(syntax.Language.unknown, syntax.detectLanguage("foobar"));
}

test "highlight code with block comments" {
    const allocator = std.testing.allocator;
    const code = "/* multi\nline\ncomment */ const x = 1;";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    // First segment should be block comment
    try std.testing.expectEqual(syntax.Colors.comment, segments.items[0].color);
    try std.testing.expect(std.mem.indexOf(u8, segments.items[0].text, "multi") != null);
}

test "highlight code with escaped strings" {
    const allocator = std.testing.allocator;
    const code = "const s = \"hello \\\"world\\\"\";";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    var string_found = false;
    for (segments.items) |seg| {
        if (seg.color == syntax.Colors.string and std.mem.indexOf(u8, seg.text, "world") != null) {
            string_found = true;
        }
    }
    try std.testing.expect(string_found);
}

test "highlight numbers with various formats" {
    const allocator = std.testing.allocator;
    const code = "42 3.14 0xFF 1.5e10";

    const segments = try syntax.highlight(allocator, code, .zig);
    defer segments.deinit();

    var number_count: usize = 0;
    for (segments.items) |seg| {
        if (seg.color == syntax.Colors.number) {
            number_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 4), number_count);
}
