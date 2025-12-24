# Fix JSON Injection in createRunner

## Priority: HIGH | Security

## Problem

Labels are concatenated into JSON without escaping:

`db/root.zig:406-422`
```zig
try writer.writeByte('"');
try writer.writeAll(label);  // No escaping!
try writer.writeByte('"');
```

Attack payload: `label = "ubuntu\", \"injected\": \"payload"`
Results in: `["ubuntu", "injected": "payload"]`

## Task

1. **Analyze the vulnerability:**
   - Read `db/root.zig:396-430` (createRunner function)
   - Identify all places where strings are concatenated into JSON
   - Trace where label values come from

2. **Create JSON string escaping function:**
   ```zig
   // db/root.zig or lib/json_utils.zig

   pub fn writeJsonString(writer: anytype, str: []const u8) !void {
       try writer.writeByte('"');
       for (str) |c| {
           switch (c) {
               '"' => try writer.writeAll("\\\""),
               '\\' => try writer.writeAll("\\\\"),
               '\n' => try writer.writeAll("\\n"),
               '\r' => try writer.writeAll("\\r"),
               '\t' => try writer.writeAll("\\t"),
               // Control characters
               0x00...0x1F => {
                   try writer.print("\\u{x:0>4}", .{c});
               },
               else => try writer.writeByte(c),
           }
       }
       try writer.writeByte('"');
   }
   ```

3. **Fix createRunner function:**
   ```zig
   // Before (vulnerable)
   try writer.writeByte('"');
   try writer.writeAll(label);
   try writer.writeByte('"');

   // After (safe)
   try writeJsonString(writer, label);
   ```

4. **Alternative: Use std.json.stringify:**
   ```zig
   const labels_json = try std.json.stringifyAlloc(allocator, labels);
   defer allocator.free(labels_json);
   ```

5. **Audit other JSON construction:**
   - Search for manual JSON string building: `grep -rn 'writeByte.*"' db/`
   - Search for string concatenation into JSON
   - Fix all instances

6. **Write tests:**
   ```zig
   test "createRunner escapes special characters in labels" {
       const labels = &[_][]const u8{
           "normal-label",
           "label-with-\"quotes\"",
           "label-with-\\backslash",
           "label-with-\nnewline",
       };

       const result = try createRunner(allocator, labels);

       // Verify it's valid JSON
       const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.labels, .{});
       try testing.expect(parsed.array.items.len == 4);
       try testing.expectEqualStrings("label-with-\"quotes\"", parsed.array.items[1].string);
   }
   ```

7. **Add input validation:**
   - Consider rejecting labels with special characters at API level
   - Document allowed label format

## Acceptance Criteria

- [ ] All special characters properly escaped
- [ ] Valid JSON output for all inputs
- [ ] Tests cover edge cases (quotes, backslashes, unicode)
- [ ] No JSON injection possible
- [ ] Other JSON construction code audited
