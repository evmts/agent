# Fix Race Condition in Issue Number Assignment

## Priority: HIGH | Data Integrity

## Problem

Issue number assignment uses non-atomic SELECT-then-INSERT:

`db/daos/issues.zig:136-140`
```zig
const num_row = try pool.row(
    \\SELECT COALESCE(MAX(issue_number), 0) + 1 FROM issues WHERE repository_id = $1
, .{repo_id});
// Gap between SELECT and INSERT allows race condition
const issue_number = num_row.issue_number;
// Later: INSERT INTO issues (..., issue_number, ...) VALUES (..., $x, ...)
```

Concurrent requests can get the same issue_number, causing unique constraint violations.

## Task

### Option A: Use Database Sequence (Recommended)

1. **Create per-repository sequence:**
   ```sql
   -- db/migrations/009_issue_sequences.sql

   -- Create function to get next issue number atomically
   CREATE OR REPLACE FUNCTION next_issue_number(repo_id INTEGER)
   RETURNS INTEGER AS $$
   DECLARE
     next_num INTEGER;
   BEGIN
     UPDATE repositories
     SET next_issue_number = next_issue_number + 1
     WHERE id = repo_id
     RETURNING next_issue_number INTO next_num;

     RETURN next_num;
   END;
   $$ LANGUAGE plpgsql;

   -- Add column to track next number
   ALTER TABLE repositories ADD COLUMN next_issue_number INTEGER DEFAULT 1;

   -- Initialize from existing data
   UPDATE repositories r SET next_issue_number = (
     SELECT COALESCE(MAX(issue_number), 0) + 1
     FROM issues i
     WHERE i.repository_id = r.id
   );
   ```

2. **Update DAO to use function:**
   ```zig
   // db/daos/issues.zig

   pub fn createIssue(pool: *Pool, ...) !Issue {
       // Get issue number atomically
       const num_row = try pool.row(
           \\SELECT next_issue_number($1) as issue_number
       , .{repo_id});

       const issue_number = num_row.issue_number;

       // Insert with guaranteed unique number
       try pool.exec(
           \\INSERT INTO issues (repository_id, issue_number, ...)
           \\VALUES ($1, $2, ...)
       , .{repo_id, issue_number, ...});
   }
   ```

### Option B: Use FOR UPDATE Lock

1. **Modify SELECT to acquire lock:**
   ```zig
   // Get number with row lock
   const num_row = try pool.row(
       \\SELECT COALESCE(MAX(issue_number), 0) + 1 as next_number
       \\FROM issues
       \\WHERE repository_id = $1
       \\FOR UPDATE
   , .{repo_id});
   ```

   Note: This locks all issue rows for the repo, which can cause contention.

### Option C: Optimistic Locking with Retry

1. **Use INSERT with retry on conflict:**
   ```zig
   pub fn createIssue(pool: *Pool, ...) !Issue {
       var attempts: u8 = 0;
       const max_attempts: u8 = 5;

       while (attempts < max_attempts) : (attempts += 1) {
           const num_row = try pool.row(
               \\SELECT COALESCE(MAX(issue_number), 0) + 1 as next_number
               \\FROM issues WHERE repository_id = $1
           , .{repo_id});

           const result = pool.exec(
               \\INSERT INTO issues (repository_id, issue_number, ...)
               \\VALUES ($1, $2, ...)
           , .{repo_id, num_row.next_number, ...});

           if (result) |_| {
               return try pool.row("SELECT * FROM issues WHERE id = lastval()");
           } else |err| {
               if (err == error.UniqueViolation) {
                   continue; // Retry with new number
               }
               return err;
           }
       }

       return error.TooManyRetries;
   }
   ```

2. **Implement the chosen solution**

3. **Write concurrency test:**
   ```zig
   test "concurrent issue creation gets unique numbers" {
       const pool = try setupTestPool();

       var threads: [10]std.Thread = undefined;
       for (&threads) |*t| {
           t.* = try std.Thread.spawn(.{}, createTestIssue, .{pool});
       }

       for (threads) |t| t.join();

       // Verify all issues have unique numbers
       const rows = try pool.query("SELECT issue_number FROM issues WHERE repository_id = $1", .{test_repo_id});
       var seen = std.AutoHashMap(i32, void).init(allocator);
       for (rows) |row| {
           try testing.expect(!seen.contains(row.issue_number));
           try seen.put(row.issue_number, {});
       }
   }
   ```

## Acceptance Criteria

- [ ] No unique constraint violations under concurrent load
- [ ] Issue numbers always sequential (no gaps under normal operation)
- [ ] Performance acceptable (< 10ms additional latency)
- [ ] Concurrency test passes with 100+ parallel requests
- [ ] Migration preserves existing issue numbers
