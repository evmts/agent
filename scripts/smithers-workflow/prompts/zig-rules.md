# Zig Coding Rules (Critical — LLMs commonly get these wrong)

This project targets Zig 0.14. Do NOT use APIs from 0.11, 0.12, 0.13, or 0.15.

## Common Mistakes to Avoid
- **ArrayList**: In 0.14, prefer ArrayListUnmanaged (pass allocator to every method). std.ArrayList still works but is transitional.
- **JSON**: Use `std.json.parseFromSlice(T, allocator, input, .{})` — returns `Parsed(T)` with `.value` and `.deinit()`. Do NOT forget `defer parsed.deinit()`.
- **HashMap**: Use AutoHashMap for integer keys, StringHashMap for `[]const u8` keys. NEVER use AutoHashMap with string keys.
- **Type introspection**: In 0.14+, use `.int`, `.@"struct"`, `.@"enum"` (lowercase with @ prefix for keywords). NOT `.Int`, `.Struct`, `.Enum`.
- `std.mem.page_size` is now `std.heap.pageSize()` or `page_size_min`/`page_size_max`.
- `std.rand` is now `std.Random`.
- `std.TailQueue` is now `std.DoublyLinkedList`.
- `std.ChildProcess` is now `std.process.Child`.
- `@setCold(true)` is now `@branchHint(.cold)`.

## Allocator Patterns
- Pass allocators explicitly. Never use global state.
- Use ArenaAllocator for batch allocations with shared lifetime (request-scoped, JSON parsing).
- Use `std.testing.allocator` in ALL tests (detects leaks).
- Use `defer`/`errdefer` immediately after allocation.

## Error Handling
- Define explicit error sets. NEVER use `anyerror`.
- Handle all error cases. NEVER use `catch {}` or `catch |_| {}`.
- Use `errdefer` for cleanup on error paths.

## Comptime
- Prefer `comptime T: type` over `anytype` for generics.
- Use comptime for dependency injection (vtable pattern like in `src/host.zig`).

## Style
- Prefer `const` over `var`. Prefer slices over raw pointers.
- Use `std.log.scoped` for namespaced loggers.
- Handle all switch branches exhaustively.

## When Stuck on Stdlib APIs
The Zig standard library changes frequently. If you're unsure about an API, read the actual source files.
On macOS with Homebrew, the Zig stdlib is at: `/opt/homebrew/lib/zig/std/`
Read the actual `.zig` files there as the source of truth.
Common files to check: `std/json.zig`, `std/array_list.zig`, `std/hash_map.zig`, `std/io.zig`, `std/heap.zig`
