# Fix DAO Allocator Usage

## Priority: High

## Problem
The `DataAccessObject.init()` function in `src/database/dao.zig` uses `std.heap.page_allocator` directly instead of using the allocator parameter that should be passed to it. This violates the project's memory management principles where allocators should be explicitly passed and used consistently.

## Current Code (Line 50)
```zig
const pool = try pg.Pool.initUri(std.heap.page_allocator, uri, .{ .size = 5 });
```

## Expected Solution
1. Update the function signature to accept an allocator parameter:
   ```zig
   pub fn init(allocator: std.mem.Allocator, connection_url: []const u8) !DataAccessObject
   ```

2. Use the passed allocator instead of page_allocator:
   ```zig
   const pool = try pg.Pool.initUri(allocator, uri, .{ .size = 5 });
   ```

3. Update all call sites to pass the appropriate allocator

## Files to Modify
- `src/database/dao.zig` (primary change)
- Any files that call `DataAccessObject.init()` (update call sites)

## Testing
- Ensure all existing tests continue to pass
- Run `zig build test` to verify no regressions
- Verify database operations still work correctly

## Context
This follows the project's coding standard that allocators should be explicitly passed rather than using global allocators like `page_allocator`. This improves memory management control and makes testing easier.