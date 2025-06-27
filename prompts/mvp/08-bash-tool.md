# Implement Bash Tool for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on implementing the Bash tool that allows AI agents to execute shell commands with proper security, timeout handling, and output streaming.

## Context

<context>
<project_overview>
The Bash tool is one of the most powerful tools in Plue, enabling AI agents to:
- Execute shell commands to interact with the system
- Build and test code
- Install dependencies
- Navigate file systems
- Run development servers
- Perform system administration tasks
</project_overview>

<existing_infrastructure>
From previous implementations:
- Tool registry system provides the framework for tool implementation
- Tool execution context handles abort signals and metadata streaming
- Error handling system provides comprehensive error reporting
- Message system tracks tool invocations in conversation history
- JSON utilities handle parameter parsing and result formatting
</existing_infrastructure>

<api_specification>
The Bash tool follows the standard tool interface with:
- Parameters: command (string), working_dir (optional string), timeout_ms (optional number)
- Returns: stdout, stderr, exit_code, and execution metadata
- Supports streaming output for long-running commands
- Respects abort signals for cancellation
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has a sophisticated bash implementation:
- opencode/packages/opencode/src/tool/bash.txt - Bash tool specification
- Supports timeout with default of 120 seconds
- Captures both stdout and stderr
- Handles working directory changes
- Implements proper shell escaping
- Tracks command execution time
</reference_implementation>
</context>

## Task: Implement Bash Tool

### Requirements

1. **Create secure command execution**:
   - Proper shell escaping to prevent injection
   - Working directory isolation
   - Environment variable control
   - Process group management for cleanup

2. **Implement timeout and cancellation**:
   - Configurable timeout with defaults
   - Abort signal handling
   - Process tree termination
   - Partial output on timeout

3. **Add output streaming**:
   - Real-time stdout/stderr streaming
   - Metadata updates during execution
   - Buffer management for large outputs
   - Character encoding handling

4. **Provide comprehensive results**:
   - Exit code and signal information
   - Execution timing metrics
   - Resource usage statistics
   - Error context on failures

### Detailed Steps

1. **Create src/tool/bash.zig with tool implementation**:
   ```zig
   const std = @import("std");
   const builtin = @import("builtin");
   const tool = @import("../tool.zig");
   const json = @import("../../json.zig");
   
   pub const BashTool = struct {
       tool_impl: tool.Tool,
       allocator: std.mem.Allocator,
       default_timeout_ms: u32 = 120_000, // 120 seconds
       max_output_size: usize = 10 * 1024 * 1024, // 10MB
       
       pub fn init(allocator: std.mem.Allocator) !BashTool {
           const builder = tool.SchemaBuilder.init(allocator);
           
           return BashTool{
               .allocator = allocator,
               .tool_impl = tool.Tool{
                   .info = tool.ToolInfo{
                       .name = "bash",
                       .description = "Execute bash commands with timeout and output capture",
                       .parameters_schema = try builder.object(.{
                           .command = builder.string().required(),
                           .working_dir = builder.string().optional(),
                           .timeout_ms = builder.number().min(0).max(600_000).optional(),
                           .env = builder.object(.{}).additionalProperties(builder.string()).optional(),
                       }),
                       .returns_schema = try builder.object(.{
                           .stdout = builder.string(),
                           .stderr = builder.string(),
                           .exit_code = builder.number(),
                           .timed_out = builder.boolean(),
                           .duration_ms = builder.number(),
                           .truncated = builder.boolean(),
                       }),
                   },
                   .executeFn = execute,
               },
           };
       }
       
       fn execute(self_tool: *tool.Tool, params: json.Value, context: *tool.ToolContext) !json.Value {
           const self = @fieldParentPtr(BashTool, "tool_impl", self_tool);
           
           // Parse parameters
           const command = params.object.get("command").?.string;
           const working_dir = if (params.object.get("working_dir")) |wd| wd.string else null;
           const timeout_ms = if (params.object.get("timeout_ms")) |t| 
               @intCast(u32, t.integer) 
           else 
               self.default_timeout_ms;
           
           // Send start metadata
           try context.sendMetadata(.{
               .type = "start",
               .command = command,
               .working_dir = working_dir,
               .timeout_ms = timeout_ms,
           });
           
           // Execute command
           const result = try self.executeCommand(command, working_dir, timeout_ms, context);
           
           // Send completion metadata
           try context.sendMetadata(.{
               .type = "complete",
               .exit_code = result.exit_code,
               .duration_ms = result.duration_ms,
           });
           
           return result.toJson(self.allocator);
       }
   };
   ```

2. **Implement secure command execution**:
   ```zig
   const CommandResult = struct {
       stdout: []const u8,
       stderr: []const u8,
       exit_code: i32,
       timed_out: bool,
       duration_ms: u64,
       truncated: bool,
       
       pub fn toJson(self: CommandResult, allocator: std.mem.Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           try obj.put("stdout", json.Value{ .string = self.stdout });
           try obj.put("stderr", json.Value{ .string = self.stderr });
           try obj.put("exit_code", json.Value{ .integer = self.exit_code });
           try obj.put("timed_out", json.Value{ .bool = self.timed_out });
           try obj.put("duration_ms", json.Value{ .integer = @intCast(i64, self.duration_ms) });
           try obj.put("truncated", json.Value{ .bool = self.truncated });
           return json.Value{ .object = obj };
       }
   };
   
   fn executeCommand(
       self: *BashTool,
       command: []const u8,
       working_dir: ?[]const u8,
       timeout_ms: u32,
       context: *tool.ToolContext,
   ) !CommandResult {
       const start_time = std.time.milliTimestamp();
       
       // Create command args for shell
       const argv = [_][]const u8{
           "/bin/bash",
           "-c",
           command,
       };
       
       // Setup process
       var child = std.ChildProcess.init(&argv, self.allocator);
       child.stdin_behavior = .Close;
       child.stdout_behavior = .Pipe;
       child.stderr_behavior = .Pipe;
       
       // Set working directory if specified
       if (working_dir) |dir| {
           child.cwd = dir;
       }
       
       // Copy environment with modifications if needed
       child.env_map = try self.setupEnvironment(context);
       defer if (child.env_map) |*env| env.deinit();
       
       // Spawn process
       try child.spawn();
       
       // Create output collectors
       var stdout_collector = OutputCollector.init(self.allocator, self.max_output_size);
       defer stdout_collector.deinit();
       var stderr_collector = OutputCollector.init(self.allocator, self.max_output_size);
       defer stderr_collector.deinit();
       
       // Start output streaming threads
       const stdout_thread = try std.Thread.spawn(.{}, streamOutput, .{
           child.stdout.?,
           &stdout_collector,
           context,
           .stdout,
       });
       const stderr_thread = try std.Thread.spawn(.{}, streamOutput, .{
           child.stderr.?,
           &stderr_collector,
           context,
           .stderr,
       });
       
       // Monitor timeout and abort
       const monitor_result = try self.monitorExecution(&child, timeout_ms, context);
       
       // Wait for output threads
       stdout_thread.join();
       stderr_thread.join();
       
       // Get final result
       const duration_ms = @intCast(u64, std.time.milliTimestamp() - start_time);
       
       return CommandResult{
           .stdout = try stdout_collector.getOutput(),
           .stderr = try stderr_collector.getOutput(),
           .exit_code = monitor_result.exit_code,
           .timed_out = monitor_result.timed_out,
           .duration_ms = duration_ms,
           .truncated = stdout_collector.truncated or stderr_collector.truncated,
       };
   }
   ```

3. **Implement output streaming and collection**:
   ```zig
   const OutputCollector = struct {
       allocator: std.mem.Allocator,
       buffer: std.ArrayList(u8),
       max_size: usize,
       truncated: bool,
       mutex: std.Thread.Mutex,
       
       pub fn init(allocator: std.mem.Allocator, max_size: usize) OutputCollector {
           return OutputCollector{
               .allocator = allocator,
               .buffer = std.ArrayList(u8).init(allocator),
               .max_size = max_size,
               .truncated = false,
               .mutex = std.Thread.Mutex{},
           };
       }
       
       pub fn append(self: *OutputCollector, data: []const u8) !void {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           const available = self.max_size - self.buffer.items.len;
           if (data.len <= available) {
               try self.buffer.appendSlice(data);
           } else {
               try self.buffer.appendSlice(data[0..available]);
               self.truncated = true;
           }
       }
       
       pub fn getOutput(self: *OutputCollector) ![]const u8 {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           return try self.allocator.dupe(u8, self.buffer.items);
       }
       
       pub fn deinit(self: *OutputCollector) void {
           self.buffer.deinit();
       }
   };
   
   const StreamType = enum { stdout, stderr };
   
   fn streamOutput(
       reader: std.fs.File,
       collector: *OutputCollector,
       context: *tool.ToolContext,
       stream_type: StreamType,
   ) !void {
       var buffer: [4096]u8 = undefined;
       
       while (true) {
           const bytes_read = reader.read(&buffer) catch |err| {
               if (err == error.EndOfStream) break;
               return err;
           };
           
           if (bytes_read == 0) break;
           
           const chunk = buffer[0..bytes_read];
           
           // Collect output
           try collector.append(chunk);
           
           // Stream to metadata callback
           try context.sendMetadata(.{
               .type = "output",
               .stream = @tagName(stream_type),
               .data = chunk,
               .timestamp = std.time.milliTimestamp(),
           });
       }
   }
   ```

4. **Add timeout and abort monitoring**:
   ```zig
   const MonitorResult = struct {
       exit_code: i32,
       timed_out: bool,
       aborted: bool,
   };
   
   fn monitorExecution(
       self: *BashTool,
       child: *std.ChildProcess,
       timeout_ms: u32,
       context: *tool.ToolContext,
   ) !MonitorResult {
       const start_time = std.time.milliTimestamp();
       
       // Create a separate thread for process monitoring
       const monitor_thread = try std.Thread.spawn(.{}, processMonitor, .{
           child,
           context.abort_signal,
       });
       defer monitor_thread.join();
       
       // Wait with timeout
       while (true) {
           // Check if process finished
           const result = child.wait() catch |err| {
               if (err == error.ChildNotFinished) {
                   // Process still running, check conditions
               } else {
                   return err;
               }
           };
           
           if (result) |term| {
               return MonitorResult{
                   .exit_code = switch (term) {
                       .Exited => |code| @intCast(i32, code),
                       .Signal => |sig| -@intCast(i32, sig),
                       .Stopped => -1,
                       .Unknown => -1,
                   },
                   .timed_out = false,
                   .aborted = false,
               };
           }
           
           // Check timeout
           const elapsed = std.time.milliTimestamp() - start_time;
           if (elapsed >= timeout_ms) {
               // Kill process and children
               try self.terminateProcessTree(child);
               
               return MonitorResult{
                   .exit_code = -1,
                   .timed_out = true,
                   .aborted = false,
               };
           }
           
           // Check abort signal
           try context.checkAbort() catch {
               // Kill process on abort
               try self.terminateProcessTree(child);
               
               return MonitorResult{
                   .exit_code = -1,
                   .timed_out = false,
                   .aborted = true,
               };
           };
           
           // Sleep briefly before next check
           std.time.sleep(10 * std.time.ns_per_ms);
       }
   }
   
   fn terminateProcessTree(self: *BashTool, child: *std.ChildProcess) !void {
       // First try SIGTERM
       _ = std.os.kill(child.pid, std.os.SIGTERM) catch {};
       
       // Give process time to cleanup
       std.time.sleep(100 * std.time.ns_per_ms);
       
       // Force kill if still running
       _ = std.os.kill(child.pid, std.os.SIGKILL) catch {};
       
       // On Unix systems, also kill process group
       if (builtin.os.tag != .windows) {
           // Kill negative PID to kill process group
           _ = std.os.kill(-@intCast(i32, child.pid), std.os.SIGKILL) catch {};
       }
   }
   ```

5. **Implement environment setup**:
   ```zig
   fn setupEnvironment(self: *BashTool, context: *tool.ToolContext) !?*std.process.EnvMap {
       var env_map = try std.process.EnvMap.init(self.allocator);
       errdefer env_map.deinit();
       
       // Copy current environment
       var env_iter = try std.process.getEnvMap(self.allocator);
       defer env_iter.deinit();
       
       var it = env_iter.iterator();
       while (it.next()) |entry| {
           try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
       }
       
       // Add tool-specific environment variables
       try env_map.put("PLUE_SESSION_ID", context.session_id);
       try env_map.put("PLUE_MESSAGE_ID", context.message_id);
       try env_map.put("PLUE_TOOL", "bash");
       
       // Security: Remove sensitive variables
       _ = env_map.remove("PLUE_API_KEY");
       _ = env_map.remove("OPENAI_API_KEY");
       _ = env_map.remove("ANTHROPIC_API_KEY");
       
       return env_map;
   }
   ```

6. **Add comprehensive tests**:
   ```zig
   test "bash tool executes simple commands" {
       const allocator = std.testing.allocator;
       var bash = try BashTool.init(allocator);
       defer bash.deinit();
       
       var context = try createTestContext(allocator);
       defer context.deinit();
       
       const params = try json.parse(allocator,
           \\{"command": "echo 'Hello, World!'"}
       );
       defer params.deinit();
       
       const result = try bash.tool_impl.execute(params, &context);
       defer result.deinit();
       
       try std.testing.expectEqualStrings("Hello, World!\n", result.object.get("stdout").?.string);
       try std.testing.expectEqual(@as(i32, 0), result.object.get("exit_code").?.integer);
   }
   
   test "bash tool handles timeouts" {
       const allocator = std.testing.allocator;
       var bash = try BashTool.init(allocator);
       defer bash.deinit();
       
       var context = try createTestContext(allocator);
       defer context.deinit();
       
       const params = try json.parse(allocator,
           \\{"command": "sleep 10", "timeout_ms": 100}
       );
       defer params.deinit();
       
       const result = try bash.tool_impl.execute(params, &context);
       defer result.deinit();
       
       try std.testing.expect(result.object.get("timed_out").?.bool);
       try std.testing.expect(result.object.get("exit_code").?.integer != 0);
   }
   
   test "bash tool respects abort signals" {
       const allocator = std.testing.allocator;
       var bash = try BashTool.init(allocator);
       defer bash.deinit();
       
       var context = try createTestContext(allocator);
       defer context.deinit();
       
       // Set abort signal before execution
       context.abort_signal.set();
       
       const params = try json.parse(allocator,
           \\{"command": "sleep 10"}
       );
       defer params.deinit();
       
       const result = bash.tool_impl.execute(params, &context);
       try std.testing.expectError(error.Aborted, result);
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write security-focused tests first**:
   - Test command injection prevention
   - Test environment variable isolation
   - Test working directory restrictions
   - Test resource limits

2. **Implement incrementally**:
   - Basic command execution
   - Output capture
   - Timeout handling
   - Streaming support
   - Abort handling
   - Security hardening

3. **Test edge cases**:
   - Very long output
   - Binary output
   - Interactive commands
   - Process groups
   - Signal handling

### Git Workflow

```bash
git worktree add worktrees/bash-tool -b feat/bash-tool
cd worktrees/bash-tool
```

Commits:
- `feat: implement basic bash command execution`
- `feat: add timeout and process monitoring`
- `feat: implement output streaming and collection`
- `feat: add abort signal handling`
- `feat: implement security hardening`
- `test: comprehensive bash tool test suite`
- `feat: register bash tool with registry`

## Success Criteria

✅ **Task is complete when**:
1. Commands execute with proper output capture
2. Timeouts terminate processes cleanly
3. Abort signals stop execution immediately
4. Output streams in real-time via metadata
5. Large outputs are handled without OOM
6. Security measures prevent injection
7. Process groups are cleaned up properly
8. All tests pass including security tests

## Technical Considerations

<security_requirements>
- Never pass user input directly to shell
- Sanitize environment variables
- Limit resource consumption
- Use process groups for cleanup
- Validate working directory paths
</security_requirements>

<performance_requirements>
- Stream output without buffering entire result
- Handle multi-MB outputs efficiently
- Clean process termination
- Minimal overhead for simple commands
- Reuse resources where possible
</performance_requirements>

<platform_considerations>
- Handle Windows vs Unix differences
- Deal with different shell behaviors
- Support various terminal encodings
- Handle zombie processes
- Work in containerized environments
</platform_considerations>

Remember: The Bash tool is powerful but dangerous. Security must be the top priority, followed by reliability and performance. This tool will be used extensively by AI agents.