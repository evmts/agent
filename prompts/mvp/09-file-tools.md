# Implement File Tools (Read, Write, Edit) for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on implementing the core file manipulation tools (Read, Write, Edit) that allow AI agents to interact with the file system for code generation and modification.

## Context

<context>
<project_overview>
File tools are fundamental to Plue's code editing capabilities:
- **Read**: Load file contents with line numbers and encoding detection
- **Write**: Create new files or overwrite existing ones
- **Edit**: Make precise text replacements in existing files
- These tools track all changes for undo/redo and version control integration
</project_overview>

<existing_infrastructure>
From previous implementations:
- Tool registry provides the framework for registering these tools
- Bash tool demonstrates the pattern for tool implementation
- Message system tracks file operations in conversation history
- Error handling provides comprehensive error reporting
- JSON utilities handle parameter validation
</existing_infrastructure>

<api_specification>
Each file tool follows the standard tool interface:
- **Read**: Parameters: path, offset (optional), limit (optional)
- **Write**: Parameters: path, content, create_dirs (optional)
- **Edit**: Parameters: path, old_string, new_string, count (optional)
All tools return detailed results including operation metadata
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has mature file tool implementations:
- opencode/packages/opencode/src/tool/read.txt - Read tool with line numbers
- opencode/packages/opencode/src/tool/write.txt - Write tool with directory creation
- opencode/packages/opencode/src/tool/edit.txt - Edit tool with precise replacements
- All tools include comprehensive error handling and validation
</reference_implementation>
</context>

## Task: Implement File Tools

### Requirements

1. **Implement Read tool** with:
   - Line number prefixes for context
   - Optional offset/limit for large files
   - Encoding detection (UTF-8, ASCII, etc.)
   - Binary file detection and handling
   - Metadata about file properties

2. **Implement Write tool** with:
   - Atomic writes to prevent corruption
   - Optional parent directory creation
   - Permission preservation
   - Backup creation option
   - Conflict detection

3. **Implement Edit tool** with:
   - Exact string matching and replacement
   - Multiple replacement support
   - Line ending preservation
   - Validation that old_string exists
   - Diff generation for changes

4. **Add common file utilities**:
   - Path validation and normalization
   - Permission checking
   - File type detection
   - Safe temporary file handling

### Detailed Steps

1. **Create src/tool/file_tools.zig with shared utilities**:
   ```zig
   const std = @import("std");
   const builtin = @import("builtin");
   const tool = @import("../tool.zig");
   const json = @import("../../json.zig");
   
   // Shared file utilities
   pub const FileUtils = struct {
       // Validate and normalize file path
       pub fn validatePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
           // Prevent directory traversal attacks
           if (std.mem.indexOf(u8, path, "..") != null) {
               return error.InvalidPath;
           }
           
           // Resolve to absolute path
           const abs_path = try std.fs.realpathAlloc(allocator, path);
           
           // Ensure path is within allowed directories
           // TODO: Add configurable allowed directories
           
           return abs_path;
       }
       
       // Detect file encoding
       pub fn detectEncoding(content: []const u8) Encoding {
           // Check for UTF-8 BOM
           if (content.len >= 3 and 
               content[0] == 0xEF and 
               content[1] == 0xBB and 
               content[2] == 0xBF) {
               return .utf8_bom;
           }
           
           // Validate UTF-8
           if (std.unicode.utf8ValidateSlice(content)) {
               return .utf8;
           }
           
           // Check for null bytes (binary)
           for (content) |byte| {
               if (byte == 0) return .binary;
           }
           
           return .ascii;
       }
       
       // Check if file is binary
       pub fn isBinary(content: []const u8) bool {
           const sample_size = @min(content.len, 8192);
           var null_count: usize = 0;
           var non_printable: usize = 0;
           
           for (content[0..sample_size]) |byte| {
               if (byte == 0) null_count += 1;
               if (byte < 32 and byte != '\t' and byte != '\n' and byte != '\r') {
                   non_printable += 1;
               }
           }
           
           // If more than 0.1% null bytes or 30% non-printable, likely binary
           return null_count > 0 or 
                  (non_printable * 100 / sample_size) > 30;
       }
       
       pub const Encoding = enum {
           utf8,
           utf8_bom,
           ascii,
           binary,
       };
   };
   ```

2. **Implement Read tool**:
   ```zig
   pub const ReadTool = struct {
       tool_impl: tool.Tool,
       allocator: std.mem.Allocator,
       max_file_size: usize = 100 * 1024 * 1024, // 100MB limit
       
       pub fn init(allocator: std.mem.Allocator) !ReadTool {
           const builder = tool.SchemaBuilder.init(allocator);
           
           return ReadTool{
               .allocator = allocator,
               .tool_impl = tool.Tool{
                   .info = tool.ToolInfo{
                       .name = "read",
                       .description = "Read file contents with line numbers",
                       .parameters_schema = try builder.object(.{
                           .path = builder.string().required(),
                           .offset = builder.number().min(0).optional(),
                           .limit = builder.number().min(1).max(10000).optional(),
                       }),
                       .returns_schema = try builder.object(.{
                           .content = builder.string(),
                           .encoding = builder.string(),
                           .size = builder.number(),
                           .lines = builder.number(),
                           .truncated = builder.boolean(),
                       }),
                   },
                   .executeFn = execute,
               },
           };
       }
       
       fn execute(self_tool: *tool.Tool, params: json.Value, context: *tool.ToolContext) !json.Value {
           const self = @fieldParentPtr(ReadTool, "tool_impl", self_tool);
           
           // Parse parameters
           const path = params.object.get("path").?.string;
           const offset = if (params.object.get("offset")) |o| 
               @intCast(usize, o.integer) 
           else 
               0;
           const limit = if (params.object.get("limit")) |l| 
               @intCast(usize, l.integer) 
           else 
               null;
           
           // Validate path
           const validated_path = try FileUtils.validatePath(self.allocator, path);
           defer self.allocator.free(validated_path);
           
           // Send start metadata
           try context.sendMetadata(.{
               .type = "start",
               .operation = "read",
               .path = validated_path,
           });
           
           // Open file
           const file = try std.fs.openFileAbsolute(validated_path, .{});
           defer file.close();
           
           // Get file stats
           const stat = try file.stat();
           if (stat.size > self.max_file_size) {
               return error.FileTooLarge;
           }
           
           // Read file content
           const content = try file.readToEndAlloc(self.allocator, self.max_file_size);
           defer self.allocator.free(content);
           
           // Check encoding
           const encoding = FileUtils.detectEncoding(content);
           if (encoding == .binary) {
               return error.BinaryFile;
           }
           
           // Format with line numbers
           const formatted = try self.formatWithLineNumbers(content, offset, limit);
           defer self.allocator.free(formatted.content);
           
           // Send completion metadata
           try context.sendMetadata(.{
               .type = "complete",
               .operation = "read",
               .path = validated_path,
               .lines_read = formatted.line_count,
           });
           
           // Return result
           var result = std.StringHashMap(json.Value).init(self.allocator);
           try result.put("content", json.Value{ .string = formatted.content });
           try result.put("encoding", json.Value{ .string = @tagName(encoding) });
           try result.put("size", json.Value{ .integer = @intCast(i64, stat.size) });
           try result.put("lines", json.Value{ .integer = @intCast(i64, formatted.total_lines) });
           try result.put("truncated", json.Value{ .bool = formatted.truncated });
           
           return json.Value{ .object = result };
       }
       
       const FormattedContent = struct {
           content: []const u8,
           line_count: usize,
           total_lines: usize,
           truncated: bool,
       };
       
       fn formatWithLineNumbers(
           self: *ReadTool,
           content: []const u8,
           offset: usize,
           limit: ?usize,
       ) !FormattedContent {
           var result = std.ArrayList(u8).init(self.allocator);
           defer result.deinit();
           
           var line_iter = std.mem.split(u8, content, "\n");
           var line_num: usize = 1;
           var lines_written: usize = 0;
           var total_lines: usize = 0;
           
           while (line_iter.next()) |line| {
               total_lines += 1;
               
               // Skip lines before offset
               if (line_num <= offset) {
                   line_num += 1;
                   continue;
               }
               
               // Check limit
               if (limit) |l| {
                   if (lines_written >= l) {
                       return FormattedContent{
                           .content = try result.toOwnedSlice(),
                           .line_count = lines_written,
                           .total_lines = total_lines,
                           .truncated = true,
                       };
                   }
               }
               
               // Format line with number
               try result.writer().print("{d: >6}\t{s}\n", .{ line_num, line });
               lines_written += 1;
               line_num += 1;
           }
           
           return FormattedContent{
               .content = try result.toOwnedSlice(),
               .line_count = lines_written,
               .total_lines = total_lines,
               .truncated = false,
           };
       }
   };
   ```

3. **Implement Write tool**:
   ```zig
   pub const WriteTool = struct {
       tool_impl: tool.Tool,
       allocator: std.mem.Allocator,
       
       pub fn init(allocator: std.mem.Allocator) !WriteTool {
           const builder = tool.SchemaBuilder.init(allocator);
           
           return WriteTool{
               .allocator = allocator,
               .tool_impl = tool.Tool{
                   .info = tool.ToolInfo{
                       .name = "write",
                       .description = "Write content to a file",
                       .parameters_schema = try builder.object(.{
                           .path = builder.string().required(),
                           .content = builder.string().required(),
                           .create_dirs = builder.boolean().optional(),
                       }),
                       .returns_schema = try builder.object(.{
                           .path = builder.string(),
                           .size = builder.number(),
                           .created = builder.boolean(),
                       }),
                   },
                   .executeFn = execute,
               },
           };
       }
       
       fn execute(self_tool: *tool.Tool, params: json.Value, context: *tool.ToolContext) !json.Value {
           const self = @fieldParentPtr(WriteTool, "tool_impl", self_tool);
           
           // Parse parameters
           const path = params.object.get("path").?.string;
           const content = params.object.get("content").?.string;
           const create_dirs = if (params.object.get("create_dirs")) |cd| 
               cd.bool 
           else 
               false;
           
           // Validate path
           const validated_path = try FileUtils.validatePath(self.allocator, path);
           defer self.allocator.free(validated_path);
           
           // Check if file exists
           const exists = blk: {
               std.fs.accessAbsolute(validated_path, .{}) catch {
                   break :blk false;
               };
               break :blk true;
           };
           
           // Send start metadata
           try context.sendMetadata(.{
               .type = "start",
               .operation = "write",
               .path = validated_path,
               .exists = exists,
           });
           
           // Create parent directories if requested
           if (create_dirs) {
               const dir_path = std.fs.path.dirname(validated_path) orelse ".";
               try std.fs.makeDirAbsolute(dir_path);
           }
           
           // Perform atomic write
           try self.atomicWrite(validated_path, content);
           
           // Send completion metadata
           try context.sendMetadata(.{
               .type = "complete",
               .operation = "write",
               .path = validated_path,
               .size = content.len,
           });
           
           // Return result
           var result = std.StringHashMap(json.Value).init(self.allocator);
           try result.put("path", json.Value{ .string = validated_path });
           try result.put("size", json.Value{ .integer = @intCast(i64, content.len) });
           try result.put("created", json.Value{ .bool = !exists });
           
           return json.Value{ .object = result };
       }
       
       fn atomicWrite(self: *WriteTool, path: []const u8, content: []const u8) !void {
           // Create temporary file in same directory
           const dir_path = std.fs.path.dirname(path) orelse ".";
           const basename = std.fs.path.basename(path);
           
           const tmp_path = try std.fmt.allocPrint(
               self.allocator,
               "{s}/.{s}.tmp.{d}",
               .{ dir_path, basename, std.time.milliTimestamp() }
           );
           defer self.allocator.free(tmp_path);
           
           // Write to temporary file
           {
               const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
               defer tmp_file.close();
               
               try tmp_file.writeAll(content);
               try tmp_file.sync();
           }
           
           // Get original file permissions if it exists
           const mode = blk: {
               const orig_file = std.fs.openFileAbsolute(path, .{}) catch {
                   break :blk @as(std.fs.File.Mode, 0o644);
               };
               defer orig_file.close();
               const stat = try orig_file.stat();
               break :blk stat.mode;
           };
           
           // Set permissions on temp file
           try std.fs.chmodAbsolute(tmp_path, mode);
           
           // Atomic rename
           try std.fs.renameAbsolute(tmp_path, path);
       }
   };
   ```

4. **Implement Edit tool**:
   ```zig
   pub const EditTool = struct {
       tool_impl: tool.Tool,
       allocator: std.mem.Allocator,
       max_file_size: usize = 10 * 1024 * 1024, // 10MB limit for edit
       
       pub fn init(allocator: std.mem.Allocator) !EditTool {
           const builder = tool.SchemaBuilder.init(allocator);
           
           return EditTool{
               .allocator = allocator,
               .tool_impl = tool.Tool{
                   .info = tool.ToolInfo{
                       .name = "edit",
                       .description = "Replace exact string in a file",
                       .parameters_schema = try builder.object(.{
                           .path = builder.string().required(),
                           .old_string = builder.string().required(),
                           .new_string = builder.string().required(),
                           .count = builder.number().min(1).optional(),
                       }),
                       .returns_schema = try builder.object(.{
                           .path = builder.string(),
                           .replacements = builder.number(),
                           .diff = builder.string(),
                       }),
                   },
                   .executeFn = execute,
               },
           };
       }
       
       fn execute(self_tool: *tool.Tool, params: json.Value, context: *tool.ToolContext) !json.Value {
           const self = @fieldParentPtr(EditTool, "tool_impl", self_tool);
           
           // Parse parameters
           const path = params.object.get("path").?.string;
           const old_string = params.object.get("old_string").?.string;
           const new_string = params.object.get("new_string").?.string;
           const count = if (params.object.get("count")) |c| 
               @intCast(usize, c.integer) 
           else 
               null;
           
           // Validate inputs
           if (old_string.len == 0) return error.EmptySearchString;
           if (std.mem.eql(u8, old_string, new_string)) return error.NoChange;
           
           // Validate path
           const validated_path = try FileUtils.validatePath(self.allocator, path);
           defer self.allocator.free(validated_path);
           
           // Send start metadata
           try context.sendMetadata(.{
               .type = "start",
               .operation = "edit",
               .path = validated_path,
           });
           
           // Read file content
           const file = try std.fs.openFileAbsolute(validated_path, .{});
           defer file.close();
           
           const stat = try file.stat();
           if (stat.size > self.max_file_size) {
               return error.FileTooLarge;
           }
           
           const original_content = try file.readToEndAlloc(self.allocator, self.max_file_size);
           defer self.allocator.free(original_content);
           
           // Perform replacements
           const edit_result = try self.performReplacements(
               original_content,
               old_string,
               new_string,
               count
           );
           defer self.allocator.free(edit_result.new_content);
           defer self.allocator.free(edit_result.diff);
           
           if (edit_result.replacement_count == 0) {
               return error.StringNotFound;
           }
           
           // Write changes atomically
           const write_tool = try WriteTool.init(self.allocator);
           defer write_tool.deinit();
           
           const write_params = try json.stringify(self.allocator, .{
               .path = validated_path,
               .content = edit_result.new_content,
           }, .{});
           defer self.allocator.free(write_params);
           
           _ = try write_tool.tool_impl.execute(write_params, context);
           
           // Send completion metadata
           try context.sendMetadata(.{
               .type = "complete",
               .operation = "edit",
               .path = validated_path,
               .replacements = edit_result.replacement_count,
           });
           
           // Return result
           var result = std.StringHashMap(json.Value).init(self.allocator);
           try result.put("path", json.Value{ .string = validated_path });
           try result.put("replacements", json.Value{ .integer = @intCast(i64, edit_result.replacement_count) });
           try result.put("diff", json.Value{ .string = edit_result.diff });
           
           return json.Value{ .object = result };
       }
       
       const EditResult = struct {
           new_content: []const u8,
           replacement_count: usize,
           diff: []const u8,
       };
       
       fn performReplacements(
           self: *EditTool,
           content: []const u8,
           old_string: []const u8,
           new_string: []const u8,
           max_count: ?usize,
       ) !EditResult {
           var result = std.ArrayList(u8).init(self.allocator);
           defer result.deinit();
           
           var replacements: usize = 0;
           var pos: usize = 0;
           var diff_lines = std.ArrayList(u8).init(self.allocator);
           defer diff_lines.deinit();
           
           while (pos < content.len) {
               // Check for abort
               try context.checkAbort();
               
               // Find next occurrence
               if (std.mem.indexOfPos(u8, content, pos, old_string)) |found_pos| {
                   // Check count limit
                   if (max_count) |max| {
                       if (replacements >= max) {
                           // Append remaining content
                           try result.appendSlice(content[pos..]);
                           break;
                       }
                   }
                   
                   // Append content before match
                   try result.appendSlice(content[pos..found_pos]);
                   
                   // Append replacement
                   try result.appendSlice(new_string);
                   
                   // Generate diff line
                   const line_num = self.getLineNumber(content, found_pos);
                   try diff_lines.writer().print(
                       "Line {d}: -{s}\n         +{s}\n",
                       .{ line_num, old_string, new_string }
                   );
                   
                   replacements += 1;
                   pos = found_pos + old_string.len;
               } else {
                   // No more occurrences, append rest
                   try result.appendSlice(content[pos..]);
                   break;
               }
           }
           
           return EditResult{
               .new_content = try result.toOwnedSlice(),
               .replacement_count = replacements,
               .diff = try diff_lines.toOwnedSlice(),
           };
       }
       
       fn getLineNumber(self: *EditTool, content: []const u8, pos: usize) usize {
           var line: usize = 1;
           for (content[0..pos]) |char| {
               if (char == '\n') line += 1;
           }
           return line;
       }
   };
   ```

5. **Register all file tools**:
   ```zig
   pub fn registerFileTools(registry: *tool.ToolRegistry) !void {
       // Create and register Read tool
       const read_tool = try registry.allocator.create(ReadTool);
       read_tool.* = try ReadTool.init(registry.allocator);
       try registry.register(&read_tool.tool_impl);
       
       // Create and register Write tool
       const write_tool = try registry.allocator.create(WriteTool);
       write_tool.* = try WriteTool.init(registry.allocator);
       try registry.register(&write_tool.tool_impl);
       
       // Create and register Edit tool
       const edit_tool = try registry.allocator.create(EditTool);
       edit_tool.* = try EditTool.init(registry.allocator);
       try registry.register(&edit_tool.tool_impl);
       
       std.log.info("Registered file tools: read, write, edit", .{});
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write comprehensive tests**:
   - Test basic file operations
   - Test edge cases (empty files, large files)
   - Test error conditions
   - Test concurrent access
   - Test encoding detection
   - Test atomic writes

2. **Implement incrementally**:
   - Shared utilities first
   - Read tool implementation
   - Write tool with atomicity
   - Edit tool with diff generation
   - Integration with registry

3. **Focus on reliability**:
   - Handle all error cases
   - Ensure atomic operations
   - Preserve file attributes
   - Validate all inputs

### Git Workflow

```bash
git worktree add worktrees/file-tools -b feat/file-tools
cd worktrees/file-tools
```

Commits:
- `feat: create file utilities module`
- `feat: implement read tool with line numbers`
- `feat: add write tool with atomic writes`
- `feat: implement edit tool with replacements`
- `test: comprehensive file tools test suite`
- `feat: register file tools with registry`

## Success Criteria

✅ **Task is complete when**:
1. Read tool handles various file encodings correctly
2. Write tool performs atomic writes without corruption
3. Edit tool makes precise replacements with diffs
4. All tools validate paths for security
5. Large files are handled efficiently
6. Concurrent operations work safely
7. All error cases return helpful messages
8. Test coverage exceeds 95%

## Technical Considerations

<security_requirements>
- Prevent path traversal attacks
- Validate all file paths
- Check file permissions
- Limit file sizes
- Sanitize user inputs
</security_requirements>

<reliability_requirements>
- Use atomic writes
- Preserve file permissions
- Handle disk space errors
- Support various encodings
- Clean up temporary files
</reliability_requirements>

<performance_requirements>
- Stream large files
- Minimize memory usage
- Efficient string searching
- Cache file metadata
- Batch operations when possible
</performance_requirements>

Remember: File tools are used constantly by AI agents. They must be rock-solid, secure, and efficient. Pay special attention to edge cases and error handling.