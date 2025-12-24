//! Workflow Evaluator
//!
//! Evaluates workflow .py files and generates execution plans.
//! This is a simplified evaluator that understands the Plue workflow DSL
//! without executing arbitrary Python code.

const std = @import("std");
const plan = @import("plan.zig");

/// Evaluation context
pub const Evaluator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Evaluator {
        return .{ .allocator = allocator };
    }

    /// Evaluate a workflow file and extract workflow definitions
    pub fn evaluateFile(self: *Evaluator, file_path: []const u8) !plan.PlanSet {
        const source = try std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024);
        defer self.allocator.free(source);

        return try self.evaluateSource(source, file_path);
    }

    /// Evaluate workflow source code directly
    pub fn evaluateSource(self: *Evaluator, source: []const u8, source_name: []const u8) !plan.PlanSet {
        var workflows: std.ArrayList(plan.WorkflowDefinition) = .{};
        var errors: std.ArrayList(plan.PlanError) = .{};

        var parser = Parser{
            .allocator = self.allocator,
            .source = source,
            .source_name = source_name,
            .pos = 0,
            .line = 1,
            .column = 1,
        };

        parser.parse(&workflows, &errors) catch |err| {
            try errors.append(self.allocator, .{
                .message = try std.fmt.allocPrint(self.allocator, "Parse error: {}", .{err}),
                .file = try self.allocator.dupe(u8, source_name),
                .line = parser.line,
                .column = parser.column,
            });
        };

        return plan.PlanSet{
            .workflows = try workflows.toOwnedSlice(self.allocator),
            .errors = try errors.toOwnedSlice(self.allocator),
        };
    }
};

/// Token types for Python DSL
const TokenType = enum {
    // Literals
    identifier,
    string,
    number,

    // Keywords
    keyword_from,
    keyword_import,
    keyword_def,
    keyword_return,

    // Symbols
    at_sign,      // @
    left_paren,   // (
    right_paren,  // )
    left_bracket, // [
    right_bracket, // ]
    comma,        // ,
    equals,       // =
    colon,        // :
    dot,          // .

    // Special
    newline,
    indent,
    dedent,
    eof,
};

const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

/// Simple parser for workflow DSL
const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    source_name: []const u8,
    pos: usize,
    line: usize,
    column: usize,

    // Current step counter for generating unique IDs
    step_counter: usize = 0,

    fn parse(
        self: *Parser,
        workflows: *std.ArrayList(plan.WorkflowDefinition),
        errors: *std.ArrayList(plan.PlanError),
    ) !void {
        // Parse workflow definitions
        // Look for @workflow decorator followed by function definition

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();

            if (self.pos >= self.source.len) break;

            // Look for @workflow decorator
            if (self.peek() == '@') {
                const workflow = self.parseWorkflow() catch |err| {
                    try errors.append(self.allocator, .{
                        .message = try std.fmt.allocPrint(self.allocator, "Failed to parse workflow: {}", .{err}),
                        .file = try self.allocator.dupe(u8, self.source_name),
                        .line = self.line,
                        .column = self.column,
                    });
                    // Skip to next line and continue
                    self.skipToNextLine();
                    continue;
                };

                if (workflow) |wf| {
                    try workflows.append(self.allocator, wf);
                }
            } else {
                // Skip non-workflow lines (imports, etc.)
                self.skipToNextLine();
            }
        }
    }

    fn parseWorkflow(self: *Parser) !?plan.WorkflowDefinition {
        // Expect @workflow
        if (!try self.expectChar('@')) return null;

        const decorator_name = try self.parseIdentifier();
        defer self.allocator.free(decorator_name);

        if (!std.mem.eql(u8, decorator_name, "workflow")) {
            // Not a workflow decorator, skip it
            return null;
        }

        // Parse decorator arguments: @workflow(triggers=[...], image="...", ...)
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        var triggers: std.ArrayList(plan.Trigger) = .{};
        var image: ?[]const u8 = null;
        var dockerfile: ?[]const u8 = null;

        // Parse keyword arguments
        while (self.peek() != ')') {
            self.skipWhitespaceAndComments();

            const key = try self.parseIdentifier();
            defer self.allocator.free(key);

            self.skipWhitespaceAndComments();
            if (!try self.expectChar('=')) return error.ExpectedEquals;
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, key, "triggers")) {
                triggers = try self.parseTriggers();
            } else if (std.mem.eql(u8, key, "image")) {
                image = try self.parseString();
            } else if (std.mem.eql(u8, key, "dockerfile")) {
                dockerfile = try self.parseString();
            } else {
                // Unknown argument, skip value
                try self.skipValue();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
                self.skipWhitespaceAndComments();
            }
        }

        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        // Now parse the function definition
        self.skipWhitespaceAndComments();

        // Expect: def function_name(ctx):
        const def_keyword = try self.parseIdentifier();
        defer self.allocator.free(def_keyword);

        if (!std.mem.eql(u8, def_keyword, "def")) return error.ExpectedDef;

        self.skipWhitespaceAndComments();
        const function_name = try self.parseIdentifier();

        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        // Skip function parameters (we know it's (ctx))
        while (self.peek() != ')' and self.pos < self.source.len) {
            _ = self.advance();
        }
        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        self.skipWhitespaceAndComments();
        if (!try self.expectChar(':')) return error.ExpectedColon;

        // Parse function body to extract steps
        var steps = try self.parseFunctionBody();

        return plan.WorkflowDefinition{
            .name = function_name,
            .triggers = try triggers.toOwnedSlice(self.allocator),
            .image = image,
            .dockerfile = dockerfile,
            .steps = try steps.toOwnedSlice(self.allocator),
        };
    }

    fn parseTriggers(self: *Parser) !std.ArrayList(plan.Trigger) {
        var triggers: std.ArrayList(plan.Trigger) = .{};

        // Expect [push(), pull_request(), ...]
        if (!try self.expectChar('[')) return error.ExpectedLeftBracket;

        self.skipWhitespaceAndComments();
        while (self.peek() != ']' and self.pos < self.source.len) {
            const trigger = try self.parseTrigger();
            try triggers.append(self.allocator, trigger);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
                self.skipWhitespaceAndComments();
            }
        }

        if (!try self.expectChar(']')) return error.ExpectedRightBracket;

        return triggers;
    }

    fn parseTrigger(self: *Parser) !plan.Trigger {
        const trigger_name = try self.parseIdentifier();
        defer self.allocator.free(trigger_name);

        const trigger_type: plan.TriggerType = blk: {
            if (std.mem.eql(u8, trigger_name, "push")) break :blk .push;
            if (std.mem.eql(u8, trigger_name, "pull_request")) break :blk .pull_request;
            if (std.mem.eql(u8, trigger_name, "issue_comment")) break :blk .issue_comment;
            if (std.mem.eql(u8, trigger_name, "manual")) break :blk .manual;
            if (std.mem.eql(u8, trigger_name, "schedule")) break :blk .schedule;
            return error.UnknownTriggerType;
        };

        // Parse trigger arguments: push(branches=["main"])
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        var config = std.json.ObjectMap.init(self.allocator);

        self.skipWhitespaceAndComments();

        // Parse keyword arguments
        while (self.peek() != ')' and self.pos < self.source.len) {
            self.skipWhitespaceAndComments();

            const key = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            if (!try self.expectChar('=')) {
                self.allocator.free(key);
                return error.ExpectedEquals;
            }
            self.skipWhitespaceAndComments();

            const value = try self.parseValue();
            try config.put(key, value);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }

        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        return plan.Trigger{
            .type = trigger_type,
            .config = .{ .object = config },
        };
    }

    fn parseFunctionBody(self: *Parser) !std.ArrayList(plan.Step) {
        var steps: std.ArrayList(plan.Step) = .{};

        self.skipWhitespaceAndComments();

        // Find all ctx.run(...) calls in the function body
        // This is a simplified parser - a full implementation would handle
        // conditional statements, loops, etc.

        const body_start = self.pos;
        var body_indent: ?usize = null;

        while (self.pos < self.source.len) {
            self.skipWhitespace();

            // Track indentation to know when function body ends
            const line_indent = self.countIndent();

            if (body_indent == null) {
                if (line_indent > 0) {
                    body_indent = line_indent;
                }
            } else {
                // If we dedent back to function level or beyond, body is done
                if (line_indent < body_indent.?) {
                    break;
                }
            }

            // Look for ctx.run(...) or ctx.parallel(...)
            if (try self.matchString("ctx.run")) {
                const step = try self.parseRunStep();
                try steps.append(self.allocator, step);
            } else if (try self.matchString("ctx.parallel")) {
                const step = try self.parseParallelStep();
                try steps.append(self.allocator, step);
            } else if (try self.matchString("return")) {
                // End of function body
                break;
            } else {
                // Skip this line
                self.skipToNextLine();
            }
        }

        // Reset position if we didn't parse anything
        if (steps.items.len == 0) {
            self.pos = body_start;
        }

        return steps;
    }

    fn parseRunStep(self: *Parser) !plan.Step {
        // Already matched "ctx.run", now parse arguments
        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        var config = std.json.ObjectMap.init(self.allocator);
        var step_name: ?[]const u8 = null;

        self.skipWhitespaceAndComments();

        // Parse keyword arguments
        while (self.peek() != ')' and self.pos < self.source.len) {
            self.skipWhitespaceAndComments();

            const key = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            if (!try self.expectChar('=')) {
                self.allocator.free(key);
                return error.ExpectedEquals;
            }
            self.skipWhitespaceAndComments();

            const value = try self.parseValue();

            if (std.mem.eql(u8, key, "name")) {
                step_name = try self.allocator.dupe(u8, value.string);
            }

            try config.put(key, value);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }

        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        self.step_counter += 1;
        const step_id = try std.fmt.allocPrint(self.allocator, "step_{d}", .{self.step_counter});

        return plan.Step{
            .id = step_id,
            .name = step_name orelse try self.allocator.dupe(u8, "unnamed"),
            .@"type" = .shell,
            .config = .{ .data = .{ .object = config } },
            .depends_on = &.{},
        };
    }

    fn parseParallelStep(self: *Parser) !plan.Step {
        // Simplified - just create a parallel step marker
        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        // Skip the arguments for now
        var depth: usize = 1;
        while (depth > 0 and self.pos < self.source.len) {
            const ch = self.advance() orelse break;
            if (ch == '(') depth += 1;
            if (ch == ')') depth -= 1;
        }

        self.step_counter += 1;
        const step_id = try std.fmt.allocPrint(self.allocator, "step_{d}", .{self.step_counter});

        const config = std.json.ObjectMap.init(self.allocator);

        return plan.Step{
            .id = step_id,
            .name = try self.allocator.dupe(u8, "parallel"),
            .@"type" = .parallel,
            .config = .{ .data = .{ .object = config } },
            .depends_on = &.{},
        };
    }

    fn parseValue(self: *Parser) anyerror!std.json.Value {
        self.skipWhitespaceAndComments();

        const ch = self.peek() orelse return error.UnexpectedEof;

        if (ch == '"' or ch == '\'') {
            const str = try self.parseString();
            return .{ .string = str };
        } else if (ch == '[') {
            return try self.parseArray();
        } else if (ch == '{') {
            return try self.parseObject();
        } else if (std.ascii.isDigit(ch) or ch == '-') {
            const num = try self.parseNumber();
            return .{ .integer = num };
        } else if (try self.matchString("True")) {
            return .{ .bool = true };
        } else if (try self.matchString("False")) {
            return .{ .bool = false };
        } else if (try self.matchString("None")) {
            return .null;
        }

        return error.UnexpectedValue;
    }

    fn parseArray(self: *Parser) !std.json.Value {
        if (!try self.expectChar('[')) return error.ExpectedLeftBracket;

        var array = std.json.Array.init(self.allocator);

        self.skipWhitespaceAndComments();
        while (self.peek() != ']' and self.pos < self.source.len) {
            const value = try self.parseValue();
            try array.append(value);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
                self.skipWhitespaceAndComments();
            }
        }

        if (!try self.expectChar(']')) return error.ExpectedRightBracket;

        return .{ .array = array };
    }

    fn parseObject(self: *Parser) !std.json.Value {
        if (!try self.expectChar('{')) return error.ExpectedLeftBrace;

        var object = std.json.ObjectMap.init(self.allocator);

        self.skipWhitespaceAndComments();
        while (self.peek() != '}' and self.pos < self.source.len) {
            const key = try self.parseString();

            self.skipWhitespaceAndComments();
            if (!try self.expectChar(':')) {
                self.allocator.free(key);
                return error.ExpectedColon;
            }
            self.skipWhitespaceAndComments();

            const value = try self.parseValue();
            try object.put(key, value);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
                self.skipWhitespaceAndComments();
            }
        }

        if (!try self.expectChar('}')) return error.ExpectedRightBrace;

        return .{ .object = object };
    }

    fn parseString(self: *Parser) ![]const u8 {
        const quote_char = self.peek() orelse return error.UnexpectedEof;
        if (quote_char != '"' and quote_char != '\'') return error.ExpectedString;

        _ = self.advance(); // Skip opening quote

        const start = self.pos;
        while (self.peek()) |ch| {
            if (ch == quote_char) break;
            if (ch == '\\') {
                _ = self.advance(); // Skip escape char
                _ = self.advance(); // Skip escaped char
            } else {
                _ = self.advance();
            }
        }

        const content = self.source[start..self.pos];

        if (self.peek() != quote_char) return error.UnterminatedString;
        _ = self.advance(); // Skip closing quote

        return try self.allocator.dupe(u8, content);
    }

    fn parseNumber(self: *Parser) !i64 {
        const start = self.pos;

        if (self.peek() == '-') {
            _ = self.advance();
        }

        while (self.peek()) |ch| {
            if (!std.ascii.isDigit(ch)) break;
            _ = self.advance();
        }

        const num_str = self.source[start..self.pos];
        return try std.fmt.parseInt(i64, num_str, 10);
    }

    fn parseIdentifier(self: *Parser) ![]const u8 {
        const start = self.pos;

        // First char must be letter or underscore
        const first = self.peek() orelse return error.UnexpectedEof;
        if (!std.ascii.isAlphabetic(first) and first != '_') return error.ExpectedIdentifier;

        _ = self.advance();

        // Rest can be alphanumeric or underscore
        while (self.peek()) |ch| {
            if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
            _ = self.advance();
        }

        return try self.allocator.dupe(u8, self.source[start..self.pos]);
    }

    fn skipValue(self: *Parser) !void {
        _ = try self.parseValue();
    }

    fn matchString(self: *Parser, str: []const u8) !bool {
        const saved_pos = self.pos;
        const saved_line = self.line;
        const saved_column = self.column;

        for (str) |ch| {
            if (self.peek() != ch) {
                self.pos = saved_pos;
                self.line = saved_line;
                self.column = saved_column;
                return false;
            }
            _ = self.advance();
        }

        return true;
    }

    fn expectChar(self: *Parser, expected: u8) !bool {
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }

    fn countIndent(self: *Parser) usize {
        var count: usize = 0;
        const saved_pos = self.pos;

        while (self.peek()) |ch| {
            if (ch == ' ') {
                count += 1;
                _ = self.advance();
            } else if (ch == '\t') {
                count += 4; // Tab counts as 4 spaces
                _ = self.advance();
            } else {
                break;
            }
        }

        self.pos = saved_pos;
        return count;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (!std.ascii.isWhitespace(ch) or ch == '\n') break;
            if (ch == '\t' or ch == ' ') {
                self.column += 1;
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];

            // Skip whitespace (including newlines)
            if (std.ascii.isWhitespace(ch)) {
                if (ch == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
                self.pos += 1;
                continue;
            }

            // Skip comments
            if (ch == '#') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
                continue;
            }

            break;
        }
    }

    fn skipToNextLine(self: *Parser) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos < self.source.len) {
            self.pos += 1; // Skip the newline
            self.line += 1;
            self.column = 1;
        }
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance(self: *Parser) ?u8 {
        const ch = self.peek() orelse return null;
        self.pos += 1;
        if (ch == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return ch;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "evaluator basic workflow" {
    const allocator = std.testing.allocator;

    var evaluator = Evaluator.init(allocator);

    const source =
        \\from plue import workflow, push
        \\
        \\@workflow(triggers=[push()])
        \\def ci(ctx):
        \\    ctx.run(name="test", cmd="echo hello")
    ;

    var result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    // Should have 1 workflow
    try std.testing.expectEqual(@as(usize, 1), result.workflows.len);
    try std.testing.expectEqual(@as(usize, 0), result.errors.len);

    const workflow = result.workflows[0];
    try std.testing.expectEqualStrings("ci", workflow.name);
    try std.testing.expectEqual(@as(usize, 1), workflow.triggers.len);
    try std.testing.expectEqual(plan.TriggerType.push, workflow.triggers[0].type);
    try std.testing.expectEqual(@as(usize, 1), workflow.steps.len);

    const step = workflow.steps[0];
    try std.testing.expectEqualStrings("test", step.name);
    try std.testing.expectEqual(plan.StepType.shell, step.@"type");
}

test "evaluator multiple steps" {
    const allocator = std.testing.allocator;

    var evaluator = Evaluator.init(allocator);

    const source =
        \\from plue import workflow, push
        \\
        \\@workflow(triggers=[push()])
        \\def ci(ctx):
        \\    ctx.run(name="install", cmd="bun install")
        \\    ctx.run(name="test", cmd="bun test")
        \\    ctx.run(name="build", cmd="bun build")
    ;

    var result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.workflows.len);

    const workflow = result.workflows[0];
    try std.testing.expectEqual(@as(usize, 3), workflow.steps.len);
    try std.testing.expectEqualStrings("install", workflow.steps[0].name);
    try std.testing.expectEqualStrings("test", workflow.steps[1].name);
    try std.testing.expectEqualStrings("build", workflow.steps[2].name);
}

test "evaluator with image" {
    const allocator = std.testing.allocator;

    var evaluator = Evaluator.init(allocator);

    const source =
        \\from plue import workflow, push
        \\
        \\@workflow(triggers=[push()], image="ubuntu:22.04")
        \\def ci(ctx):
        \\    ctx.run(name="test", cmd="echo hello")
    ;

    var result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.workflows.len);

    const workflow = result.workflows[0];
    try std.testing.expect(workflow.image != null);
    try std.testing.expectEqualStrings("ubuntu:22.04", workflow.image.?);
}

test "evaluator pull_request trigger" {
    const allocator = std.testing.allocator;

    var evaluator = Evaluator.init(allocator);

    const source =
        \\from plue import workflow, pull_request
        \\
        \\@workflow(triggers=[pull_request(types=["opened", "synchronize"])])
        \\def review(ctx):
        \\    ctx.run(name="lint", cmd="bun lint")
    ;

    var result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.workflows.len);

    const workflow = result.workflows[0];
    try std.testing.expectEqualStrings("review", workflow.name);
    try std.testing.expectEqual(@as(usize, 1), workflow.triggers.len);
    try std.testing.expectEqual(plan.TriggerType.pull_request, workflow.triggers[0].type);
}

test "parser basic structure" {
    const allocator = std.testing.allocator;

    var parser = Parser{
        .allocator = allocator,
        .source = "  hello\nworld",
        .source_name = "test.py",
        .pos = 0,
        .line = 1,
        .column = 1,
    };

    try std.testing.expectEqual(@as(?u8, ' '), parser.peek());

    parser.skipWhitespace();
    try std.testing.expectEqual(@as(?u8, 'h'), parser.peek());

    _ = parser.advance();
    try std.testing.expectEqual(@as(?u8, 'e'), parser.peek());
}
