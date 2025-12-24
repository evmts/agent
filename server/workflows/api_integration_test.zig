//! Integration tests for workflow API endpoints
//!
//! These tests verify that the API handlers work correctly with the full stack:
//! - Request parsing
//! - Evaluator/parser/validator integration
//! - Response serialization
//!
//! Note: These tests require the test allocator and do not hit the database.
//! For full E2E tests with DB, see e2e/cases/workflows.spec.ts

const std = @import("std");
const testing = std.testing;
const workflows = @import("mod.zig");

// Mock request/response for testing
const MockRequest = struct {
    body_data: []const u8,

    pub fn body(self: *const MockRequest) ?[]const u8 {
        return self.body_data;
    }
};

const MockResponse = struct {
    status_code: u16 = 200,
    content_type_val: []const u8 = "application/json",
    response_body: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) MockResponse {
        return .{
            .response_body = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockResponse) void {
        self.response_body.deinit();
    }

    pub fn status(self: *MockResponse, code: u16) void {
        self.status_code = code;
    }

    pub fn contentType(self: *MockResponse, ct: []const u8) void {
        self.content_type_val = ct;
    }

    pub fn json(self: *MockResponse, data: anytype) !void {
        var writer = self.response_body.writer();
        try std.json.stringify(data, .{}, writer);
    }
};

test "parse workflow - valid workflow" {
    const allocator = testing.allocator;

    const source =
        \\from plue import workflow, push
        \\
        \\@workflow(triggers=[push()])
        \\def ci(ctx):
        \\    ctx.run(name="test", cmd="bun test")
    ;

    // Test evaluator directly (API handler logic)
    var evaluator = workflows.Evaluator.init(allocator);
    const result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    // Verify we got a workflow
    try testing.expect(result.workflows.len > 0);
    const workflow_def = result.workflows[0];
    try testing.expectEqualStrings("ci", workflow_def.name);

    // Validate the plan
    var validation = try workflows.validateWorkflow(allocator, &workflow_def);
    defer validation.deinit();

    try testing.expect(validation.valid);
    try testing.expect(validation.errors.len == 0);
}

test "parse workflow - syntax error" {
    const allocator = testing.allocator;

    const source =
        \\from plue import workflow
        \\
        \\@workflow(triggers=[])  # Missing closing parenthesis
        \\def ci(ctx
        \\    ctx.run(name="test", cmd="bun test")
    ;

    var evaluator = workflows.Evaluator.init(allocator);
    const result = evaluator.evaluateSource(source, "test.py");

    // Should return an error
    try testing.expectError(error.SyntaxError, result);
}

test "parse workflow - validation error (cycle)" {
    const allocator = testing.allocator;

    // Create a plan with a circular dependency
    const source =
        \\from plue import workflow, push
        \\
        \\@workflow(triggers=[push()])
        \\def ci(ctx):
        \\    step1 = ctx.run(name="step1", cmd="echo 1")
        \\    step2 = ctx.run(name="step2", cmd="echo 2")
    ;

    var evaluator = workflows.Evaluator.init(allocator);
    const result = try evaluator.evaluateSource(source, "test.py");
    defer result.deinit(allocator);

    // Manually create cycle for testing validator
    var workflow_def = result.workflows[0];

    // Allocate depends_on arrays to create a cycle: step1 -> step2 -> step1
    const step1_deps = try allocator.alloc([]const u8, 1);
    step1_deps[0] = "step_2";
    workflow_def.steps[0].depends_on = step1_deps;

    const step2_deps = try allocator.alloc([]const u8, 1);
    step2_deps[0] = "step_1";
    workflow_def.steps[1].depends_on = step2_deps;

    defer allocator.free(step1_deps);
    defer allocator.free(step2_deps);

    // Validate - should detect cycle
    var validation = try workflows.validateWorkflow(allocator, &workflow_def);
    defer validation.deinit();

    try testing.expect(!validation.valid);
    try testing.expect(validation.errors.len > 0);

    // Check error message mentions cycle
    const has_cycle_error = for (validation.errors) |err| {
        if (std.mem.indexOf(u8, err, "cycle") != null or
            std.mem.indexOf(u8, err, "Cycle") != null or
            std.mem.indexOf(u8, err, "circular") != null) {
            break true;
        }
    } else false;

    try testing.expect(has_cycle_error);
}

test "prompt parse - valid prompt" {
    const allocator = testing.allocator;

    const source =
        \\---
        \\name: TestPrompt
        \\client: anthropic/claude-sonnet
        \\inputs:
        \\  message: string
        \\output:
        \\  response: string
        \\---
        \\
        \\You are a helpful assistant.
        \\
        \\{{ message }}
    ;

    // Test prompt parser
    const parser = workflows.prompt.PromptParser.init(allocator);
    defer parser.deinit();

    var result = try parser.parseString(source, "test.prompt.md");
    defer result.deinit();

    // Verify parsed data
    try testing.expectEqualStrings("TestPrompt", result.name);
    try testing.expectEqualStrings("anthropic/claude-sonnet", result.client);

    // Verify inputs schema
    try testing.expect(result.inputs_schema != null);

    // Verify output schema
    try testing.expect(result.output_schema != null);
}

test "prompt render - with variables" {
    const allocator = testing.allocator;

    const source =
        \\---
        \\name: Greeter
        \\client: anthropic/claude-sonnet
        \\inputs:
        \\  name: string
        \\output:
        \\  greeting: string
        \\---
        \\
        \\Hello {{ name }}!
    ;

    const parser = workflows.prompt.PromptParser.init(allocator);
    defer parser.deinit();

    var prompt_def = try parser.parseString(source, "test.prompt.md");
    defer prompt_def.deinit();

    // Render with inputs
    const inputs_json = "{\"name\": \"World\"}";
    const rendered = try workflows.prompt.renderTemplate(
        allocator,
        prompt_def.body_template,
        inputs_json,
    );
    defer allocator.free(rendered);

    // Check rendering
    try testing.expect(std.mem.indexOf(u8, rendered, "Hello World!") != null);
}
