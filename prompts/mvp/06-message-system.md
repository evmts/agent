# Implement Message System API for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on implementing the message system that manages the conversation history between users and AI agents, including message parts, streaming responses, and tool invocations.

## Context

<context>
<project_overview>
Plue's message system is the core of user-AI interaction:
- Messages belong to sessions and form conversation threads
- Messages have multiple parts (text, files, tool calls, reasoning)
- AI responses stream in real-time with token usage tracking
- Messages integrate with the tool system for agent capabilities
- All message state is managed by Zig, streamed to Swift for display
</project_overview>

<existing_infrastructure>
From previous implementations:
- Session management system is complete with persistence
- Enhanced error handling provides robust error propagation
- JSON utilities handle serialization efficiently
- AI provider wrapper handles streaming responses
- Basic FFI patterns are established
</existing_infrastructure>

<api_specification>
From PLUE_CORE_API.md:
```c
// Send a user message to a session
export fn plue_message_send(session: ?*anyopaque, message_json: [*:0]const u8) [*c]u8;

// Get all messages for a session as JSON array
export fn plue_message_list(session: ?*anyopaque) [*c]u8;

// Get a specific message by ID as JSON
export fn plue_message_get(session: ?*anyopaque, message_id: [*:0]const u8) [*c]u8;

// Stream response for a message
typedef fn(*const u8, usize, *anyopaque) void plue_stream_callback;
export fn plue_message_stream_response(
    session: ?*anyopaque,
    message_id: [*:0]const u8,
    provider_id: [*:0]const u8,
    model_id: [*:0]const u8,
    callback: plue_stream_callback,
    user_data: ?*anyopaque
) c_int;
```
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has a sophisticated message system:
- opencode/packages/opencode/src/session/message.ts - Message types and parts
- Messages have multiple part types: text, file, tool use, tool result
- Streaming updates individual message parts
- Token usage and costs are tracked per message
- Messages support attachments and reasoning traces
</reference_implementation>
</context>

## Task: Implement Message System API

### Requirements

1. **Design message data structures** supporting:
   - Multiple part types (text, file, tool invocation, reasoning)
   - Role-based messages (system, user, assistant)
   - Streaming updates for parts
   - Token usage and cost tracking
   - File attachments

2. **Implement message management**:
   - Send user messages with attachments
   - Store messages in sessions
   - List and retrieve messages
   - Update message parts during streaming

3. **Create streaming infrastructure**:
   - Handle AI provider streaming responses
   - Update message parts in real-time
   - Track token usage during streaming
   - Support abort/cancellation

4. **Integrate with tool system**:
   - Track tool invocations in messages
   - Store tool results as message parts
   - Support multiple tool calls per message

### Detailed Steps

1. **Create src/message/message.zig with core types**:
   ```zig
   const std = @import("std");
   const json = @import("../json.zig");
   const session = @import("../session/session.zig");
   
   pub const MessageId = []const u8;
   
   pub const Role = enum {
       system,
       user,
       assistant,
       
       pub fn toString(self: Role) []const u8 {
           return switch (self) {
               .system => "system",
               .user => "user",
               .assistant => "assistant",
           };
       }
   };
   
   pub const Message = struct {
       id: MessageId,
       session_id: session.SessionId,
       role: Role,
       parts: std.ArrayList(Part),
       created_at: i64,
       updated_at: i64,
       usage: ?Usage,
       cost: ?Cost,
       provider_info: ?ProviderInfo,
       
       pub fn init(allocator: Allocator, session_id: session.SessionId, role: Role) !Message {
           const timestamp = std.time.milliTimestamp();
           const id = try std.fmt.allocPrint(allocator, "msg_{d}", .{timestamp});
           
           return Message{
               .id = id,
               .session_id = try allocator.dupe(u8, session_id),
               .role = role,
               .parts = std.ArrayList(Part).init(allocator),
               .created_at = timestamp,
               .updated_at = timestamp,
               .usage = null,
               .cost = null,
               .provider_info = null,
           };
       }
       
       pub fn addPart(self: *Message, part: Part) !void {
           try self.parts.append(part);
           self.updated_at = std.time.milliTimestamp();
       }
   };
   
   pub const Part = union(enum) {
       text: TextPart,
       file: FilePart,
       tool_use: ToolUsePart,
       tool_result: ToolResultPart,
       reasoning: ReasoningPart,
       
       pub fn toJson(self: Part, allocator: Allocator) !json.Value {
           return switch (self) {
               .text => |t| try t.toJson(allocator),
               .file => |f| try f.toJson(allocator),
               .tool_use => |t| try t.toJson(allocator),
               .tool_result => |t| try t.toJson(allocator),
               .reasoning => |r| try r.toJson(allocator),
           };
       }
   };
   ```

2. **Define part types**:
   ```zig
   pub const TextPart = struct {
       content: []const u8,
       
       pub fn init(allocator: Allocator, content: []const u8) !TextPart {
           return TextPart{
               .content = try allocator.dupe(u8, content),
           };
       }
       
       pub fn toJson(self: TextPart, allocator: Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           try obj.put("type", json.Value{ .string = "text" });
           try obj.put("content", json.Value{ .string = self.content });
           return json.Value{ .object = obj };
       }
   };
   
   pub const FilePart = struct {
       path: []const u8,
       content: []const u8,
       language: ?[]const u8,
       
       pub fn init(allocator: Allocator, path: []const u8, content: []const u8) !FilePart {
           return FilePart{
               .path = try allocator.dupe(u8, path),
               .content = try allocator.dupe(u8, content),
               .language = try detectLanguage(path),
           };
       }
   };
   
   pub const ToolUsePart = struct {
       tool_name: []const u8,
       parameters: json.Value,
       tool_use_id: []const u8,
       
       pub fn init(allocator: Allocator, tool_name: []const u8, params: json.Value) !ToolUsePart {
           const id = try std.fmt.allocPrint(allocator, "tool_use_{d}", .{std.time.milliTimestamp()});
           return ToolUsePart{
               .tool_name = try allocator.dupe(u8, tool_name),
               .parameters = try params.clone(allocator),
               .tool_use_id = id,
           };
       }
   };
   
   pub const ToolResultPart = struct {
       tool_use_id: []const u8,
       result: json.Value,
       error: ?[]const u8,
       
       pub fn init(allocator: Allocator, tool_use_id: []const u8, result: json.Value) !ToolResultPart {
           return ToolResultPart{
               .tool_use_id = try allocator.dupe(u8, tool_use_id),
               .result = try result.clone(allocator),
               .error = null,
           };
       }
   };
   
   pub const ReasoningPart = struct {
       content: []const u8,
       
       pub fn init(allocator: Allocator, content: []const u8) !ReasoningPart {
           return ReasoningPart{
               .content = try allocator.dupe(u8, content),
           };
       }
   };
   ```

3. **Add usage and cost tracking**:
   ```zig
   pub const Usage = struct {
       input_tokens: u32,
       output_tokens: u32,
       total_tokens: u32,
       
       pub fn add(self: *Usage, other: Usage) void {
           self.input_tokens += other.input_tokens;
           self.output_tokens += other.output_tokens;
           self.total_tokens += other.total_tokens;
       }
   };
   
   pub const Cost = struct {
       input_cost: f64,
       output_cost: f64,
       total_cost: f64,
       
       pub fn calculate(usage: Usage, model_pricing: ModelPricing) Cost {
           const input_cost = @intToFloat(f64, usage.input_tokens) * model_pricing.input_per_million / 1_000_000;
           const output_cost = @intToFloat(f64, usage.output_tokens) * model_pricing.output_per_million / 1_000_000;
           return Cost{
               .input_cost = input_cost,
               .output_cost = output_cost,
               .total_cost = input_cost + output_cost,
           };
       }
   };
   
   pub const ProviderInfo = struct {
       provider_id: []const u8,
       model_id: []const u8,
       request_id: ?[]const u8,
   };
   ```

4. **Implement message manager**:
   ```zig
   pub const MessageManager = struct {
       allocator: Allocator,
       messages: std.StringHashMap(std.ArrayList(*Message)),
       storage_path: []const u8,
       mutex: std.Thread.Mutex,
       
       pub fn init(allocator: Allocator, storage_path: []const u8) !MessageManager {
           return MessageManager{
               .allocator = allocator,
               .messages = std.StringHashMap(std.ArrayList(*Message)).init(allocator),
               .storage_path = storage_path,
               .mutex = std.Thread.Mutex{},
           };
       }
       
       pub fn sendMessage(self: *MessageManager, session_id: session.SessionId, message_json: []const u8) !MessageId {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           // Parse message JSON
           const parsed = try json.parse(self.allocator, message_json);
           defer parsed.deinit();
           
           // Create message
           var message = try self.allocator.create(Message);
           message.* = try Message.init(self.allocator, session_id, .user);
           
           // Add text part
           if (parsed.object.get("text")) |text| {
               const text_part = try TextPart.init(self.allocator, text.string);
               try message.addPart(.{ .text = text_part });
           }
           
           // Add file attachments
           if (parsed.object.get("attachments")) |attachments| {
               for (attachments.array.items) |attachment| {
                   const path = attachment.object.get("path").?.string;
                   const content = try self.loadFile(path);
                   const file_part = try FilePart.init(self.allocator, path, content);
                   try message.addPart(.{ .file = file_part });
               }
           }
           
           // Store message
           var session_messages = self.messages.get(session_id) orelse blk: {
               var list = std.ArrayList(*Message).init(self.allocator);
               try self.messages.put(session_id, list);
               break :blk list;
           };
           try session_messages.append(message);
           
           // Persist
           try self.saveMessage(message);
           
           return message.id;
       }
       
       pub fn listMessages(self: *MessageManager, session_id: session.SessionId, allocator: Allocator) ![]u8 {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           const session_messages = self.messages.get(session_id) orelse {
               return json.stringify(allocator, &[_]json.Value{}, .{});
           };
           
           var array = std.ArrayList(json.Value).init(allocator);
           defer array.deinit();
           
           for (session_messages.items) |msg| {
               try array.append(try msg.toJson(allocator));
           }
           
           return json.stringify(allocator, array.items, .{});
       }
   };
   ```

5. **Implement streaming response handler**:
   ```zig
   pub const StreamingHandler = struct {
       allocator: Allocator,
       message: *Message,
       current_part_index: usize,
       stream_buffer: std.ArrayList(u8),
       callback: plue_stream_callback,
       user_data: ?*anyopaque,
       
       pub fn init(
           allocator: Allocator,
           message: *Message,
           callback: plue_stream_callback,
           user_data: ?*anyopaque,
       ) !StreamingHandler {
           // Add initial empty text part for streaming
           try message.addPart(.{ .text = try TextPart.init(allocator, "") });
           
           return StreamingHandler{
               .allocator = allocator,
               .message = message,
               .current_part_index = message.parts.items.len - 1,
               .stream_buffer = std.ArrayList(u8).init(allocator),
               .callback = callback,
               .user_data = user_data,
           };
       }
       
       pub fn handleChunk(self: *StreamingHandler, chunk: []const u8) !void {
           // Parse streaming chunk from AI provider
           const parsed = try json.parse(self.allocator, chunk);
           defer parsed.deinit();
           
           if (parsed.object.get("type")) |chunk_type| {
               switch (chunk_type.string) {
                   "content" => {
                       // Append to current text part
                       const content = parsed.object.get("content").?.string;
                       try self.stream_buffer.appendSlice(content);
                       
                       // Update message part
                       if (self.message.parts.items[self.current_part_index]) |*part| {
                           switch (part.*) {
                               .text => |*text_part| {
                                   self.allocator.free(text_part.content);
                                   text_part.content = try self.allocator.dupe(u8, self.stream_buffer.items);
                               },
                               else => return error.InvalidPartType,
                           }
                       }
                       
                       // Send update to callback
                       const update = try json.stringify(self.allocator, .{
                           .type = "content",
                           .content = content,
                           .message_id = self.message.id,
                           .part_index = self.current_part_index,
                       }, .{});
                       defer self.allocator.free(update);
                       
                       self.callback(update.ptr, update.len, self.user_data);
                   },
                   
                   "tool_use" => {
                       // Add new tool use part
                       const tool_use = try ToolUsePart.init(
                           self.allocator,
                           parsed.object.get("tool_name").?.string,
                           parsed.object.get("parameters").?,
                       );
                       try self.message.addPart(.{ .tool_use = tool_use });
                       
                       // Notify callback
                       const update = try json.stringify(self.allocator, .{
                           .type = "tool_use",
                           .tool_use_id = tool_use.tool_use_id,
                           .message_id = self.message.id,
                       }, .{});
                       defer self.allocator.free(update);
                       
                       self.callback(update.ptr, update.len, self.user_data);
                   },
                   
                   "done" => {
                       // Update usage and cost
                       if (parsed.object.get("usage")) |usage| {
                           self.message.usage = Usage{
                               .input_tokens = @intCast(u32, usage.object.get("input_tokens").?.integer),
                               .output_tokens = @intCast(u32, usage.object.get("output_tokens").?.integer),
                               .total_tokens = @intCast(u32, usage.object.get("total_tokens").?.integer),
                           };
                       }
                       
                       // Calculate cost based on model
                       if (self.message.usage) |usage| {
                           const pricing = try self.getModelPricing(self.message.provider_info.?.model_id);
                           self.message.cost = Cost.calculate(usage, pricing);
                       }
                       
                       // Final notification
                       const update = try json.stringify(self.allocator, .{
                           .type = "done",
                           .message_id = self.message.id,
                           .usage = self.message.usage,
                           .cost = self.message.cost,
                       }, .{});
                       defer self.allocator.free(update);
                       
                       self.callback(update.ptr, update.len, self.user_data);
                   },
               }
           }
       }
   };
   ```

6. **Implement FFI exports**:
   ```zig
   export fn plue_message_send(session_ptr: ?*anyopaque, message_json: [*:0]const u8) [*c]u8 {
       const session = @ptrCast(*session.Session, @alignCast(@alignOf(session.Session), session_ptr.?));
       
       const message_id = g_message_manager.?.sendMessage(session.id, std.mem.span(message_json)) catch |err| {
           error_handling.setError(err, "Failed to send message", .{});
           return null;
       };
       
       return try allocator.dupeZ(u8, message_id);
   }
   
   export fn plue_message_stream_response(
       session_ptr: ?*anyopaque,
       message_id: [*:0]const u8,
       provider_id: [*:0]const u8,
       model_id: [*:0]const u8,
       callback: plue_stream_callback,
       user_data: ?*anyopaque,
   ) c_int {
       const session = @ptrCast(*session.Session, @alignCast(@alignOf(session.Session), session_ptr.?));
       
       // Get message
       const msg_id = std.mem.span(message_id);
       const message = g_message_manager.?.getMessage(session.id, msg_id) catch |err| {
           error_handling.setError(err, "Message not found", .{});
           return error_handling.errorToCode(err);
       };
       
       // Set provider info
       message.provider_info = ProviderInfo{
           .provider_id = std.mem.span(provider_id),
           .model_id = std.mem.span(model_id),
           .request_id = null,
       };
       
       // Create streaming handler
       var handler = StreamingHandler.init(g_allocator, message, callback, user_data) catch |err| {
           error_handling.setError(err, "Failed to create stream handler", .{});
           return error_handling.errorToCode(err);
       };
       
       // Spawn AI provider process
       const provider_request = try json.stringify(g_allocator, .{
           .action = "stream_chat",
           .provider = std.mem.span(provider_id),
           .params = .{
               .messages = try g_message_manager.?.getMessagesForProvider(session.id),
               .model = std.mem.span(model_id),
               .options = .{},
           },
       }, .{});
       defer g_allocator.free(provider_request);
       
       // Stream from provider executable
       streamFromProvider(provider_request, &handler, session.abort_source) catch |err| {
           error_handling.setError(err, "Streaming failed", .{});
           return error_handling.errorToCode(err);
       };
       
       return 0;
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write tests first**:
   - Test message creation and parts
   - Test message persistence
   - Test streaming updates
   - Test token counting and costs
   - Test tool invocation tracking
   - Test concurrent message handling

2. **Implement incrementally**:
   - Basic message structure
   - Part types implementation
   - Message manager operations
   - Streaming infrastructure
   - FFI integration
   - Provider communication

3. **Commit frequently**:
   - After message types defined
   - After part types implemented
   - After manager works
   - After streaming works
   - After FFI complete

### Git Workflow

```bash
git worktree add worktrees/message-system -b feat/message-system
cd worktrees/message-system
```

Commits:
- `feat: define message and part data structures`
- `feat: implement message manager with persistence`
- `feat: add streaming response handler`
- `feat: integrate tool invocations with messages`
- `feat: implement token usage and cost tracking`
- `feat: export message FFI functions`
- `test: comprehensive message system tests`

## Success Criteria

✅ **Task is complete when**:
1. Messages can be sent with text and file attachments
2. Messages persist correctly within sessions
3. Streaming updates work in real-time
4. Tool invocations are tracked properly
5. Token usage and costs are calculated accurately
6. All FFI functions work from Swift
7. Concurrent operations are thread-safe
8. Test coverage exceeds 95%

## Technical Considerations

<zig_patterns>
- Use tagged unions for part types
- Implement proper memory management for streaming
- Leverage arena allocators for temporary data
- Follow single ownership for message data
- Use atomics for concurrent counters
</zig_patterns>

<streaming_requirements>
- Minimize latency for first token
- Handle backpressure appropriately
- Support partial message recovery
- Clean up resources on abort
- Test with slow/fast streams
</streaming_requirements>

<integration_notes>
- Coordinate with session manager for persistence
- Interface with AI provider wrapper for streaming
- Prepare for tool system integration
- Consider event bus for updates
- Design for future search capabilities
</integration_notes>

Remember: The message system is how users interact with AI. Make it fast, reliable, and feature-rich. This is a critical component of the user experience.