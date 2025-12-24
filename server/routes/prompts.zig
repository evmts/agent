//! Prompt API Routes (Phase 09)
//!
//! Implements the prompt management API from docs/workflows-engineering.md:
//! - POST   /api/prompts/parse             # Parse .prompt.md file
//! - POST   /api/prompts/render            # Render prompt with inputs

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const workflows = @import("../workflows/mod.zig");
const json = @import("../lib/json.zig");
const filesystem = @import("../ai/tools/filesystem.zig");

const log = std.log.scoped(.prompt_api);

// ============================================================================
// Request/Response Types
// ============================================================================

const ParsePromptRequest = struct {
    source: []const u8, // .prompt.md file contents
    file_path: ?[]const u8 = null, // Optional file path for error messages
};

const RenderPromptRequest = struct {
    prompt_path: []const u8, // Path to .prompt.md file
    inputs: std.json.Value, // Input data for template rendering
};

// ============================================================================
// POST /api/prompts/parse
// ============================================================================

/// Parse a .prompt.md file and return its definition
pub fn parse(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing request body" }, .{});
        return;
    };

    const parsed = std.json.parseFromSlice(
        ParsePromptRequest,
        ctx.allocator,
        body,
        .{},
    ) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid JSON" }, .{});
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    // Parse prompt using the prompt parser
    var prompt_def = workflows.parsePrompt(ctx.allocator, request.source) catch |err| {
        res.status = 400;
        const err_msg = switch (err) {
            error.ParseError => "Failed to parse prompt frontmatter",
            error.InvalidSchema => "Invalid type schema definition",
            error.MissingField => "Missing required field in frontmatter",
            error.ValidationFailed => "Prompt validation failed",
            else => "Parse error",
        };
        try res.json(.{ .@"error" = err_msg }, .{});
        return;
    };
    defer prompt_def.deinit();

    // Build response with prompt metadata
    var response = std.json.ObjectMap.init(ctx.allocator);
    defer response.deinit();

    try response.put("name", .{ .string = prompt_def.name });
    try response.put("client", .{ .string = prompt_def.client });
    try response.put("type", .{ .string = prompt_def.prompt_type });

    // Convert schemas to JSON (they're already std.json.Value)
    try response.put("inputs_schema", prompt_def.inputs_schema);
    try response.put("output_schema", prompt_def.output_schema);
    try response.put("max_turns", .{ .integer = @intCast(prompt_def.max_turns) });

    // Convert to string manually since httpz can't serialize std.json.Value
    const response_str = try json.valueToString(ctx.allocator, .{ .object = response });
    defer ctx.allocator.free(response_str);

    res.body = response_str;
}

// ============================================================================
// POST /api/prompts/render
// ============================================================================

/// Render a prompt template with given inputs
pub fn render(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing request body" }, .{});
        return;
    };

    const parsed = std.json.parseFromSlice(
        RenderPromptRequest,
        ctx.allocator,
        body,
        .{},
    ) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid JSON" }, .{});
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    const cwd = std.process.getCwdAlloc(ctx.allocator) catch {
        res.status = 500;
        try res.json(.{ .@"error" = "Failed to resolve workspace" }, .{});
        return;
    };
    defer ctx.allocator.free(cwd);

    const resolved_path = try filesystem.resolveAndValidatePathSecure(
        ctx.allocator,
        request.prompt_path,
        cwd,
    ) orelse {
        res.status = 403;
        try res.json(.{ .@"error" = "Invalid prompt path" }, .{});
        return;
    };
    defer ctx.allocator.free(resolved_path);

    const prompts_root = std.fs.path.join(ctx.allocator, &.{ cwd, ".plue", "prompts" }) catch {
        res.status = 500;
        try res.json(.{ .@"error" = "Failed to resolve prompts directory" }, .{});
        return;
    };
    defer ctx.allocator.free(prompts_root);

    if (!std.mem.startsWith(u8, resolved_path, prompts_root) or
        (resolved_path.len > prompts_root.len and resolved_path[prompts_root.len] != '/') or
        !std.mem.endsWith(u8, resolved_path, ".prompt.md"))
    {
        res.status = 403;
        try res.json(.{ .@"error" = "Prompt path must be within .plue/prompts and end with .prompt.md" }, .{});
        return;
    }

    // Read prompt file
    const prompt_source = filesystem.readFileContents(ctx.allocator, resolved_path) catch {
        res.status = 404;
        try res.json(.{ .@"error" = "Prompt file not found" }, .{});
        return;
    };
    defer ctx.allocator.free(prompt_source);

    // Parse prompt
    var prompt_def = workflows.parsePrompt(ctx.allocator, prompt_source) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Failed to parse prompt" }, .{});
        return;
    };
    defer prompt_def.deinit();

    const inputs_json = json.valueToString(ctx.allocator, request.inputs) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid inputs" }, .{});
        return;
    };
    defer ctx.allocator.free(inputs_json);

    // Render template
    const rendered = workflows.renderTemplate(
        ctx.allocator,
        prompt_def.body_template,
        inputs_json,
    ) catch {
        res.status = 500;
        try res.json(.{ .@"error" = "Template rendering failed" }, .{});
        return;
    };
    defer ctx.allocator.free(rendered);

    // Return rendered prompt
    try res.json(.{ .rendered = rendered }, .{});
}
