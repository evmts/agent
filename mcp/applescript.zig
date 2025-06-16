const std = @import("std");
const json = std.json;
const process = std.process;
const io = std.io;

// MCP Protocol Types
const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?json.Value = null,
    id: ?json.Value = null,
};

const JsonRpcResponse = struct {
    jsonrpc: []const u8 = "2.0",
    result: ?json.Value = null,
    error: ?JsonRpcError = null,
    id: ?json.Value = null,
};

const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?json.Value = null,
};

const Tool = struct {
    name: []const u8,
    description: []const u8,
    inputSchema: json.Value,
};

const InitializeParams = struct {
    protocolVersion: []const u8,
    capabilities: struct {
        roots: ?struct {
            listChanged: ?bool = null,
        } = null,
        sampling: ?struct {} = null,
    },
    clientInfo: struct {
        name: []const u8,
        version: ?[]const u8 = null,
    },
};

const InitializeResult = struct {
    protocolVersion: []const u8 = "2024-11-05",
    capabilities: struct {
        logging: ?struct {} = null,
        prompts: ?struct {
            listChanged: ?bool = null,
        } = null,
        resources: ?struct {
            subscribe: ?bool = null,
            listChanged: ?bool = null,
        } = null,
        tools: ?struct {
            listChanged: ?bool = null,
        } = null,
    },
    serverInfo: struct {
        name: []const u8,
        version: []const u8,
    },
};

const CallToolParams = struct {
    name: []const u8,
    arguments: ?json.ObjectMap = null,
};

const TextContent = struct {
    type: []const u8 = "text",
    text: []const u8,
};

pub const AppleScriptMcpServer = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) AppleScriptMcpServer {
        return .{
            .allocator = allocator,
            .stdin = io.getStdIn(),
            .stdout = io.getStdOut(),
            .stderr = io.getStdErr(),
        };
    }

    pub fn run(self: *AppleScriptMcpServer) !void {
        self.log("AppleScript MCP server starting", .{});

        var buffer: [1024 * 1024]u8 = undefined;
        var fixed_buffer_stream = io.fixedBufferStream(&buffer);
        const reader = self.stdin.reader();

        while (true) {
            // Read until we get a complete line
            fixed_buffer_stream.reset();
            try reader.streamUntilDelimiter(fixed_buffer_stream.writer(), '\n', buffer.len);
            const line = fixed_buffer_stream.getWritten();

            if (line.len == 0) continue;

            // Parse the JSON-RPC request
            const parsed = try json.parseFromSlice(JsonRpcRequest, self.allocator, line, .{
                .ignore_unknown_fields = true,
            });
            defer parsed.deinit();

            const request = parsed.value;

            // Handle the request
            const response = try self.handleRequest(request);
            defer response.deinit();

            // Write the response
            try json.stringify(response.value, .{}, self.stdout.writer());
            try self.stdout.writer().writeByte('\n');
        }
    }

    fn handleRequest(self: *AppleScriptMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        if (std.mem.eql(u8, request.method, "initialize")) {
            return self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            return self.handleListTools(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            return self.handleCallTool(request);
        } else {
            return self.createErrorResponse(request.id, -32601, "Method not found");
        }
    }

    fn handleInitialize(self: *AppleScriptMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        self.initialized = true;
        
        const result = InitializeResult{
            .capabilities = .{
                .tools = .{
                    .listChanged = false,
                },
            },
            .serverInfo = .{
                .name = "applescript-mcp",
                .version = "0.1.0",
            },
        };

        var response_json = try json.valueFromType(self.allocator, InitializeResult, result);
        defer response_json.deinit(self.allocator);

        const response = JsonRpcResponse{
            .result = response_json.value,
            .id = request.id,
        };

        return json.parseFromValue(JsonRpcResponse, self.allocator, try json.valueFromType(self.allocator, JsonRpcResponse, response).value, .{});
    }

    fn handleListTools(self: *AppleScriptMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        const tools = [_]Tool{
            .{
                .name = "applescript_execute",
                .description = 
                \\Run AppleScript code to interact with Mac applications and system features. This tool can access and manipulate data in Notes, Calendar, Contacts, Messages, Mail, Finder, Safari, and other Apple applications. Common use cases include but not limited to:
                \\- Retrieve or create notes in Apple Notes
                \\- Access or add calendar events and appointments
                \\- List contacts or modify contact details
                \\- Search for and organize files using Spotlight or Finder
                \\- Get system information like battery status, disk space, or network details
                \\- Read or organize browser bookmarks or history
                \\- Access or send emails, messages, or other communications
                \\- Read, write, or manage file contents
                \\- Execute shell commands and capture the output
                ,
                .inputSchema = json.Value{
                    .object = blk: {
                        var map = json.ObjectMap.init(self.allocator);
                        try map.put("type", json.Value{ .string = "object" });
                        
                        var props = json.ObjectMap.init(self.allocator);
                        var code_snippet = json.ObjectMap.init(self.allocator);
                        try code_snippet.put("type", json.Value{ .string = "string" });
                        try code_snippet.put("description", json.Value{ .string = "Multi-line AppleScript code to execute." });
                        try props.put("code_snippet", json.Value{ .object = code_snippet });
                        
                        var timeout = json.ObjectMap.init(self.allocator);
                        try timeout.put("type", json.Value{ .string = "integer" });
                        try timeout.put("description", json.Value{ .string = "Command execution timeout in seconds (default: 60)" });
                        try props.put("timeout", json.Value{ .object = timeout });
                        
                        try map.put("properties", json.Value{ .object = props });
                        
                        var required = json.Array.init(self.allocator);
                        try required.append(json.Value{ .string = "code_snippet" });
                        try map.put("required", json.Value{ .array = required });
                        
                        break :blk map;
                    },
                },
            },
        };

        var tools_array = json.Array.init(self.allocator);
        for (tools) |tool| {
            var tool_obj = json.ObjectMap.init(self.allocator);
            try tool_obj.put("name", json.Value{ .string = tool.name });
            try tool_obj.put("description", json.Value{ .string = tool.description });
            try tool_obj.put("inputSchema", tool.inputSchema);
            try tools_array.append(json.Value{ .object = tool_obj });
        }

        var result_obj = json.ObjectMap.init(self.allocator);
        try result_obj.put("tools", json.Value{ .array = tools_array });

        const response = JsonRpcResponse{
            .result = json.Value{ .object = result_obj },
            .id = request.id,
        };

        return json.parseFromValue(JsonRpcResponse, self.allocator, try json.valueFromType(self.allocator, JsonRpcResponse, response).value, .{});
    }

    fn handleCallTool(self: *AppleScriptMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        if (request.params == null) {
            return self.createErrorResponse(request.id, -32602, "Invalid params");
        }

        const params = request.params.?.object;
        const name = params.get("name") orelse return self.createErrorResponse(request.id, -32602, "Missing tool name");
        
        if (!std.mem.eql(u8, name.string, "applescript_execute")) {
            return self.createErrorResponse(request.id, -32602, "Unknown tool");
        }

        const arguments = params.get("arguments") orelse return self.createErrorResponse(request.id, -32602, "Missing arguments");
        const args_obj = arguments.object;
        const code_snippet = args_obj.get("code_snippet") orelse return self.createErrorResponse(request.id, -32602, "Missing code_snippet");
        
        const timeout_value = args_obj.get("timeout");
        const timeout: u64 = if (timeout_value) |t| @intCast(t.integer) else 60;

        // Execute the AppleScript
        const result = try self.executeAppleScript(code_snippet.string, timeout);
        defer self.allocator.free(result);

        // Create response content
        var content_array = json.Array.init(self.allocator);
        var content_obj = json.ObjectMap.init(self.allocator);
        try content_obj.put("type", json.Value{ .string = "text" });
        try content_obj.put("text", json.Value{ .string = result });
        try content_array.append(json.Value{ .object = content_obj });

        var result_obj = json.ObjectMap.init(self.allocator);
        try result_obj.put("content", json.Value{ .array = content_array });

        const response = JsonRpcResponse{
            .result = json.Value{ .object = result_obj },
            .id = request.id,
        };

        return json.parseFromValue(JsonRpcResponse, self.allocator, try json.valueFromType(self.allocator, JsonRpcResponse, response).value, .{});
    }

    fn executeAppleScript(self: *AppleScriptMcpServer, code: []const u8, timeout: u64) ![]u8 {
        _ = timeout; // TODO: Implement timeout
        
        // Create a temporary file for the AppleScript
        const tmp_dir = std.fs.tmpDir(.{});
        const tmp_name = try std.fmt.allocPrint(self.allocator, "applescript_{d}.scpt", .{std.time.milliTimestamp()});
        defer self.allocator.free(tmp_name);

        const tmp_file = try tmp_dir.createFile(tmp_name, .{});
        defer tmp_file.close();
        defer tmp_dir.deleteFile(tmp_name) catch {};

        try tmp_file.writeAll(code);

        // Build the osascript command
        const argv = [_][]const u8{ "/usr/bin/osascript", tmp_name };
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &argv,
            .cwd_dir = tmp_dir,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            return try std.fmt.allocPrint(self.allocator, "AppleScript execution failed: {s}", .{result.stderr});
        }

        return try self.allocator.dupe(u8, result.stdout);
    }

    fn createErrorResponse(self: *AppleScriptMcpServer, id: ?json.Value, code: i32, message: []const u8) !json.Parsed(JsonRpcResponse) {
        const response = JsonRpcResponse{
            .error = JsonRpcError{
                .code = code,
                .message = message,
            },
            .id = id,
        };

        return json.parseFromValue(JsonRpcResponse, self.allocator, try json.valueFromType(self.allocator, JsonRpcResponse, response).value, .{});
    }

    fn log(self: *AppleScriptMcpServer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.stderr.writer(), "[applescript-mcp] " ++ format ++ "\n", args) catch {};
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = AppleScriptMcpServer.init(allocator);
    try server.run();
}