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
    @"error": ?JsonRpcError = null,
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

pub const PlueMcpServer = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,
    initialized: bool = false,
    plue_app_running: bool = false,

    pub fn init(allocator: std.mem.Allocator) PlueMcpServer {
        return .{
            .allocator = allocator,
            .stdin = io.getStdIn(),
            .stdout = io.getStdOut(),
            .stderr = io.getStdErr(),
        };
    }

    pub fn run(self: *PlueMcpServer) !void {
        self.log("Plue MCP server starting", .{});

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

    fn handleRequest(self: *PlueMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
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

    fn handleInitialize(self: *PlueMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        self.initialized = true;
        
        const result = InitializeResult{
            .capabilities = .{
                .tools = .{
                    .listChanged = false,
                },
            },
            .serverInfo = .{
                .name = "plue-mcp-server",
                .version = "1.0.0",
            },
        };

        // Convert the result to JSON
        const result_string = try json.stringifyAlloc(self.allocator, result, .{});
        defer self.allocator.free(result_string);
        
        const result_value = try json.parseFromSlice(json.Value, self.allocator, result_string, .{});
        defer result_value.deinit();
        
        const response = JsonRpcResponse{
            .result = result_value.value,
            .id = request.id,
        };

        const response_string = try json.stringifyAlloc(self.allocator, response, .{});
        defer self.allocator.free(response_string);
        
        return json.parseFromSlice(JsonRpcResponse, self.allocator, response_string, .{});
    }

    fn handleListTools(self: *PlueMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        const tools = [_]Tool{
            // Launch and control Plue
            .{
                .name = "plue_launch",
                .description = "Launch the Plue application",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            .{
                .name = "plue_quit",
                .description = "Quit the Plue application",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // Terminal operations
            .{
                .name = "plue_terminal_command",
                .description = "Execute a command in Plue's terminal",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "command", "string", "The terminal command to execute" },
                    .{ "new_tab", "boolean", "Whether to run in a new tab (optional)", true },
                }),
            },
            .{
                .name = "plue_terminal_output",
                .description = "Get the current terminal output from Plue",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // Chat/Agent operations
            .{
                .name = "plue_send_message",
                .description = "Send a message to Plue's chat/agent interface",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "message", "string", "The message to send" },
                    .{ "conversation_type", "string", "Type of conversation: 'agent' or 'prompt' (optional)", true },
                }),
            },
            .{
                .name = "plue_get_messages",
                .description = "Get all messages from the current conversation",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // Navigation
            .{
                .name = "plue_switch_tab",
                .description = "Switch to a different tab in Plue",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "tab", "string", "Tab name: prompt, farcaster, agent, terminal, web, editor, diff, or worktree" },
                }),
            },
            
            // File operations
            .{
                .name = "plue_open_file",
                .description = "Open a file in Plue's editor",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "path", "string", "The file path to open" },
                }),
            },
            .{
                .name = "plue_save_file",
                .description = "Save the currently open file",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // State queries
            .{
                .name = "plue_get_state",
                .description = "Get the current application state",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // Prompt engineering
            .{
                .name = "plue_set_prompt",
                .description = "Set the content in the prompt engineering tab",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "content", "string", "The prompt content to set" },
                }),
            },
            .{
                .name = "plue_get_prompt",
                .description = "Get the current prompt content",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            
            // Git worktree operations
            .{
                .name = "plue_list_worktrees",
                .description = "List all git worktrees",
                .inputSchema = try self.createSimpleSchema(&.{}),
            },
            .{
                .name = "plue_create_worktree",
                .description = "Create a new git worktree",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "branch", "string", "The branch name" },
                    .{ "path", "string", "The worktree path" },
                }),
            },
            
            // Farcaster operations
            .{
                .name = "plue_farcaster_post",
                .description = "Post a cast to Farcaster",
                .inputSchema = try self.createObjectSchema(&.{
                    .{ "content", "string", "The cast content" },
                    .{ "channel", "string", "The channel to post to (optional)", true },
                }),
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

        const response_string = try json.stringifyAlloc(self.allocator, response, .{});
        defer self.allocator.free(response_string);
        
        return json.parseFromSlice(JsonRpcResponse, self.allocator, response_string, .{});
    }

    fn handleCallTool(self: *PlueMcpServer, request: JsonRpcRequest) !json.Parsed(JsonRpcResponse) {
        if (request.params == null) {
            return self.createErrorResponse(request.id, -32602, "Invalid params");
        }

        const params = request.params.?.object;
        const name = params.get("name") orelse return self.createErrorResponse(request.id, -32602, "Missing tool name");
        
        const tool_name = name.string;
        const arguments = params.get("arguments");
        
        // Route to appropriate handler
        const result = if (std.mem.eql(u8, tool_name, "plue_launch"))
            try self.handleLaunchPlue()
        else if (std.mem.eql(u8, tool_name, "plue_quit"))
            try self.handleQuitPlue()
        else if (std.mem.eql(u8, tool_name, "plue_terminal_command"))
            try self.handleTerminalCommand(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_terminal_output"))
            try self.handleGetTerminalOutput()
        else if (std.mem.eql(u8, tool_name, "plue_send_message"))
            try self.handleSendMessage(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_get_messages"))
            try self.handleGetMessages()
        else if (std.mem.eql(u8, tool_name, "plue_switch_tab"))
            try self.handleSwitchTab(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_open_file"))
            try self.handleOpenFile(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_save_file"))
            try self.handleSaveFile()
        else if (std.mem.eql(u8, tool_name, "plue_get_state"))
            try self.handleGetState()
        else if (std.mem.eql(u8, tool_name, "plue_set_prompt"))
            try self.handleSetPrompt(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_get_prompt"))
            try self.handleGetPrompt()
        else if (std.mem.eql(u8, tool_name, "plue_list_worktrees"))
            try self.handleListWorktrees()
        else if (std.mem.eql(u8, tool_name, "plue_create_worktree"))
            try self.handleCreateWorktree(arguments)
        else if (std.mem.eql(u8, tool_name, "plue_farcaster_post"))
            try self.handleFarcasterPost(arguments)
        else
            return self.createErrorResponse(request.id, -32602, "Unknown tool");

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

        const response_string = try json.stringifyAlloc(self.allocator, response, .{});
        defer self.allocator.free(response_string);
        
        return json.parseFromSlice(JsonRpcResponse, self.allocator, response_string, .{});
    }

    // Tool handlers
    fn handleLaunchPlue(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    activate
            \\end tell
        ;
        const result = try self.executeAppleScript(script);
        self.plue_app_running = true;
        return result;
    }

    fn handleQuitPlue(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    quit
            \\end tell
        ;
        const result = try self.executeAppleScript(script);
        self.plue_app_running = false;
        return result;
    }

    fn handleTerminalCommand(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const command = args.get("command") orelse return self.allocError("Missing command");
        const new_tab = if (args.get("new_tab")) |nt| nt.bool else false;
        
        const script = if (new_tab)
            try std.fmt.allocPrint(self.allocator, 
                \\tell application "Plue"
                \\    run terminal command "{s}" in new tab
                \\end tell
            , .{command.string})
        else
            try std.fmt.allocPrint(self.allocator, 
                \\tell application "Plue"
                \\    run terminal command "{s}"
                \\end tell
            , .{command.string});
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    fn handleGetTerminalOutput(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    get terminal output
            \\end tell
        ;
        return self.executeAppleScript(script);
    }

    fn handleSendMessage(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const message = args.get("message") orelse return self.allocError("Missing message");
        
        const script = try std.fmt.allocPrint(self.allocator, 
            \\tell application "Plue"
            \\    send chat message "{s}"
            \\end tell
        , .{message.string});
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    fn handleGetMessages(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    get chat messages
            \\end tell
        ;
        return self.executeAppleScript(script);
    }

    fn handleSwitchTab(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const tab = args.get("tab") orelse return self.allocError("Missing tab");
        
        const script = try std.fmt.allocPrint(self.allocator, 
            \\tell application "Plue"
            \\    switch to tab "{s}"
            \\end tell
        , .{tab.string});
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    fn handleOpenFile(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const path = args.get("path") orelse return self.allocError("Missing path");
        
        const script = try std.fmt.allocPrint(self.allocator, 
            \\tell application "Plue"
            \\    open file "{s}"
            \\end tell
        , .{path.string});
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    fn handleSaveFile(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    save file
            \\end tell
        ;
        return self.executeAppleScript(script);
    }

    fn handleGetState(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    get application state
            \\end tell
        ;
        return self.executeAppleScript(script);
    }

    fn handleSetPrompt(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        _ = args.get("content") orelse return self.allocError("Missing content");
        
        // For now, we'll switch to prompt tab and send the content
        const script = 
            \\tell application "Plue"
            \\    switch to tab "prompt"
            \\    delay 0.5
            \\    -- Future: implement direct prompt setting
            \\    return "Prompt tab selected. Direct prompt setting coming soon."
            \\end tell
        ;
        
        return self.executeAppleScript(script);
    }

    fn handleGetPrompt(self: *PlueMcpServer) ![]u8 {
        // For now, return a placeholder
        return self.allocator.dupe(u8, "Prompt content retrieval coming soon");
    }

    fn handleListWorktrees(self: *PlueMcpServer) ![]u8 {
        const script = 
            \\tell application "Plue"
            \\    switch to tab "worktree"
            \\    delay 0.5
            \\    return "Worktree tab selected"
            \\end tell
        ;
        return self.executeAppleScript(script);
    }

    fn handleCreateWorktree(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const branch = args.get("branch") orelse return self.allocError("Missing branch");
        const path = args.get("path") orelse return self.allocError("Missing path");
        
        const script = try std.fmt.allocPrint(self.allocator, 
            \\tell application "Plue"
            \\    -- Future: implement worktree creation
            \\    return "Worktree creation for branch '{s}' at path '{s}' coming soon"
            \\end tell
        , .{ branch.string, path.string });
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    fn handleFarcasterPost(self: *PlueMcpServer, arguments: ?json.Value) ![]u8 {
        if (arguments == null) return self.allocError("Missing arguments");
        
        const args = arguments.?.object;
        const content = args.get("content") orelse return self.allocError("Missing content");
        const channel = if (args.get("channel")) |ch| ch.string else "home";
        
        const script = try std.fmt.allocPrint(self.allocator, 
            \\tell application "Plue"
            \\    switch to tab "farcaster"
            \\    delay 0.5
            \\    -- Future: implement direct Farcaster posting
            \\    return "Ready to post to Farcaster channel '{s}': {s}"
            \\end tell
        , .{ channel, content.string });
        
        defer self.allocator.free(script);
        return self.executeAppleScript(script);
    }

    // Helper functions
    fn executeAppleScript(self: *PlueMcpServer, code: []const u8) ![]u8 {
        // Create a temporary file for the AppleScript
        var tmp_dir = try std.fs.openDirAbsolute("/tmp", .{});
        defer tmp_dir.close();
        const tmp_name = try std.fmt.allocPrint(self.allocator, "plue_script_{d}.scpt", .{std.time.milliTimestamp()});
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

    fn createSimpleSchema(self: *PlueMcpServer, required: []const void) !json.Value {
        _ = required;
        var map = json.ObjectMap.init(self.allocator);
        try map.put("type", json.Value{ .string = "object" });
        
        const props = json.ObjectMap.init(self.allocator);
        try map.put("properties", json.Value{ .object = props });
        
        const req_array = json.Array.init(self.allocator);
        try map.put("required", json.Value{ .array = req_array });
        
        return json.Value{ .object = map };
    }

    fn createObjectSchema(self: *PlueMcpServer, fields: []const struct { []const u8, []const u8, []const u8, bool }) !json.Value {
        var map = json.ObjectMap.init(self.allocator);
        try map.put("type", json.Value{ .string = "object" });
        
        var props = json.ObjectMap.init(self.allocator);
        var required = json.Array.init(self.allocator);
        
        for (fields) |field| {
            var field_obj = json.ObjectMap.init(self.allocator);
            try field_obj.put("type", json.Value{ .string = field[1] });
            try field_obj.put("description", json.Value{ .string = field[2] });
            try props.put(field[0], json.Value{ .object = field_obj });
            
            if (!field[3]) { // If not optional
                try required.append(json.Value{ .string = field[0] });
            }
        }
        
        try map.put("properties", json.Value{ .object = props });
        try map.put("required", json.Value{ .array = required });
        
        return json.Value{ .object = map };
    }

    fn allocError(self: *PlueMcpServer, message: []const u8) ![]u8 {
        return try self.allocator.dupe(u8, message);
    }

    fn createErrorResponse(self: *PlueMcpServer, id: ?json.Value, code: i32, message: []const u8) !json.Parsed(JsonRpcResponse) {
        const response = JsonRpcResponse{
            .@"error" = JsonRpcError{
                .code = code,
                .message = message,
            },
            .id = id,
        };

        const response_string = try json.stringifyAlloc(self.allocator, response, .{});
        defer self.allocator.free(response_string);
        
        return json.parseFromSlice(JsonRpcResponse, self.allocator, response_string, .{});
    }

    fn log(self: *PlueMcpServer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.stderr.writer(), "[plue-mcp] " ++ format ++ "\n", args) catch {};
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = PlueMcpServer.init(allocator);
    try server.run();
}