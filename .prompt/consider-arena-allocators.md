# Consider Arena Allocators for Complex Temporary Allocations

## Priority: Low

## Problem
Some parts of the codebase perform complex temporary allocations that could benefit from arena allocators for simpler memory management and potentially better performance.

## Potential Areas for Improvement

### 1. LFS Storage MockDatabaseConnection (src/lfs/storage.zig)
The `MockDatabaseConnection` manages individual string allocations that could be simplified:

```zig
// Current approach - manual cleanup of each field
var iterator = self.metadata_store.iterator();
while (iterator.next()) |entry| {
    self.allocator.free(entry.value_ptr.checksum);
    if (entry.value_ptr.content_type) |ct| {
        self.allocator.free(ct);
    }
}
```

**Could become:**
```zig
// With arena allocator
pub const MockDatabaseConnection = struct {
    arena: std.heap.ArenaAllocator,
    metadata_store: std.HashMap(...),
    
    pub fn init(backing_allocator: std.mem.Allocator) MockDatabaseConnection {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .metadata_store = std.HashMap(...).init(arena.allocator()),
        };
    }
    
    pub fn deinit(self: *MockDatabaseConnection) void {
        self.arena.deinit(); // Frees everything at once
    }
};
```

### 2. HTTP Request Processing
Request handlers that build complex JSON responses could use arena allocators:

```zig
pub fn complexHandler(r: zap.Request, ctx: *Context) !void {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();
    
    // All temporary allocations use temp_allocator
    // Automatic cleanup when function exits
}
```

### 3. Batch Operations in LFS
The batch processing code could benefit from arena allocators for temporary data structures.

## Expected Solution

1. **Identify suitable use cases**:
   - Operations with many temporary allocations
   - Functions with complex cleanup logic
   - Request processing with temporary data structures

2. **Implement arena allocator patterns**:
   ```zig
   fn complexOperation(backing_allocator: std.mem.Allocator, data: SomeData) !Result {
       var arena = std.heap.ArenaAllocator.init(backing_allocator);
       defer arena.deinit();
       const temp_allocator = arena.allocator();
       
       // Use temp_allocator for all temporary allocations
       const temp_buffer = try temp_allocator.alloc(u8, 1024);
       const temp_list = std.ArrayList(Item).init(temp_allocator);
       
       // No need for individual cleanup - arena handles it all
       
       // Only allocate final result with backing_allocator if needed
       return try backing_allocator.dupe(u8, final_result);
   }
   ```

3. **Create utility functions** for common patterns:
   ```zig
   // src/utils/arena_helpers.zig
   pub fn withArena(
       backing_allocator: std.mem.Allocator,
       comptime func: anytype,
       args: anytype
   ) !@typeInfo(@TypeOf(func)).Fn.return_type.? {
       var arena = std.heap.ArenaAllocator.init(backing_allocator);
       defer arena.deinit();
       
       return @call(.auto, func, .{arena.allocator()} ++ args);
   }
   ```

## Areas to Evaluate
- `src/lfs/storage.zig` - MockDatabaseConnection and batch operations
- `src/server/handlers/*.zig` - Request processing with temporary data
- `src/actions/executor.zig` - Step execution with temporary allocations
- `src/git/command.zig` - Command processing with temporary buffers

## Benefits
- Simplified memory management (single deinit call)
- Reduced chance of memory leaks
- Potentially better performance for allocation-heavy operations
- Cleaner error handling (no complex cleanup in error paths)

## Considerations
- Arena allocators use more memory (no individual deallocation)
- Not suitable for long-running operations with many allocations
- Should only be used for operations with clear scope boundaries

## Files to Potentially Modify
- `src/lfs/storage.zig`
- `src/server/handlers/*.zig`
- `src/actions/executor.zig`
- Create `src/utils/arena_helpers.zig` for common patterns

## Testing
- Ensure memory usage doesn't increase significantly
- Verify all temporary data is properly cleaned up
- Performance testing for allocation-heavy operations
- Memory leak testing with valgrind or similar tools

## Implementation Approach
1. Start with one clear use case (like MockDatabaseConnection)
2. Measure memory usage and performance impact
3. Create reusable patterns and utilities
4. Gradually apply to other suitable areas
5. Document when to use arena vs. regular allocators