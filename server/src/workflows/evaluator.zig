//! Workflow Evaluator
//!
//! Evaluates workflow .py files and generates execution plans.
//! This is a simplified evaluator that understands the Plue workflow DSL
//! without executing arbitrary Python code.

const std = @import("std");
const plan = @import("plan.zig");

pub const PromptDefinitionInfo = struct {
    name: []const u8,
    file_path: []const u8,
    prompt_type: []const u8,
    client: []const u8,
    tools_json: []const u8,
    max_turns: u32,
};

pub const PromptCatalog = struct {
    allocator: std.mem.Allocator,
    prompts: std.StringHashMap(PromptDefinitionInfo),

    pub fn init(allocator: std.mem.Allocator) PromptCatalog {
        return .{
            .allocator = allocator,
            .prompts = std.StringHashMap(PromptDefinitionInfo).init(allocator),
        };
    }

    pub fn deinit(self: *PromptCatalog) void {
        var iter = self.prompts.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.file_path);
            self.allocator.free(entry.value_ptr.prompt_type);
            self.allocator.free(entry.value_ptr.client);
            self.allocator.free(entry.value_ptr.tools_json);
        }
        self.prompts.deinit();
    }

    pub fn add(self: *PromptCatalog, info: PromptDefinitionInfo) !void {
        const name = try self.allocator.dupe(u8, info.name);
        errdefer self.allocator.free(name);

        const file_path = try self.allocator.dupe(u8, info.file_path);
        errdefer self.allocator.free(file_path);

        const prompt_type = try self.allocator.dupe(u8, info.prompt_type);
        errdefer self.allocator.free(prompt_type);

        const client = try self.allocator.dupe(u8, info.client);
        errdefer self.allocator.free(client);

        const tools_json = try self.allocator.dupe(u8, info.tools_json);
        errdefer self.allocator.free(tools_json);

        try self.prompts.put(name, .{
            .name = name,
            .file_path = file_path,
            .prompt_type = prompt_type,
            .client = client,
            .tools_json = tools_json,
            .max_turns = info.max_turns,
        });
    }

    pub fn get(self: *const PromptCatalog, name: []const u8) ?PromptDefinitionInfo {
        return self.prompts.get(name);
    }
};

/// Evaluation context
pub const Evaluator = struct {
    allocator: std.mem.Allocator,
    prompt_catalog: ?*const PromptCatalog = null,

    pub fn init(allocator: std.mem.Allocator) Evaluator {
        return .{ .allocator = allocator };
    }

    pub fn initWithPrompts(allocator: std.mem.Allocator, catalog: *const PromptCatalog) Evaluator {
        return .{ .allocator = allocator, .prompt_catalog = catalog };
    }

    pub fn deinit(self: *Evaluator) void {
        _ = self;
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
            .prompt_catalog = self.prompt_catalog,
            .imported_prompts = std.StringHashMap(PromptDefinitionInfo).init(self.allocator),
        };
        defer parser.deinit();

        try parser.scanImportsAndValidate(&errors);

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
    prompt_catalog: ?*const PromptCatalog,
    imported_prompts: std.StringHashMap(PromptDefinitionInfo),

    // Current step counter for generating unique IDs
    step_counter: usize = 0,

    fn deinit(self: *Parser) void {
        var iter = self.imported_prompts.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.imported_prompts.deinit();
    }

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

    fn scanImportsAndValidate(self: *Parser, errors: *std.ArrayList(plan.PlanError)) !void {
        var iter = std.mem.splitScalar(u8, self.source, '\n');
        var line_number: usize = 1;

        while (iter.next()) |raw_line| : (line_number += 1) {
            const line = std.mem.trimLeft(u8, raw_line, " \t");
            if (line.len == 0 or line[0] == '#') continue;

            if (std.mem.startsWith(u8, line, "import ")) {
                try self.appendError(errors, "Direct import statements are not allowed", line_number, 1);
                continue;
            }

            if (std.mem.startsWith(u8, line, "from ")) {
                const import_idx = std.mem.indexOf(u8, line, " import ") orelse {
                    try self.appendError(errors, "Invalid import statement", line_number, 1);
                    continue;
                };

                const module = std.mem.trim(u8, line[5..import_idx], " \t");
                const names_str = std.mem.trim(u8, line[import_idx + 8 ..], " \t");

                const allowed = std.mem.eql(u8, module, "plue") or
                    std.mem.eql(u8, module, "plue.prompts") or
                    std.mem.eql(u8, module, "plue.tools");

                if (!allowed) {
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Import blocked by RestrictedPython: from {s}",
                        .{module},
                    );
                    try self.appendErrorOwned(errors, msg, line_number, 1);
                    continue;
                }

                if (std.mem.eql(u8, module, "plue.prompts")) {
                    try self.registerPromptImports(names_str, errors, line_number);
                }
            }
        }

        try self.scanForbiddenIdentifiers(errors);
    }

    fn registerPromptImports(self: *Parser, names_str: []const u8, errors: *std.ArrayList(plan.PlanError), line_number: usize) !void {
        var name_iter = std.mem.splitScalar(u8, names_str, ',');
        while (name_iter.next()) |raw_name| {
            const name = std.mem.trim(u8, raw_name, " \t");
            if (name.len == 0) continue;

            if (self.prompt_catalog) |catalog| {
                if (catalog.get(name)) |prompt_def| {
                    const key = try self.allocator.dupe(u8, name);
                    errdefer self.allocator.free(key);
                    try self.imported_prompts.put(key, prompt_def);
                } else {
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Prompt '{s}' not found in registry",
                        .{name},
                    );
                    try self.appendErrorOwned(errors, msg, line_number, 1);
                }
            } else {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Prompt imports require a prompt catalog: {s}",
                    .{name},
                );
                try self.appendErrorOwned(errors, msg, line_number, 1);
            }
        }
    }

    fn scanForbiddenIdentifiers(self: *Parser, errors: *std.ArrayList(plan.PlanError)) !void {
        const forbidden = std.StaticStringMap(void).initComptime(.{
            .{ "open", {} },
            .{ "eval", {} },
            .{ "exec", {} },
            .{ "compile", {} },
            .{ "os", {} },
            .{ "pathlib", {} },
            .{ "socket", {} },
            .{ "urllib", {} },
            .{ "requests", {} },
            .{ "subprocess", {} },
        });

        var i: usize = 0;
        var line: usize = 1;
        var column: usize = 1;
        var in_string: ?u8 = null;

        while (i < self.source.len) : (i += 1) {
            const ch = self.source[i];

            if (in_string) |quote| {
                if (ch == '\\') {
                    if (i + 1 < self.source.len) {
                        i += 1;
                        column += 1;
                    }
                } else if (ch == quote) {
                    in_string = null;
                }

                if (ch == '\n') {
                    line += 1;
                    column = 1;
                } else {
                    column += 1;
                }
                continue;
            }

            if (ch == '#') {
                while (i < self.source.len and self.source[i] != '\n') : (i += 1) {}
                continue;
            }

            if (ch == '\n') {
                line += 1;
                column = 1;
                continue;
            }

            if (ch == '"' or ch == '\'') {
                in_string = ch;
                column += 1;
                continue;
            }

            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start = i;
                var end = i + 1;
                while (end < self.source.len) : (end += 1) {
                    const next = self.source[end];
                    if (!std.ascii.isAlphanumeric(next) and next != '_') break;
                }

                const ident = self.source[start..end];
                if (ident.len > 0 and ident[0] == '_') {
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Private identifiers are not allowed: {s}",
                        .{ident},
                    );
                    try self.appendErrorOwned(errors, msg, line, column);
                } else if (forbidden.get(ident) != null) {
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Identifier blocked by RestrictedPython: {s}",
                        .{ident},
                    );
                    try self.appendErrorOwned(errors, msg, line, column);
                }

                column += (end - start);
                i = end - 1;
                continue;
            }

            column += 1;
        }
    }

    fn appendError(self: *Parser, errors: *std.ArrayList(plan.PlanError), message: []const u8, line: usize, column: usize) !void {
        try errors.append(self.allocator, .{
            .message = try self.allocator.dupe(u8, message),
            .file = try self.allocator.dupe(u8, self.source_name),
            .line = line,
            .column = column,
        });
    }

    fn appendErrorOwned(self: *Parser, errors: *std.ArrayList(plan.PlanError), message: []const u8, line: usize, column: usize) !void {
        try errors.append(self.allocator, .{
            .message = message,
            .file = try self.allocator.dupe(u8, self.source_name),
            .line = line,
            .column = column,
        });
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
        var step_vars = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var iter = step_vars.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            step_vars.deinit();
        }

        self.skipWhitespaceAndComments();

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
            } else if (line_indent < body_indent.?) {
                break;
            }

            const saved_pos = self.pos;
            const saved_line = self.line;
            const saved_column = self.column;

            self.skipWhitespaceAndComments();

            if (try self.matchString("return")) {
                break;
            }

            // Attempt assignment: <name> = ctx.run(...) / ctx.parallel(...) / Prompt(...)
            var assignment_name: ?[]const u8 = null;
            if (self.peek()) |ch| {
                if (std.ascii.isAlphabetic(ch) or ch == '_') {
                    assignment_name = self.parseIdentifier() catch null;
                }
            }

            if (assignment_name != null) {
                self.skipWhitespaceAndComments();
                if (self.peek() == '=') {
                    _ = self.advance();
                    self.skipWhitespaceAndComments();

                    if (try self.matchString("ctx.run")) {
                        const step = try self.parseRunStep(&step_vars, assignment_name);
                        try steps.append(self.allocator, step);
                        continue;
                    }

                    if (try self.matchString("ctx.parallel")) {
                        const step = try self.parseParallelStep(&steps, &step_vars, assignment_name);
                        try steps.append(self.allocator, step);
                        continue;
                    }

                    if (try self.tryParsePromptStep(&steps, &step_vars, assignment_name)) {
                        continue;
                    }
                }
            }

            if (assignment_name) |name| {
                self.allocator.free(name);
            }

            // Reset position if no assignment match
            self.pos = saved_pos;
            self.line = saved_line;
            self.column = saved_column;

            self.skipWhitespaceAndComments();

            if (try self.matchString("ctx.run")) {
                const step = try self.parseRunStep(&step_vars, null);
                try steps.append(self.allocator, step);
            } else if (try self.matchString("ctx.parallel")) {
                const step = try self.parseParallelStep(&steps, &step_vars, null);
                try steps.append(self.allocator, step);
            } else if (try self.tryParsePromptStep(&steps, &step_vars, null)) {
                continue;
            } else {
                self.skipToNextLine();
            }
        }

        if (steps.items.len == 0) {
            self.pos = body_start;
        }

        return steps;
    }

    fn parseRunStep(
        self: *Parser,
        step_vars: *std.StringHashMap([]const u8),
        assignment_name: ?[]const u8,
    ) !plan.Step {
        // Already matched "ctx.run", now parse arguments
        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        var config = std.json.ObjectMap.init(self.allocator);
        var step_name: ?[]const u8 = null;
        var depends_on_list = std.ArrayList([]const u8){};
        errdefer depends_on_list.deinit(self.allocator);

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

            if (std.mem.eql(u8, key, "depends_on")) {
                const deps = try self.parseDependsOn(step_vars);
                for (deps) |dep| {
                    try depends_on_list.append(self.allocator, dep);
                }
                self.allocator.free(key);
            } else {
                const value = try self.parseValue();

                if (std.mem.eql(u8, key, "name")) {
                    step_name = try self.allocator.dupe(u8, value.string);
                }

                try config.put(key, value);
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }

        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        self.step_counter += 1;
        const step_id = try std.fmt.allocPrint(self.allocator, "step_{d}", .{self.step_counter});

        const depends_on = try depends_on_list.toOwnedSlice(self.allocator);

        const step = plan.Step{
            .id = step_id,
            .name = step_name orelse try self.allocator.dupe(u8, "unnamed"),
            .@"type" = .shell,
            .config = .{ .data = .{ .object = config } },
            .depends_on = depends_on,
        };

        if (assignment_name) |name| {
            const key = try self.allocator.dupe(u8, name);
            try step_vars.put(key, step.id);
            self.allocator.free(name);
        }

        return step;
    }

    fn parseParallelStep(
        self: *Parser,
        steps: *std.ArrayList(plan.Step),
        step_vars: *std.StringHashMap([]const u8),
        assignment_name: ?[]const u8,
    ) !plan.Step {
        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        self.skipWhitespaceAndComments();
        if (!try self.expectChar('[')) return error.ExpectedLeftBracket;

        var step_ids = std.ArrayList([]const u8){};
        defer step_ids.deinit(self.allocator);

        self.skipWhitespaceAndComments();
        while (self.peek() != ']' and self.pos < self.source.len) {
            self.skipWhitespaceAndComments();

            if (try self.matchString("ctx.run")) {
                const nested = try self.parseRunStep(step_vars, null);
                try step_ids.append(self.allocator, try self.allocator.dupe(u8, nested.id));
                try steps.append(self.allocator, nested);
            } else if (try self.matchString("ctx.parallel")) {
                const nested_parallel = try self.parseParallelStep(steps, step_vars, null);
                try step_ids.append(self.allocator, try self.allocator.dupe(u8, nested_parallel.id));
                try steps.append(self.allocator, nested_parallel);
            } else if (try self.tryParsePromptStep(steps, step_vars, null)) {
                if (steps.items.len > 0) {
                    const last_step = steps.items[steps.items.len - 1];
                    try step_ids.append(self.allocator, try self.allocator.dupe(u8, last_step.id));
                }
            } else {
                const name = try self.parseIdentifier();
                if (step_vars.get(name)) |dep_id| {
                    try step_ids.append(self.allocator, try self.allocator.dupe(u8, dep_id));
                    self.allocator.free(name);
                } else {
                    try step_ids.append(self.allocator, name);
                }
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
                self.skipWhitespaceAndComments();
            }
        }

        if (!try self.expectChar(']')) return error.ExpectedRightBracket;
        self.skipWhitespaceAndComments();
        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        self.step_counter += 1;
        const step_id = try std.fmt.allocPrint(self.allocator, "step_{d}", .{self.step_counter});

        var config = std.json.ObjectMap.init(self.allocator);
        var ids_array = std.json.Array.init(self.allocator);
        for (step_ids.items) |id| {
            try ids_array.append(.{ .string = id });
        }
        try config.put("step_ids", .{ .array = ids_array });

        const step = plan.Step{
            .id = step_id,
            .name = try self.allocator.dupe(u8, "parallel"),
            .@"type" = .parallel,
            .config = .{ .data = .{ .object = config } },
            .depends_on = &.{},
        };

        if (assignment_name) |name| {
            const key = try self.allocator.dupe(u8, name);
            try step_vars.put(key, step.id);
            self.allocator.free(name);
        }

        return step;
    }

    fn tryParsePromptStep(
        self: *Parser,
        steps: *std.ArrayList(plan.Step),
        step_vars: *std.StringHashMap([]const u8),
        assignment_name: ?[]const u8,
    ) !bool {
        const saved_pos = self.pos;
        const saved_line = self.line;
        const saved_column = self.column;

        if (self.peek() == null) return false;
        const ch = self.peek().?;
        if (!std.ascii.isAlphabetic(ch) and ch != '_') return false;

        const name = self.parseIdentifier() catch {
            self.pos = saved_pos;
            self.line = saved_line;
            self.column = saved_column;
            return false;
        };
        defer self.allocator.free(name);

        const prompt_def = self.imported_prompts.get(name) orelse {
            self.pos = saved_pos;
            self.line = saved_line;
            self.column = saved_column;
            return false;
        };

        self.skipWhitespaceAndComments();
        if (self.peek() != '(') {
            self.pos = saved_pos;
            self.line = saved_line;
            self.column = saved_column;
            return false;
        }

        const step = try self.parsePromptStep(prompt_def, step_vars, assignment_name);
        try steps.append(self.allocator, step);
        return true;
    }

    fn parsePromptStep(
        self: *Parser,
        prompt_def: PromptDefinitionInfo,
        step_vars: *std.StringHashMap([]const u8),
        assignment_name: ?[]const u8,
    ) !plan.Step {
        self.skipWhitespaceAndComments();
        if (!try self.expectChar('(')) return error.ExpectedLeftParen;

        var inputs = std.json.ObjectMap.init(self.allocator);
        var config = std.json.ObjectMap.init(self.allocator);
        var depends_on_list = std.ArrayList([]const u8){};
        errdefer depends_on_list.deinit(self.allocator);

        var tools_value: ?std.json.Value = null;
        var max_turns_value: ?i64 = null;
        var client_value: ?[]const u8 = null;

        self.skipWhitespaceAndComments();
        while (self.peek() != ')' and self.pos < self.source.len) {
            self.skipWhitespaceAndComments();

            const key = try self.parseIdentifier();
            defer self.allocator.free(key);

            self.skipWhitespaceAndComments();
            if (!try self.expectChar('=')) return error.ExpectedEquals;
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, key, "depends_on")) {
                const deps = try self.parseDependsOn(step_vars);
                for (deps) |dep| {
                    try depends_on_list.append(self.allocator, dep);
                }
            } else if (std.mem.eql(u8, key, "tools")) {
                tools_value = try self.parseValue();
            } else if (std.mem.eql(u8, key, "max_turns")) {
                const value = try self.parseValue();
                if (value == .integer) {
                    max_turns_value = value.integer;
                }
            } else if (std.mem.eql(u8, key, "client")) {
                const value = try self.parseValue();
                if (value == .string) {
                    client_value = try self.allocator.dupe(u8, value.string);
                }
            } else {
                const value = try self.parseValue();
                try inputs.put(try self.allocator.dupe(u8, key), value);
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') {
                _ = self.advance();
            }
        }

        if (!try self.expectChar(')')) return error.ExpectedRightParen;

        try config.put("prompt_path", .{ .string = try self.allocator.dupe(u8, prompt_def.file_path) });
        try config.put("inputs", .{ .object = inputs });

        if (client_value) |client| {
            try config.put("client", .{ .string = client });
        } else {
            try config.put("client", .{ .string = try self.allocator.dupe(u8, prompt_def.client) });
        }

        if (tools_value) |tools| {
            try config.put("tools", tools);
        } else if (prompt_def.tools_json.len > 0) {
            const parsed_tools = std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                prompt_def.tools_json,
                .{},
            ) catch null;
            if (parsed_tools) |parsed| {
                try config.put("tools", parsed.value);
            }
        }

        const max_turns = max_turns_value orelse @as(i64, @intCast(prompt_def.max_turns));
        try config.put("max_turns", .{ .integer = max_turns });

        self.step_counter += 1;
        const step_id = try std.fmt.allocPrint(self.allocator, "step_{d}", .{self.step_counter});

        const depends_on = try depends_on_list.toOwnedSlice(self.allocator);

        const step_type: plan.StepType = if (std.mem.eql(u8, prompt_def.prompt_type, "agent")) .agent else .llm;
        const step = plan.Step{
            .id = step_id,
            .name = try self.allocator.dupe(u8, prompt_def.name),
            .@"type" = step_type,
            .config = .{ .data = .{ .object = config } },
            .depends_on = depends_on,
        };

        if (assignment_name) |name| {
            const key = try self.allocator.dupe(u8, name);
            try step_vars.put(key, step.id);
            self.allocator.free(name);
        }

        return step;
    }

    fn parseDependsOn(
        self: *Parser,
        step_vars: *std.StringHashMap([]const u8),
    ) ![]const []const u8 {
        self.skipWhitespaceAndComments();

        var deps = std.ArrayList([]const u8){};
        errdefer deps.deinit(self.allocator);

        if (self.peek() == '[') {
            _ = self.advance();
            self.skipWhitespaceAndComments();

            while (self.peek() != ']' and self.pos < self.source.len) {
                const name = try self.parseIdentifier();
                if (step_vars.get(name)) |dep_id| {
                    try deps.append(self.allocator, try self.allocator.dupe(u8, dep_id));
                    self.allocator.free(name);
                } else {
                    try deps.append(self.allocator, name);
                }

                self.skipWhitespaceAndComments();
                if (self.peek() == ',') {
                    _ = self.advance();
                    self.skipWhitespaceAndComments();
                }
            }

            if (!try self.expectChar(']')) return error.ExpectedRightBracket;
        } else {
            const name = try self.parseIdentifier();
            if (step_vars.get(name)) |dep_id| {
                try deps.append(self.allocator, try self.allocator.dupe(u8, dep_id));
                self.allocator.free(name);
            } else {
                try deps.append(self.allocator, name);
            }
        }

        return try deps.toOwnedSlice(self.allocator);
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
        .prompt_catalog = null,
        .imported_prompts = std.StringHashMap(PromptDefinitionInfo).init(allocator),
    };
    defer parser.deinit();

    try std.testing.expectEqual(@as(?u8, ' '), parser.peek());

    parser.skipWhitespace();
    try std.testing.expectEqual(@as(?u8, 'h'), parser.peek());

    _ = parser.advance();
    try std.testing.expectEqual(@as(?u8, 'e'), parser.peek());
}
