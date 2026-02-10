# Ghostty Reference — Follow These Patterns

Smithers mirrors Ghostty repo/code style. When unsure, read Ghostty source at `../smithers/ghostty/`.

## Zig File Naming
- **PascalCase.zig** = struct-as-file (file IS struct): `App.zig`, `Surface.zig`, `Terminal.zig`
- **snake_case.zig** = namespace/module: `config.zig`, `apprt.zig`, `renderer.zig`
- Subsystem = directory + namespace: `terminal/` + `terminal.zig` (or `terminal/main.zig`)

## Struct-as-File Pattern

```zig
//! Module-level doc — explain purpose.
const MyType = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.my_module);

/// Field doc
alloc: Allocator,
surfaces: SurfaceList,
focused: bool = true,

pub const CreateError = Allocator.Error || OtherError;

pub fn create(alloc: Allocator) CreateError!*MyType {
    var self = try alloc.create(MyType);
    errdefer alloc.destroy(self);
    try self.init(alloc);
    return self;
}

pub fn init(self: *MyType, alloc: Allocator) CreateError!void {
    self.* = .{ .alloc = alloc, .surfaces = .{}, .focused = true };
}

pub fn deinit(self: *MyType) void {
    self.surfaces.deinit(self.alloc);
    self.* = undefined; // Poison
}

pub fn destroy(self: *MyType) void {
    const alloc = self.alloc;
    self.deinit();
    alloc.destroy(self);
}
```

## Namespace/Module Pattern

```zig
// Private imports (no pub)
const charsets = @import("charsets.zig");
// Public re-exports
pub const apc = @import("apc.zig");
pub const Terminal = @import("Terminal.zig");
// Test discovery
test { @import("std").testing.refAllDecls(@This()); }
```

## Import Order (strict)
1. std library: `const std = @import("std");`
2. std aliases: `const Allocator = std.mem.Allocator;`
3. Internal: `const configpkg = @import("config.zig");`
4. External: `const oni = @import("oniguruma");`
5. Logger: `const log = std.log.scoped(.module_name);`
6. Type aliases

## Module Naming
Shadow avoidance — suffix `pkg`:
```zig
const configpkg = @import("config.zig");
const Config = configpkg.Config;
```

## Lifecycle Pattern
- `create(alloc)` — alloc on heap, call init, return pointer. Use errdefer.
- `init(self, alloc)` — initialize struct. `self.* = .{ ... }`.
- `deinit(self)` — free resources. NOT self. Poison: `self.* = undefined`.
- `destroy(self)` — save allocator, call deinit(), free self.

## Error Pattern
- Per-operation: `pub const OpenError = error{OpenFailed};`
- Union: `pub const Error = OpenError || GetModeError || SetSizeError;`
- errdefer immediately after failable allocation
- Log: `catch |err| { log.warn("failed err={}", .{err}); ... }`

## Generic Type Pattern
```zig
pub fn BlockingQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        // ...
    };
}
```

## Platform Abstraction (comptime)
```zig
pub const Pty = switch (builtin.os.tag) {
    .windows => WindowsPty,
    .ios => NullPty,
    else => PosixPty,
};
```

## Labeled Blocks
```zig
self.gpa = gpa: {
    if (condition) break :gpa null;
    break :gpa GPA{};
};
```

## Naming
- Types/Structs: PascalCase (`App`, `Surface`, `GlobalState`)
- Functions: camelCase (`init`, `deinit`, `updateConfig`, `drainMailbox`)
- Variables/fields/constants/enum fields/log scopes: snake_case (`font_grid_set`, `min_window_width_cells`, `.debug`, `.app`)

## Comment Style
- `//!` — module-level doc at file top. WHY module exists, conceptual context.
- `///` — field/function doc. Behavioral contracts, not just types.
- `//` — inline notes. Consequences of alternatives.
- Minimal. Code self-documents. Explain WHY, not WHAT. Delete if restates code.
- First person, conversational. Honest about limits: "hack because...", "can't do X because..."

### Field Documentation as Contracts
Behavioral implications, not just type:
```zig
/// Font faces for rendering — lookup for codepoints, fallback, etc.
/// Replaced at runtime on config change.
font_grid_set: ?*font.SharedGridSet = null,

/// Non-null = surface closed by host, ignore further interactions.
closed: ?*Surface = null,
```

### Self-Poisoning After Deinit
`self.* = undefined` at end of `deinit()` — use-after-free crashes instead of silent corruption:
```zig
pub fn deinit(self: *MyType) void {
    self.resource.deinit();
    self.alloc.free(self.buffer);
    self.* = undefined; // Poison
}
```

## Test Pattern
```zig
test "CircBuf append" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var buf = try CircBuf(u8, 0).init(alloc, 3);
    defer buf.deinit(alloc);
    try buf.append(1);
    try testing.expectEqual(@as(u8, 1), buf.get(0));
}
```

- `std.testing.allocator` (leak detection)
- `defer` cleanup
- Progressive complexity (simple → edge cases)
- Descriptive names: `"CircBuf append wraps around"`

## C API Header (`include/smithers.h`)
- Prefix: `smithers_`
- Types: `_e` (enum), `_s` (struct), `_t` (opaque), `_cb` (callback)
- Enum values: `SMITHERS_SCREAMING_SNAKE_CASE`
- Functions: `smithers_snake_case`
- Sections: `//-------------------------------------------------------------------`

## Swift Organization
- Feature-based: `macos/Sources/Features/{Chat,IDE,Terminal,Editor,...}`
- Namespace: `Smithers.Action.swift`, `Smithers.App.swift` (enum as namespace)
- Extensions: `TypeName+Extension.swift`
- MARK: `// MARK: App Operations`
- Guard-let: `guard let app = self.app else { return }`

## build.zig
- Root thin — delegates to `src/build/main.zig`
- Each artifact/step = `PascalCase.zig` in `src/build/`
- `pkg/` deps have own `build.zig` wrapper
