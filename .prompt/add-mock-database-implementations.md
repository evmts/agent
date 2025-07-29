# Add Mock Database Implementations

## Priority: Medium

## Problem
Many tests depend on PostgreSQL being available and properly configured. While the current tests gracefully skip when the database is unavailable, this limits testing capabilities and makes it harder to run tests in various environments.

## Current State
```zig
// Example from src/database/models/user.zig:95-103
var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
    error.ConnectionRefused => {
        std.log.warn("Database not available for testing, skipping", .{});
        return;
    },
    else => return err,
};
```

## Expected Solution

1. **Create a database interface**:
   ```zig
   // src/database/interface.zig
   pub const DatabaseInterface = struct {
       // Virtual function table pattern
       createUserFn: *const fn(*anyopaque, std.mem.Allocator, User) anyerror!void,
       getUserByIdFn: *const fn(*anyopaque, std.mem.Allocator, i64) anyerror!?User,
       // ... other database operations
       
       context: *anyopaque,
       
       pub fn createUser(self: *DatabaseInterface, allocator: std.mem.Allocator, user: User) !void {
           return self.createUserFn(self.context, allocator, user);
       }
       
       // ... wrapper methods
   };
   ```

2. **Create mock implementation**:
   ```zig
   // src/database/mock_dao.zig
   pub const MockDataAccessObject = struct {
       allocator: std.mem.Allocator,
       users: std.HashMap(i64, User, ...),
       next_user_id: i64,
       
       pub fn init(allocator: std.mem.Allocator) MockDataAccessObject {
           return MockDataAccessObject{
               .allocator = allocator,
               .users = std.HashMap(i64, User, ...).init(allocator),
               .next_user_id = 1,
           };
       }
       
       pub fn interface(self: *MockDataAccessObject) DatabaseInterface {
           return DatabaseInterface{
               .createUserFn = createUser,
               .getUserByIdFn = getUserById,
               // ...
               .context = self,
           };
       }
       
       fn createUser(context: *anyopaque, allocator: std.mem.Allocator, user: User) !void {
           const self: *MockDataAccessObject = @ptrCast(@alignCast(context));
           // In-memory implementation
       }
       
       // ... other methods
   };
   ```

3. **Update existing DAO to implement interface**:
   ```zig
   // src/database/dao.zig
   pub fn interface(self: *DataAccessObject) DatabaseInterface {
       return DatabaseInterface{
           .createUserFn = createUser,
           .getUserByIdFn = getUserById,
           // ...
           .context = self,
       };
   }
   ```

4. **Create test utilities**:
   ```zig
   // src/database/test_utils.zig
   pub fn getTestDatabase(allocator: std.mem.Allocator) !DatabaseInterface {
       if (std.posix.getenv("TEST_DATABASE_URL")) |url| {
           var dao = DataAccessObject.init(allocator, url) catch {
               // Fall back to mock
               var mock = try allocator.create(MockDataAccessObject);
               mock.* = MockDataAccessObject.init(allocator);
               return mock.interface();
           };
           return dao.interface();
       } else {
           var mock = try allocator.create(MockDataAccessObject);
           mock.* = MockDataAccessObject.init(allocator);
           return mock.interface();
       }
   }
   ```

## Files to Create/Modify
- **Create**: `src/database/interface.zig`
- **Create**: `src/database/mock_dao.zig`
- **Create**: `src/database/test_utils.zig`
- **Modify**: `src/database/dao.zig` (add interface method)
- **Modify**: Test files to use the new interface

## Benefits
- Tests can run without external dependencies
- Faster test execution (no network/disk I/O)
- More predictable test behavior
- Easier to test edge cases and error conditions
- Better CI/CD pipeline reliability

## Implementation Strategy
1. Start with a subset of database operations (User CRUD)
2. Create the interface and mock implementation
3. Update a few tests to use the new system
4. Gradually expand to cover all database operations
5. Update all tests to use the test utility

## Testing
- Ensure existing PostgreSQL tests still pass
- Add tests that verify mock behavior matches real database
- Test the interface abstraction works correctly
- Verify test utility fallback behavior