const std = @import("std");
const testing = std.testing;
const job_graph = @import("job_graph.zig");
const ExecutionContext = job_graph.ExecutionContext;

pub const ExpressionError = error{
    InvalidExpression,
    UndefinedVariable,
    TypeError,
    FunctionNotFound,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const ExpressionValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    null_value,
    
    pub fn deinit(self: *ExpressionValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }
    
    pub fn toString(self: *const ExpressionValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .string => |s| allocator.dupe(u8, s),
            .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}),
            .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
            .null_value => allocator.dupe(u8, ""),
        };
    }
    
    pub fn toBool(self: *const ExpressionValue) bool {
        return switch (self.*) {
            .string => |s| s.len > 0,
            .number => |n| n != 0.0,
            .boolean => |b| b,
            .null_value => false,
        };
    }
};

pub const ExpressionEvaluator = struct {
    allocator: std.mem.Allocator,
    context: *const ExecutionContext,
    
    pub fn init(allocator: std.mem.Allocator, context: *const ExecutionContext) ExpressionEvaluator {
        return ExpressionEvaluator{
            .allocator = allocator,
            .context = context,
        };
    }
    
    pub fn evaluate(self: *const ExpressionEvaluator, expression: []const u8) !ExpressionValue {
        // Simplified expression evaluation
        // In production, this would use a proper expression parser
        
        // Handle simple variable access (e.g., "github.ref")
        if (std.mem.startsWith(u8, expression, "github.")) {
            return self.evaluateGitHubContext(expression[7..]);
        }
        
        // Handle environment variables (e.g., "env.VERSION")
        if (std.mem.startsWith(u8, expression, "env.")) {
            const var_name = expression[4..];
            if (self.context.env.get(var_name)) |value| {
                return ExpressionValue{ .string = try self.allocator.dupe(u8, value) };
            }
            return ExpressionValue{ .null_value = {} };
        }
        
        // Handle vars access (e.g., "vars.CONFIG")
        if (std.mem.startsWith(u8, expression, "vars.")) {
            const var_name = expression[5..];
            if (self.context.vars.get(var_name)) |value| {
                return ExpressionValue{ .string = try self.allocator.dupe(u8, value) };
            }
            return ExpressionValue{ .null_value = {} };
        }
        
        // Handle simple equality checks (e.g., "github.ref == 'refs/heads/main'")
        if (std.mem.indexOf(u8, expression, " == ")) |eq_pos| {
            const left_expr = std.mem.trim(u8, expression[0..eq_pos], " ");
            const right_expr = std.mem.trim(u8, expression[eq_pos + 4..], " ");
            
            var left_value = try self.evaluate(left_expr);
            defer left_value.deinit(self.allocator);
            
            var right_value = try self.evaluateLiteral(right_expr);
            defer right_value.deinit(self.allocator);
            
            const left_str = try left_value.toString(self.allocator);
            defer self.allocator.free(left_str);
            
            const right_str = try right_value.toString(self.allocator);
            defer self.allocator.free(right_str);
            
            return ExpressionValue{ .boolean = std.mem.eql(u8, left_str, right_str) };
        }
        
        // Handle simple inequality checks (e.g., "github.actor != 'dependabot'")
        if (std.mem.indexOf(u8, expression, " != ")) |neq_pos| {
            const left_expr = std.mem.trim(u8, expression[0..neq_pos], " ");
            const right_expr = std.mem.trim(u8, expression[neq_pos + 4..], " ");
            
            var left_value = try self.evaluate(left_expr);
            defer left_value.deinit(self.allocator);
            
            var right_value = try self.evaluateLiteral(right_expr);
            defer right_value.deinit(self.allocator);
            
            const left_str = try left_value.toString(self.allocator);
            defer self.allocator.free(left_str);
            
            const right_str = try right_value.toString(self.allocator);
            defer self.allocator.free(right_str);
            
            return ExpressionValue{ .boolean = !std.mem.eql(u8, left_str, right_str) };
        }
        
        // Handle logical AND (e.g., "condition1 && condition2")
        if (std.mem.indexOf(u8, expression, " && ")) |and_pos| {
            const left_expr = std.mem.trim(u8, expression[0..and_pos], " ");
            const right_expr = std.mem.trim(u8, expression[and_pos + 4..], " ");
            
            var left_value = try self.evaluate(left_expr);
            defer left_value.deinit(self.allocator);
            
            // Short-circuit evaluation
            if (!left_value.toBool()) {
                return ExpressionValue{ .boolean = false };
            }
            
            var right_value = try self.evaluate(right_expr);
            defer right_value.deinit(self.allocator);
            
            return ExpressionValue{ .boolean = right_value.toBool() };
        }
        
        // Handle logical OR (e.g., "condition1 || condition2")
        if (std.mem.indexOf(u8, expression, " || ")) |or_pos| {
            const left_expr = std.mem.trim(u8, expression[0..or_pos], " ");
            const right_expr = std.mem.trim(u8, expression[or_pos + 4..], " ");
            
            var left_value = try self.evaluate(left_expr);
            defer left_value.deinit(self.allocator);
            
            // Short-circuit evaluation
            if (left_value.toBool()) {
                return ExpressionValue{ .boolean = true };
            }
            
            var right_value = try self.evaluate(right_expr);
            defer right_value.deinit(self.allocator);
            
            return ExpressionValue{ .boolean = right_value.toBool() };
        }
        
        // Handle function calls (e.g., "startsWith(github.ref, 'refs/heads/')")
        if (std.mem.indexOf(u8, expression, "(")) |paren_pos| {
            const func_name = std.mem.trim(u8, expression[0..paren_pos], " ");
            const args_section = expression[paren_pos + 1..];
            
            if (std.mem.lastIndexOf(u8, args_section, ")")) |close_paren| {
                const args_str = args_section[0..close_paren];
                return self.evaluateFunction(func_name, args_str);
            }
        }
        
        // If nothing matches, try to evaluate as a literal
        return self.evaluateLiteral(expression);
    }
    
    fn evaluateGitHubContext(self: *const ExpressionEvaluator, field: []const u8) !ExpressionValue {
        if (std.mem.eql(u8, field, "ref")) {
            return ExpressionValue{ .string = try self.allocator.dupe(u8, self.context.github.ref) };
        } else if (std.mem.eql(u8, field, "sha")) {
            return ExpressionValue{ .string = try self.allocator.dupe(u8, self.context.github.sha) };
        } else if (std.mem.eql(u8, field, "actor")) {
            return ExpressionValue{ .string = try self.allocator.dupe(u8, self.context.github.actor) };
        } else if (std.mem.eql(u8, field, "event_name")) {
            return ExpressionValue{ .string = try self.allocator.dupe(u8, self.context.github.event_name) };
        } else if (std.mem.eql(u8, field, "repository")) {
            return ExpressionValue{ .string = try self.allocator.dupe(u8, self.context.github.repository) };
        } else if (std.mem.eql(u8, field, "run_id")) {
            return ExpressionValue{ .number = @floatFromInt(self.context.github.run_id) };
        } else if (std.mem.eql(u8, field, "run_number")) {
            return ExpressionValue{ .number = @floatFromInt(self.context.github.run_number) };
        }
        
        return ExpressionError.UndefinedVariable;
    }
    
    fn evaluateLiteral(self: *const ExpressionEvaluator, literal: []const u8) !ExpressionValue {
        const trimmed = std.mem.trim(u8, literal, " \t\n\r");
        
        // Handle string literals (single or double quotes)
        if ((std.mem.startsWith(u8, trimmed, "'") and std.mem.endsWith(u8, trimmed, "'")) or
            (std.mem.startsWith(u8, trimmed, "\"") and std.mem.endsWith(u8, trimmed, "\""))) {
            const content = trimmed[1 .. trimmed.len - 1];
            return ExpressionValue{ .string = try self.allocator.dupe(u8, content) };
        }
        
        // Handle boolean literals
        if (std.mem.eql(u8, trimmed, "true")) {
            return ExpressionValue{ .boolean = true };
        } else if (std.mem.eql(u8, trimmed, "false")) {
            return ExpressionValue{ .boolean = false };
        }
        
        // Handle null literal
        if (std.mem.eql(u8, trimmed, "null")) {
            return ExpressionValue{ .null_value = {} };
        }
        
        // Handle number literals
        if (std.fmt.parseFloat(f64, trimmed)) |number| {
            return ExpressionValue{ .number = number };
        } else |_| {
            // If it's not a number, treat as string literal without quotes
            return ExpressionValue{ .string = try self.allocator.dupe(u8, trimmed) };
        }
    }
    
    fn evaluateFunction(self: *const ExpressionEvaluator, func_name: []const u8, args_str: []const u8) !ExpressionValue {
        if (std.mem.eql(u8, func_name, "startsWith")) {
            return self.evaluateStartsWithFunction(args_str);
        } else if (std.mem.eql(u8, func_name, "endsWith")) {
            return self.evaluateEndsWithFunction(args_str);
        } else if (std.mem.eql(u8, func_name, "contains")) {
            return self.evaluateContainsFunction(args_str);
        } else if (std.mem.eql(u8, func_name, "format")) {
            return self.evaluateFormatFunction(args_str);
        } else if (std.mem.eql(u8, func_name, "join")) {
            return self.evaluateJoinFunction(args_str);
        }
        
        return ExpressionError.FunctionNotFound;
    }
    
    fn evaluateStartsWithFunction(self: *const ExpressionEvaluator, args_str: []const u8) !ExpressionValue {
        const args = try self.parseArguments(args_str);
        defer {
            for (args) |*arg| {
                arg.deinit(self.allocator);
            }
            self.allocator.free(args);
        }
        
        if (args.len != 2) {
            return ExpressionError.InvalidExpression;
        }
        
        const string_val = try args[0].toString(self.allocator);
        defer self.allocator.free(string_val);
        
        const prefix_val = try args[1].toString(self.allocator);
        defer self.allocator.free(prefix_val);
        
        return ExpressionValue{ .boolean = std.mem.startsWith(u8, string_val, prefix_val) };
    }
    
    fn evaluateEndsWithFunction(self: *const ExpressionEvaluator, args_str: []const u8) !ExpressionValue {
        const args = try self.parseArguments(args_str);
        defer {
            for (args) |*arg| {
                arg.deinit(self.allocator);
            }
            self.allocator.free(args);
        }
        
        if (args.len != 2) {
            return ExpressionError.InvalidExpression;
        }
        
        const string_val = try args[0].toString(self.allocator);
        defer self.allocator.free(string_val);
        
        const suffix_val = try args[1].toString(self.allocator);
        defer self.allocator.free(suffix_val);
        
        return ExpressionValue{ .boolean = std.mem.endsWith(u8, string_val, suffix_val) };
    }
    
    fn evaluateContainsFunction(self: *const ExpressionEvaluator, args_str: []const u8) !ExpressionValue {
        const args = try self.parseArguments(args_str);
        defer {
            for (args) |*arg| {
                arg.deinit(self.allocator);
            }
            self.allocator.free(args);
        }
        
        if (args.len != 2) {
            return ExpressionError.InvalidExpression;
        }
        
        const string_val = try args[0].toString(self.allocator);
        defer self.allocator.free(string_val);
        
        const search_val = try args[1].toString(self.allocator);
        defer self.allocator.free(search_val);
        
        return ExpressionValue{ .boolean = std.mem.indexOf(u8, string_val, search_val) != null };
    }
    
    fn evaluateFormatFunction(self: *const ExpressionEvaluator, args_str: []const u8) !ExpressionValue {
        const args = try self.parseArguments(args_str);
        defer {
            for (args) |*arg| {
                arg.deinit(self.allocator);
            }
            self.allocator.free(args);
        }
        
        if (args.len == 0) {
            return ExpressionError.InvalidExpression;
        }
        
        const format_str = try args[0].toString(self.allocator);
        defer self.allocator.free(format_str);
        
        // Simplified format function - just return the format string for now
        // In production, this would implement proper string formatting
        return ExpressionValue{ .string = try self.allocator.dupe(u8, format_str) };
    }
    
    fn evaluateJoinFunction(self: *const ExpressionEvaluator, args_str: []const u8) !ExpressionValue {
        const args = try self.parseArguments(args_str);
        defer {
            for (args) |*arg| {
                arg.deinit(self.allocator);
            }
            self.allocator.free(args);
        }
        
        if (args.len < 2) {
            return ExpressionError.InvalidExpression;
        }
        
        const separator = try args[1].toString(self.allocator);
        defer self.allocator.free(separator);
        
        // Simplified join - for now just return first argument
        // In production, this would properly join array elements
        return ExpressionValue{ .string = try args[0].toString(self.allocator) };
    }
    
    fn parseArguments(self: *const ExpressionEvaluator, args_str: []const u8) ![]ExpressionValue {
        var args = std.ArrayList(ExpressionValue).init(self.allocator);
        errdefer {
            for (args.items) |*arg| {
                arg.deinit(self.allocator);
            }
            args.deinit();
        }
        
        if (args_str.len == 0) {
            return args.toOwnedSlice();
        }
        
        // Simple argument parsing - split by comma (ignoring commas in quotes)
        var start: usize = 0;
        var in_quotes = false;
        var quote_char: u8 = 0;
        
        for (args_str, 0..) |char, i| {
            if (!in_quotes and (char == '\'' or char == '"')) {
                in_quotes = true;
                quote_char = char;
            } else if (in_quotes and char == quote_char) {
                in_quotes = false;
            } else if (!in_quotes and char == ',') {
                const arg_str = std.mem.trim(u8, args_str[start..i], " \t");
                if (arg_str.len > 0) {
                    const arg_value = try self.evaluate(arg_str);
                    try args.append(arg_value);
                }
                start = i + 1;
            }
        }
        
        // Handle last argument
        const last_arg_str = std.mem.trim(u8, args_str[start..], " \t");
        if (last_arg_str.len > 0) {
            const arg_value = try self.evaluate(last_arg_str);
            try args.append(arg_value);
        }
        
        return args.toOwnedSlice();
    }
    
    pub fn substitute(allocator: std.mem.Allocator, template: []const u8, context: *const ExecutionContext) ![]const u8 {
        const evaluator = ExpressionEvaluator.init(allocator, context);
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        var i: usize = 0;
        while (i < template.len) {
            if (i + 2 < template.len and 
                template[i] == '$' and template[i + 1] == '{' and template[i + 2] == '{') {
                
                // Find the closing }}
                if (std.mem.indexOf(u8, template[i + 3..], "}}")) |close_pos| {
                    const expr_content = template[i + 3 .. i + 3 + close_pos];
                    const trimmed_expr = std.mem.trim(u8, expr_content, " \t");
                    
                    var expr_value = evaluator.evaluate(trimmed_expr) catch |err| switch (err) {
                        error.UndefinedVariable => ExpressionValue{ .string = try allocator.dupe(u8, "") },
                        else => return err,
                    };
                    defer expr_value.deinit(allocator);
                    
                    const substituted = try expr_value.toString(allocator);
                    defer allocator.free(substituted);
                    
                    try result.appendSlice(substituted);
                    i = i + 3 + close_pos + 2; // Skip past }}
                } else {
                    // Malformed expression, just copy the character
                    try result.append(template[i]);
                    i += 1;
                }
            } else {
                try result.append(template[i]);
                i += 1;
            }
        }
        
        return result.toOwnedSlice();
    }
};

// Tests for Phase 4: Expression Evaluation and Context
test "evaluates GitHub context expressions" {
    const allocator = testing.allocator;
    
    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();
    
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    
    const context = ExecutionContext{
        .github = .{
            .ref = "refs/heads/main",
            .sha = "abc123def456",
            .actor = "user123",
            .event_name = "push",
        },
        .env = env,
        .vars = vars,
    };
    
    const expr_evaluator = ExpressionEvaluator.init(allocator, &context);
    
    // Test simple context access
    var ref_result = try expr_evaluator.evaluate("github.ref");
    defer ref_result.deinit(allocator);
    
    const ref_str = try ref_result.toString(allocator);
    defer allocator.free(ref_str);
    try testing.expectEqualStrings("refs/heads/main", ref_str);
    
    // Test conditional expressions
    var cond_result = try expr_evaluator.evaluate("github.ref == 'refs/heads/main'");
    defer cond_result.deinit(allocator);
    try testing.expect(cond_result.toBool());
    
    // Test complex expressions
    var complex_result = try expr_evaluator.evaluate("startsWith(github.ref, 'refs/heads/') && github.actor != 'dependabot'");
    defer complex_result.deinit(allocator);
    try testing.expect(complex_result.toBool());
}

test "substitutes expressions in workflow content" {
    const allocator = testing.allocator;
    
    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();
    
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    
    try env.put("VERSION", "1.2.3");
    
    const context = ExecutionContext{
        .env = env,
        .vars = vars,
        .github = .{
            .ref = "refs/heads/develop",
            .sha = "abc123",
            .actor = "testuser",
            .event_name = "push",
        },
    };
    
    const template = "Version: ${{ env.VERSION }}, Branch: ${{ github.ref }}";
    
    const substituted = try ExpressionEvaluator.substitute(allocator, template, &context);
    defer allocator.free(substituted);
    
    try testing.expectEqualStrings("Version: 1.2.3, Branch: refs/heads/develop", substituted);
}

test "handles function calls" {
    const allocator = testing.allocator;
    
    var env = std.StringHashMap([]const u8).init(allocator);
    defer env.deinit();
    
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    
    const context = ExecutionContext{
        .github = .{
            .ref = "refs/heads/feature/new-feature",
            .sha = "abc123",
            .actor = "developer",
            .event_name = "push",
        },
        .env = env,
        .vars = vars,
    };
    
    const expr_evaluator = ExpressionEvaluator.init(allocator, &context);
    
    // Test startsWith function
    var starts_with_result = try expr_evaluator.evaluate("startsWith(github.ref, 'refs/heads/feature/')");
    defer starts_with_result.deinit(allocator);
    try testing.expect(starts_with_result.toBool());
    
    // Test contains function
    var contains_result = try expr_evaluator.evaluate("contains(github.ref, 'feature')");
    defer contains_result.deinit(allocator);
    try testing.expect(contains_result.toBool());
}