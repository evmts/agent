const std = @import("std");

// C FFI structures matching Rust definitions
const CPromptDefinition = extern struct {
    name: [*:0]const u8,
    client: [*:0]const u8,
    prompt_type: [*:0]const u8,
    inputs_schema_json: [*:0]const u8,
    output_schema_json: [*:0]const u8,
    tools_json: [*:0]const u8,
    body_template: [*:0]const u8,
    max_turns: u32,
};

const CPromptError = extern struct {
    message: [*:0]const u8,
};

// Rust FFI functions
extern "c" fn prompt_parser_parse(
    content: [*:0]const u8,
    out_def: *?*CPromptDefinition,
    out_error: *?*CPromptError,
) bool;

extern "c" fn prompt_parser_free_definition(def: ?*CPromptDefinition) void;
extern "c" fn prompt_parser_free_error(error_ptr: ?*CPromptError) void;

// Schema validation FFI
extern "c" fn prompt_parser_validate_json(
    schema_json: [*:0]const u8,
    data_json: [*:0]const u8,
    out_error_count: *usize,
    out_errors: *?[*][*:0]const u8,
    out_error: *?*CPromptError,
) bool;

extern "c" fn prompt_parser_free_validation_errors(
    errors: [*][*:0]const u8,
    count: usize,
) void;

// Template rendering FFI
extern "c" fn prompt_parser_render_template(
    template_str: [*:0]const u8,
    inputs_json: [*:0]const u8,
    out_rendered: *?[*:0]u8,
    out_error: *?*CPromptError,
) bool;

extern "c" fn prompt_parser_free_string(s: [*:0]u8) void;

pub const PromptError = error{
    ParseError,
    MissingField,
    InvalidSchema,
    ValidationFailed,
    OutOfMemory,
};

pub const PromptDefinition = struct {
    name: []const u8,
    client: []const u8,
    prompt_type: []const u8,
    inputs_schema: std.json.Value,
    output_schema: std.json.Value,
    tools_json: []const u8,
    body_template: []const u8,
    max_turns: u32,
    allocator: std.mem.Allocator,
    // Store parsed JSON objects for proper cleanup
    inputs_parsed: std.json.Parsed(std.json.Value),
    output_parsed: std.json.Parsed(std.json.Value),

    pub fn deinit(self: *PromptDefinition) void {
        self.allocator.free(self.name);
        self.allocator.free(self.client);
        self.allocator.free(self.prompt_type);
        self.allocator.free(self.tools_json);
        self.allocator.free(self.body_template);
        self.inputs_parsed.deinit();
        self.output_parsed.deinit();
    }

    pub fn toJson(self: *const PromptDefinition, allocator: std.mem.Allocator) !std.json.Value {
        var obj = std.json.ObjectMap.init(allocator);
        errdefer obj.deinit();

        try obj.put("name", .{ .string = self.name });
        try obj.put("client", .{ .string = self.client });
        try obj.put("prompt_type", .{ .string = self.prompt_type });
        try obj.put("max_turns", .{ .integer = @intCast(self.max_turns) });
        try obj.put("inputs_schema", self.inputs_schema);
        try obj.put("output_schema", self.output_schema);
        if (self.tools_json.len > 0) {
            const parsed_tools = std.json.parseFromSlice(
                std.json.Value,
                allocator,
                self.tools_json,
                .{},
            ) catch null;
            if (parsed_tools) |parsed| {
                try obj.put("tools", parsed.value);
            } else {
                try obj.put("tools", .null);
            }
        } else {
            try obj.put("tools", .null);
        }
        try obj.put("body_template", .{ .string = self.body_template });

        return .{ .object = obj };
    }
};

/// Parse a prompt file from string content
pub fn parsePrompt(allocator: std.mem.Allocator, content: []const u8) !PromptDefinition {
    // Ensure content is null-terminated
    const content_z = try allocator.dupeZ(u8, content);
    defer allocator.free(content_z);

    var out_def: ?*CPromptDefinition = null;
    var out_error: ?*CPromptError = null;

    const success = prompt_parser_parse(content_z.ptr, &out_def, &out_error);

    if (!success) {
        defer if (out_error) |err| prompt_parser_free_error(err);

        if (out_error) |err| {
            const msg = std.mem.span(err.message);
            // Use debug level to avoid test failures on expected parse errors
            std.log.debug("Prompt parse error: {s}", .{msg});
            return PromptError.ParseError;
        }
        return PromptError.ParseError;
    }

    const c_def = out_def orelse return PromptError.ParseError;
    defer prompt_parser_free_definition(c_def);

    // Copy strings to Zig-managed memory
    const name = try allocator.dupe(u8, std.mem.span(c_def.name));
    errdefer allocator.free(name);

    const client = try allocator.dupe(u8, std.mem.span(c_def.client));
    errdefer allocator.free(client);

    const prompt_type = try allocator.dupe(u8, std.mem.span(c_def.prompt_type));
    errdefer allocator.free(prompt_type);

    const tools_json = try allocator.dupe(u8, std.mem.span(c_def.tools_json));
    errdefer allocator.free(tools_json);

    const body_template = try allocator.dupe(u8, std.mem.span(c_def.body_template));
    errdefer allocator.free(body_template);

    // Parse JSON schemas
    const inputs_schema_str = std.mem.span(c_def.inputs_schema_json);
    const output_schema_str = std.mem.span(c_def.output_schema_json);

    const inputs_schema = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        inputs_schema_str,
        .{},
    );
    errdefer inputs_schema.deinit();

    const output_schema = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        output_schema_str,
        .{},
    );
    errdefer output_schema.deinit();

    return PromptDefinition{
        .name = name,
        .client = client,
        .prompt_type = prompt_type,
        .inputs_schema = inputs_schema.value,
        .output_schema = output_schema.value,
        .tools_json = tools_json,
        .body_template = body_template,
        .max_turns = c_def.max_turns,
        .allocator = allocator,
        .inputs_parsed = inputs_schema,
        .output_parsed = output_schema,
    };
}

/// Parse a prompt file from filesystem path
pub fn parsePromptFile(allocator: std.mem.Allocator, file_path: []const u8) !PromptDefinition {
    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    return parsePrompt(allocator, content);
}

// ============================================================================
// Tests
// ============================================================================

test "parsePrompt basic" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\name: TestPrompt
        \\client: anthropic/claude-sonnet
        \\
        \\inputs:
        \\  query: string
        \\
        \\output:
        \\  result: string
        \\---
        \\
        \\Answer this: {{ query }}
    ;

    var def = try parsePrompt(allocator, content);
    defer def.deinit();

    try std.testing.expectEqualStrings("TestPrompt", def.name);
    try std.testing.expectEqualStrings("anthropic/claude-sonnet", def.client);
    try std.testing.expectEqualStrings("llm", def.prompt_type);
    try std.testing.expectEqual(@as(u32, 10), def.max_turns);
}

test "parsePrompt with agent type" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\name: AgentPrompt
        \\client: anthropic/claude-sonnet
        \\type: agent
        \\max_turns: 20
        \\
        \\inputs:
        \\  goal: string
        \\
        \\output:
        \\  status: string
        \\---
        \\
        \\You are an agent. Goal: {{ goal }}
    ;

    var def = try parsePrompt(allocator, content);
    defer def.deinit();

    try std.testing.expectEqualStrings("AgentPrompt", def.name);
    try std.testing.expectEqualStrings("agent", def.prompt_type);
    try std.testing.expectEqual(@as(u32, 20), def.max_turns);
}

test "parsePrompt with optional and array types" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\name: ComplexPrompt
        \\
        \\inputs:
        \\  required: string
        \\  optional: string?
        \\  items: string[]
        \\
        \\output:
        \\  data: string
        \\---
        \\
        \\Process data
    ;

    var def = try parsePrompt(allocator, content);
    defer def.deinit();

    try std.testing.expectEqualStrings("ComplexPrompt", def.name);

    // Check that schemas were parsed (basic check)
    try std.testing.expect(def.inputs_schema != .null);
    try std.testing.expect(def.output_schema != .null);
}

test "parsePrompt with enum type" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\name: EnumPrompt
        \\
        \\inputs:
        \\  level: info | warning | error
        \\
        \\output:
        \\  status: string
        \\---
        \\
        \\Handle level
    ;

    var def = try parsePrompt(allocator, content);
    defer def.deinit();

    try std.testing.expectEqualStrings("EnumPrompt", def.name);
}

test "parsePrompt invalid - missing name" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\client: anthropic/claude-sonnet
        \\---
        \\
        \\No name field
    ;

    const result = parsePrompt(allocator, content);
    try std.testing.expectError(PromptError.ParseError, result);
}

// ============================================================================
// Schema Validation
// ============================================================================

pub const ValidationResult = struct {
    valid: bool,
    errors: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ValidationResult) void {
        for (self.errors) |err| {
            self.allocator.free(err);
        }
        self.allocator.free(self.errors);
    }
};

/// Validate JSON data against a JSON Schema
/// TODO: Re-implement validation logic.
pub fn validateJson(
    allocator: std.mem.Allocator,
    schema: std.json.Value,
    data: std.json.Value,
) !ValidationResult {
    _ = schema;
    _ = data;

    // For MVP, skip validation and return success
    return ValidationResult{
        .valid = true,
        .errors = try allocator.alloc([]const u8, 0),
        .allocator = allocator,
    };
}


// ============================================================================
// Template Rendering
// ============================================================================

/// Render a Jinja2 template with JSON inputs
pub fn renderTemplate(
    allocator: std.mem.Allocator,
    template: []const u8,
    inputs_json: []const u8,
) ![]const u8 {
    // Ensure null termination
    const template_z = try allocator.dupeZ(u8, template);
    defer allocator.free(template_z);

    const inputs_z = try allocator.dupeZ(u8, inputs_json);
    defer allocator.free(inputs_z);

    var out_rendered: ?[*:0]u8 = null;
    var out_error: ?*CPromptError = null;

    const success = prompt_parser_render_template(
        template_z.ptr,
        inputs_z.ptr,
        &out_rendered,
        &out_error,
    );

    if (!success) {
        defer if (out_error) |err| prompt_parser_free_error(err);

        if (out_error) |err| {
            const msg = std.mem.span(err.message);
            std.log.err("Template render error: {s}", .{msg});
            return PromptError.ParseError;
        }
        return PromptError.ParseError;
    }

    const rendered_ptr = out_rendered orelse return PromptError.ParseError;
    defer prompt_parser_free_string(rendered_ptr);

    // Copy the rendered string to allocator-managed memory
    const rendered_span = std.mem.span(rendered_ptr);
    return try allocator.dupe(u8, rendered_span);
}
