# Implement Comprehensive JSON Utilities for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on creating robust JSON serialization/deserialization utilities that will be used throughout the system for FFI communication, state management, and IPC with Bun executables.

## Context

<context>
<project_overview>
Plue is a multi-agent coding assistant where JSON is the primary data interchange format:
- Swift UI communicates with Zig via JSON state snapshots
- Zig communicates with Bun executables via JSON IPC
- All API responses are JSON formatted
- Configuration files use JSON/JSONC format
- Error details are returned as JSON
</project_overview>

<existing_code>
The project currently uses basic std.json functionality in several places:
- src/libplue.zig: Uses std.json.stringify for state serialization
- Various state modules: Define structs that need JSON serialization
- The codebase needs a unified, efficient JSON handling system
</existing_code>

<api_requirements>
From PLUE_CORE_API.md, JSON is used extensively:
- State snapshots: Complete application state as JSON
- Event data: All events include JSON payloads  
- Tool parameters: Tools receive/return JSON
- Provider communication: JSON protocol with Bun executables
- Configuration: JSON-based configuration with schema validation
</api_requirements>

<reference_implementation>
OpenCode (in opencode/) has mature JSON handling patterns:
- Streaming JSON parsing for large responses
- Schema validation for configuration
- Efficient serialization with custom formatters
- JSONC (JSON with Comments) support for config files
</reference_implementation>
</context>

## Task: Implement Comprehensive JSON Utilities

### Requirements

1. **Create a unified JSON module** that provides:
   - High-performance serialization/deserialization
   - Streaming support for large payloads
   - Custom type serialization (dates, enums, etc.)
   - Validation against schemas
   - JSONC parsing for configuration files

2. **Implement memory-efficient patterns**:
   - Reusable buffers for serialization
   - Arena allocator integration
   - Streaming parsing for large inputs
   - Zero-copy parsing where possible

3. **Add type-safe wrappers** for common patterns:
   - Request/Response serialization
   - State snapshot formatting
   - Event payload handling
   - Error context serialization

4. **Create JSON schema validation**:
   - Runtime validation against schemas
   - Clear error messages for validation failures
   - Integration with error handling system

### Detailed Steps

1. **Create src/json.zig with core utilities**:
   ```zig
   const std = @import("std");
   const Allocator = std.mem.Allocator;
   
   pub const JsonOptions = struct {
       // Serialization options
       whitespace: bool = false,
       emit_null_fields: bool = false,
       max_depth: u32 = 256,
       
       // Parsing options  
       allow_comments: bool = false,
       allow_trailing_commas: bool = false,
       duplicate_field_behavior: DuplicateFieldBehavior = .use_last,
   };
   
   pub const DuplicateFieldBehavior = enum {
       use_first,
       use_last,
       @"error",
   };
   ```

2. **Implement efficient serialization with custom formatters**:
   ```zig
   // Type-erased JSON value for dynamic data
   pub const Value = union(enum) {
       null,
       bool: bool,
       integer: i64,
       float: f64,
       string: []const u8,
       array: ArrayList(Value),
       object: StringHashMap(Value),
       
       pub fn stringify(self: Value, writer: anytype, options: JsonOptions) !void {
           // Efficient serialization with options
       }
   };
   
   // Serialize any Zig type to JSON
   pub fn stringify(value: anytype, writer: anytype, options: JsonOptions) !void {
       // Handle all Zig types including custom serialization
   }
   
   // Convenience function with allocation
   pub fn stringifyAlloc(allocator: Allocator, value: anytype, options: JsonOptions) ![]u8 {
       // Serialize to allocated string
   }
   ```

3. **Add streaming JSON parsing**:
   ```zig
   pub const StreamingParser = struct {
       allocator: Allocator,
       state: ParserState,
       depth: u32,
       options: JsonOptions,
       
       pub fn init(allocator: Allocator, options: JsonOptions) StreamingParser {
           // Initialize parser state
       }
       
       pub fn feed(self: *StreamingParser, data: []const u8) !void {
           // Process chunk of JSON data
       }
       
       pub fn finish(self: *StreamingParser) !Value {
           // Complete parsing and return result
       }
   };
   ```

4. **Implement JSONC (JSON with Comments) support**:
   ```zig
   pub const JsoncParser = struct {
       // Strip comments and trailing commas before parsing
       pub fn parse(allocator: Allocator, jsonc: []const u8) !Value {
           // Handle single-line // and multi-line /* */ comments
           // Allow trailing commas in objects and arrays
       }
       
       pub fn parseFile(allocator: Allocator, path: []const u8) !Value {
           // Read and parse JSONC file
       }
   };
   ```

5. **Create type-safe parsing with validation**:
   ```zig
   // Parse JSON into specific type with validation
   pub fn parseInto(comptime T: type, allocator: Allocator, json: []const u8, options: JsonOptions) !T {
       // Parse and validate against type structure
   }
   
   // Custom parsing for specific types
   pub fn parseCustom(comptime T: type, allocator: Allocator, value: Value) !T {
       // Allow types to implement custom parseJson method
       if (@hasDecl(T, "parseJson")) {
           return T.parseJson(allocator, value);
       }
       // Default parsing logic
   }
   ```

6. **Add JSON Schema validation**:
   ```zig
   pub const Schema = struct {
       root: SchemaNode,
       
       pub fn validate(self: Schema, value: Value) !void {
           // Validate value against schema
           // Return detailed errors on validation failure
       }
       
       pub fn fromJson(allocator: Allocator, schema_json: []const u8) !Schema {
           // Parse JSON Schema definition
       }
   };
   
   const SchemaNode = union(enum) {
       object: ObjectSchema,
       array: ArraySchema,
       string: StringSchema,
       number: NumberSchema,
       boolean: void,
       null: void,
       any_of: []SchemaNode,
       // ... other JSON Schema types
   };
   ```

7. **Implement common patterns for the project**:
   ```zig
   // FFI response formatting
   pub fn formatFfiResponse(allocator: Allocator, data: anytype) ![]u8 {
       // Consistent formatting for FFI boundaries
   }
   
   // State snapshot formatting
   pub fn formatStateSnapshot(allocator: Allocator, state: anytype) ![]u8 {
       // Optimized state serialization
   }
   
   // Event payload formatting
   pub fn formatEvent(allocator: Allocator, event_type: []const u8, data: anytype) ![]u8 {
       // Standard event format
   }
   
   // IPC protocol formatting
   pub fn formatIpcRequest(allocator: Allocator, action: []const u8, params: anytype) ![]u8 {
       // Format for Bun executable communication
   }
   ```

8. **Add performance optimizations**:
   ```zig
   pub const BufferedWriter = struct {
       buffer: []u8,
       pos: usize,
       
       // Reusable buffer for multiple serializations
       pub fn reset(self: *BufferedWriter) void {
           self.pos = 0;
       }
   };
   
   pub const ArenaJsonSerializer = struct {
       arena: ArenaAllocator,
       
       // Use arena for temporary allocations during serialization
       pub fn stringify(self: *ArenaJsonSerializer, value: anytype) ![]u8 {
           // Serialize using arena, return final string
       }
   };
   ```

### Implementation Approach

Follow TDD methodology:

1. **Start with comprehensive tests**:
   - Test basic types (null, bool, numbers, strings)
   - Test complex types (arrays, objects, nested structures)
   - Test custom serialization
   - Test JSONC parsing
   - Test schema validation
   - Test error cases and edge conditions
   - Benchmark performance

2. **Implement incrementally**:
   - Basic serialization first
   - Then parsing
   - Add JSONC support
   - Implement schema validation
   - Add optimizations last

3. **Commit frequently**:
   - After basic serialization works
   - After parsing implementation
   - After JSONC support
   - After schema validation
   - After each optimization

### Git Workflow

```bash
git worktree add worktrees/json-utilities -b feat/json-utilities
cd worktrees/json-utilities
```

Commits:
- `feat: create json module with basic serialization`
- `feat: add streaming json parser implementation`
- `feat: implement jsonc comment stripping parser`
- `feat: add json schema validation support`
- `feat: optimize json serialization with buffers`
- `test: comprehensive json utility test suite`
- `refactor: migrate existing json usage to new module`

## Success Criteria

✅ **Task is complete when**:
1. All existing JSON usage is migrated to new utilities
2. JSONC files can be parsed (with comments and trailing commas)
3. Large JSON payloads can be streamed efficiently
4. Schema validation works with clear error messages
5. Performance is better than std.json for common cases
6. Memory usage is predictable with arena allocators
7. 100% test coverage for JSON utilities
8. Integration with error handling system works

## Technical Considerations

<zig_patterns>
- Use comptime for type introspection
- Leverage Zig's meta-programming for custom serialization
- Use error unions for all fallible operations
- Implement Writer interface for streaming
- Use slices to avoid allocations where possible
</zig_patterns>

<performance_goals>
- Serialization should be allocation-free for simple types
- Parsing should minimize allocations
- Support zero-copy parsing for string values
- Reuse buffers across multiple operations
- Arena allocator for temporary allocations
</performance_goals>

<integration_requirements>
- Must work with existing error handling system
- Should integrate with thread-local storage for errors
- Must support all types used in state management
- Should handle all IPC protocol requirements
</integration_requirements>

Remember: JSON handling is critical infrastructure. Make it robust, fast, and easy to use. Many components will depend on these utilities.