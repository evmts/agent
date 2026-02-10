# Zig Rules (LLMs get these wrong)

Target: Zig 0.14. NOT 0.11, 0.12, 0.13, 0.15.

## Common Mistakes
- **ArrayList**: 0.14 prefers ArrayListUnmanaged (pass allocator to every method). std.ArrayList transitional.
- **JSON**: `std.json.parseFromSlice(T, allocator, input, .{})` returns `Parsed(T)` with `.value` + `.deinit()`. NEVER forget `defer parsed.deinit()`.
- **HashMap**: AutoHashMap for integer keys, StringHashMap for `[]const u8`. NEVER AutoHashMap with string keys.
- **Type introspection**: 0.14+ uses `.int`, `.@"struct"`, `.@"enum"` (lowercase + @ prefix for keywords). NOT `.Int`, `.Struct`, `.Enum`.
- `std.mem.page_size` → `std.heap.pageSize()` or `page_size_min`/`page_size_max`
- `std.rand` → `std.Random`
- `std.TailQueue` → `std.DoublyLinkedList`
- `std.ChildProcess` → `std.process.Child`
- `@setCold(true)` → `@branchHint(.cold)`

## Allocator Patterns
- Pass explicitly. NO global state.
- ArenaAllocator for batch allocations with shared lifetime (request-scoped, JSON parsing).
- `std.testing.allocator` in ALL tests (leak detection).
- `defer`/`errdefer` immediately after allocation.

## Error Handling
- Explicit error sets. NEVER `anyerror`.
- Handle all cases. NEVER `catch {}` or `catch |_| {}`.
- `errdefer` for cleanup on error paths.

## Comptime
- `comptime T: type` (NOT `anytype`) for generics.
- Use for dependency injection (vtable like `src/host.zig`).

## Style
- `const` over `var`; slices over raw pointers
- `std.log.scoped` for namespaced loggers
- Exhaustive switches

## Stdlib API Help
Zig stdlib changes frequently. Unsure → read source.
macOS Homebrew: `/opt/homebrew/lib/zig/std/`
Check: `std/json.zig`, `std/array_list.zig`, `std/hash_map.zig`, `std/io.zig`, `std/heap.zig`
