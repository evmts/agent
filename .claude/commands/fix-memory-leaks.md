# Fix Memory Leaks in Server

## Priority: MEDIUM | Reliability

## Problem

Several memory leak patterns identified:

1. **CSRF token store:** Tokens accumulate without cleanup
   - Location: `server/src/middleware/csrf.zig:38-48`

2. **Rate limit store:** Keys never freed, no TTL eviction
   - Location: `server/src/middleware/rate_limit.zig:67-76`

3. **Workflow executor:** JSON allocations on error paths
   - Location: `server/src/workflows/executor.zig:1122-1126`

## Task

### Phase 1: CSRF Token Store

1. **Add token limit and cleanup:**
   ```zig
   // server/src/middleware/csrf.zig

   const MAX_TOKENS_PER_SESSION = 5;
   const TOKEN_CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // 1 hour

   pub fn generateToken(self: *CsrfStore, session_key: []const u8) ![]const u8 {
       self.mutex.lock();
       defer self.mutex.unlock();

       // Check if session already has max tokens
       var session_tokens: u32 = 0;
       var oldest_token: ?[]const u8 = null;
       var oldest_time: i64 = std.math.maxInt(i64);

       var it = self.tokens.iterator();
       while (it.next()) |entry| {
           if (std.mem.startsWith(u8, entry.key_ptr.*, session_key)) {
               session_tokens += 1;
               if (entry.value_ptr.created_at < oldest_time) {
                   oldest_time = entry.value_ptr.created_at;
                   oldest_token = entry.key_ptr.*;
               }
           }
       }

       // Remove oldest if at limit
       if (session_tokens >= MAX_TOKENS_PER_SESSION) {
           if (oldest_token) |token| {
               self.allocator.free(token);
               _ = self.tokens.remove(token);
           }
       }

       // Generate and store new token
       // ...existing code...
   }
   ```

2. **Add background cleanup job:**
   ```zig
   pub fn startCleanupJob(self: *CsrfStore) !void {
       _ = try std.Thread.spawn(.{}, cleanupLoop, .{self});
   }

   fn cleanupLoop(self: *CsrfStore) void {
       while (true) {
           std.time.sleep(TOKEN_CLEANUP_INTERVAL_MS * std.time.ns_per_ms);
           self.cleanupExpired();
       }
   }
   ```

### Phase 2: Rate Limit Store

3. **Implement TTL-based cleanup:**
   ```zig
   // server/src/middleware/rate_limit.zig

   const CLEANUP_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

   fn cleanupExpiredEntries(allocator: std.mem.Allocator) void {
       store_mutex.lock();
       defer store_mutex.unlock();

       if (rate_limit_store) |*store| {
           const now = std.time.milliTimestamp();
           var to_remove = std.ArrayList([]const u8).init(allocator);
           defer to_remove.deinit();

           var it = store.iterator();
           while (it.next()) |entry| {
               if (now - entry.value_ptr.window_start > entry.value_ptr.window_ms * 2) {
                   // Entry is stale, mark for removal
                   to_remove.append(entry.key_ptr.*) catch continue;
               }
           }

           // Remove stale entries and free keys
           for (to_remove.items) |key| {
               if (store.fetchRemove(key)) |removed| {
                   allocator.free(removed.key);
               }
           }
       }
   }
   ```

4. **Fix initialization race condition:**
   ```zig
   var init_once = std.Thread.Once{};

   fn initStore(allocator: std.mem.Allocator) void {
       init_once.call(initStoreInternal, .{allocator});
   }

   fn initStoreInternal(allocator: std.mem.Allocator) void {
       rate_limit_store = std.StringHashMap(RateLimitEntry).init(allocator);
   }
   ```

### Phase 3: Workflow Executor

5. **Add errdefer for JSON allocations:**
   ```zig
   // server/src/workflows/executor.zig

   fn buildStepOutput(self: *Executor, stdout: []const u8, stderr: []const u8) !std.json.ObjectMap {
       var output_obj = std.json.ObjectMap.init(self.allocator);
       errdefer {
           // Clean up on error
           var it = output_obj.iterator();
           while (it.next()) |entry| {
               if (entry.value_ptr.* == .string) {
                   self.allocator.free(entry.value_ptr.string);
               }
           }
           output_obj.deinit();
       }

       const stdout_copy = try self.allocator.dupe(u8, stdout);
       errdefer self.allocator.free(stdout_copy);

       try output_obj.put("stdout", .{ .string = stdout_copy });

       const stderr_copy = try self.allocator.dupe(u8, stderr);
       errdefer self.allocator.free(stderr_copy);

       try output_obj.put("stderr", .{ .string = stderr_copy });

       return output_obj;
   }
   ```

### Phase 4: Memory Testing

6. **Add memory leak detection to tests:**
   ```zig
   // server/src/tests/memory_test.zig

   const testing_allocator = std.testing.allocator;

   test "CSRF store doesn't leak on repeated token generation" {
       var store = CsrfStore.init(testing_allocator);
       defer store.deinit();

       // Generate many tokens
       for (0..1000) |_| {
           _ = try store.generateToken("test-session");
       }

       // Cleanup
       store.cleanupAll();

       // testing_allocator will fail if any memory leaked
   }

   test "rate limiter doesn't leak keys" {
       initStore(testing_allocator);
       defer deinitStore();

       for (0..1000) |i| {
           const key = try std.fmt.allocPrint(testing_allocator, "key-{}", .{i});
           defer testing_allocator.free(key);
           _ = try checkRateLimit(key, .auth);
       }

       cleanupExpiredEntries(testing_allocator);
       // testing_allocator verifies no leaks
   }
   ```

7. **Add GeneralPurposeAllocator for production leak detection:**
   ```zig
   // server/src/main.zig (optional, for debugging)

   const gpa = std.heap.GeneralPurposeAllocator(.{
       .enable_memory_limit = true,
       .safety = true,
   }){};
   defer {
       const leaked = gpa.deinit();
       if (leaked) {
           std.log.err("Memory leaked!", .{});
       }
   }
   ```

## Acceptance Criteria

- [ ] CSRF tokens cleaned up on expiration
- [ ] Rate limit entries cleaned up periodically
- [ ] Workflow executor properly frees on error
- [ ] Memory tests pass with testing_allocator
- [ ] No memory growth under sustained load
- [ ] Monitoring for memory usage added
