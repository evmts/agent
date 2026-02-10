# Research Context: libsmithers-zig-scaffold

## Current State

### Existing files to replace/modify:
- `src/root.zig` — placeholder library root (24 lines, `bufferedPrint` + `add` functions). DELETE and replace with `src/lib.zig`.
- `src/main.zig` — placeholder CLI (27 lines, "All your codebase" message). REWRITE as smithers-ctl stub.
- `build.zig` — 253 lines, module named `"agent"`, root = `src/root.zig`. MODIFY to rename + add library target.
- `build.zig.zon` — package named `.agent`. MODIFY to rename to `.smithers`.

### Directories that don't exist yet:
- `include/` — C API header
- `pkg/` — vendored deps

## Zig 0.15.2 API Signatures (Verified from stdlib source)

### ArenaAllocator (`/Users/williamcory/.zvm/0.15.2/lib/std/heap/arena_allocator.zig`)
```zig
// Init takes a child allocator, returns ArenaAllocator by value
pub fn init(child_allocator: Allocator) ArenaAllocator

// Get allocator interface - takes *ArenaAllocator (pointer)
pub fn allocator(self: *ArenaAllocator) Allocator

// Deinit takes ArenaAllocator by value (NOT pointer)
pub fn deinit(self: ArenaAllocator) void
```

**Correct usage pattern:**
```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const alloc = arena.allocator();
```

### std.log.scoped (`/Users/williamcory/.zvm/0.15.2/lib/std/log.zig:161`)
```zig
pub fn scoped(comptime scope: @Type(.enum_literal)) type
// Returns struct with err, warn, info, debug methods
```

**Usage:**
```zig
const log = std.log.scoped(.smithers);
log.info("started", .{});
```

### std.testing (`/Users/williamcory/.zvm/0.15.2/lib/std/testing.zig`)
```zig
pub const allocator = allocator_instance.allocator();
// Uses GeneralPurposeAllocator (which is DebugAllocator in 0.15.2)
pub inline fn expectEqual(expected: anytype, actual: anytype) !void
pub fn expect(ok: bool) !void
```

**Usage:**
```zig
const testing = std.testing;
const alloc = testing.allocator;
try testing.expectEqual(@as(u32, 42), result);
```

### Build API (`/Users/williamcory/.zvm/0.15.2/lib/std/Build.zig`)

**addLibrary (line 841):**
```zig
pub fn addLibrary(b: *Build, options: LibraryOptions) *Step.Compile

pub const LibraryOptions = struct {
    linkage: std.builtin.LinkMode = .static,  // default = static!
    name: []const u8,
    root_module: *Module,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    win32_manifest: ?LazyPath = null,
};
```

**addExecutable (line 798):**
```zig
pub fn addExecutable(b: *Build, options: ExecutableOptions) *Step.Compile

pub const ExecutableOptions = struct {
    name: []const u8,
    root_module: *Module,
    // ...
};
```

**addModule:**
```zig
pub fn addModule(b: *Build, name: []const u8, options: Module.CreateOptions) *Module
```

**createModule:**
```zig
pub fn createModule(b: *Build, options: Module.CreateOptions) *Module
```

### ArrayList (`/Users/williamcory/.zvm/0.15.2/lib/std/array_list.zig`)
In Zig 0.15, `std.ArrayList` is transitional. `ArrayListUnmanaged` is preferred (pass allocator to every method). But for the scaffold, usage is minimal.

### Calling Convention
```zig
// C calling convention for exported functions
fn name(args...) callconv(.c) ReturnType
```

`export fn` keyword automatically uses C calling convention AND exports the symbol.

## Ghostty Reference Patterns

### 1. CAPI Force-Export Pattern (`src/main_c.zig`)
```zig
comptime {
    _ = @import("config.zig").CApi;
    if (@hasDecl(apprt.runtime, "CAPI")) _ = apprt.runtime.CAPI;
    _ = @import("benchmark/main.zig").CApi;
}
```
The `_ =` forces compiler to evaluate the import, ensuring all `export fn` declarations are included in the binary.

### 2. Export Function Pattern (`src/config/CApi.zig`)
```zig
export fn ghostty_config_new() ?*Config {
    const result = state.alloc.create(Config) catch |err| {
        log.err("error allocating config err={}", .{err});
        return null;
    };
    result.* = Config.default(state.alloc) catch |err| {
        log.err("error creating config err={}", .{err});
        state.alloc.destroy(result);
        return null;
    };
    return result;
}
```

### 3. Struct-as-File with Lifecycle (`src/App.zig`)
```zig
const App = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;

alloc: Allocator,
surfaces: SurfaceList,

pub const CreateError = Allocator.Error || OtherError;

pub fn create(alloc: Allocator) CreateError!*App {
    var app = try alloc.create(App);
    errdefer alloc.destroy(app);
    try app.init(alloc);
    return app;
}

pub fn init(self: *App, alloc: Allocator) CreateError!void {
    self.* = .{
        .alloc = alloc,
        .surfaces = .{},
    };
}

pub fn deinit(self: *App) void {
    self.surfaces.deinit(self.alloc);
}

pub fn destroy(self: *App) void {
    self.deinit();
    self.alloc.destroy(self);
}
```

### 4. Self-Poisoning (`src/terminal/Terminal.zig`)
```zig
pub fn deinit(self: *Terminal, alloc: Allocator) void {
    self.tabstops.deinit(alloc);
    self.screens.deinit(alloc);
    self.* = undefined;  // Poison — use-after-free crashes
}
```

### 5. Runtime Config with Callbacks (`src/apprt/embedded.zig`)
```zig
pub const App = struct {
    pub const Options = extern struct {
        userdata: ?*anyopaque = null,
        wakeup: *const fn (?*anyopaque) callconv(.c) void,
        action: *const fn (*App, apprt.Target.C, apprt.Action.C) callconv(.c) bool,
        read_clipboard: *const fn (?*anyopaque, c_int, *apprt.ClipboardRequest) callconv(.c) void,
        // ...
    };
};
```

### 6. Action Tagged Union with C ABI (`src/apprt/action.zig`)
```zig
pub const Action = union(Key) {
    quit,
    new_window,
    new_tab,
    close_tab: CloseTabMode,
    // ...

    pub const Key = enum(c_int) {
        quit,
        new_window,
        new_tab,
        close_tab,
        // ...
    };

    // Comptime-generated C-compatible union
    pub const C = extern struct {
        key: Key,
        value: CValue,
    };
};
```

### 7. Comptime Platform Abstraction (`src/apprt.zig`)
```zig
pub const runtime = switch (build_config.artifact) {
    .exe => switch (build_config.app_runtime) {
        .none => none,
        .gtk => gtk,
    },
    .lib => embedded,
    .wasm_module => browser,
};
pub const App = runtime.App;
pub const Surface = runtime.Surface;
```

### 8. Build: Library + Executable (`src/build/GhosttyLib.zig` + `GhosttyExe.zig`)
```zig
// Library
const lib = b.addLibrary(.{
    .name = "ghostty",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main_c.zig"),
        .target = deps.config.target,
        .optimize = deps.config.optimize,
    }),
    .use_llvm = true,
});
lib.linkLibC();

// Executable
const exe = b.addExecutable(.{
    .name = "ghostty",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    }),
});
```

## Key Gotchas

### 1. ArenaAllocator.deinit takes value, not pointer
```zig
// WRONG: arena.deinit(&arena)
// RIGHT:
var arena = std.heap.ArenaAllocator.init(page_allocator);
defer arena.deinit();  // takes by value
```

### 2. `export fn` vs `pub fn` with `callconv(.c)`
- `export fn` = exports symbol AND uses C calling convention. Preferred for C API.
- `pub fn ... callconv(.c)` = C calling convention but NOT exported. Use for callback types.
- For the CAPI block in lib.zig, use `export fn`.

### 3. Struct initialization with `.{}`
In Zig 0.15, the idiomatic init pattern is:
```zig
self.* = .{
    .field1 = value1,
    .field2 = value2,
};
```
NOT individual field assignments.

### 4. Type introspection syntax changed in 0.14+
```zig
// OLD: .Struct, .Enum, .Int
// NEW: .@"struct", .@"enum", .int
```

### 5. Module naming — `addModule` exposes to consumers, `createModule` is private
- `addModule("smithers", ...)` — the module name consumers import with `@import("smithers")`
- `createModule(...)` — internal module not exposed to consumers (used for exe root)
- The library and executable should share the same module for the core code

## Build Strategy

Current build.zig builds:
1. Module `"agent"` from `src/root.zig`
2. Executable `"agent"` from `src/main.zig` importing the module

Needed:
1. Module `"smithers"` from `src/lib.zig`
2. Static library `"smithers"` from `src/lib.zig` (same root, C API exports)
3. Executable `"smithers-ctl"` from `src/main.zig` importing smithers module

**Key insight:** The module and library can share the same root file (`src/lib.zig`). The library target builds `src/lib.zig` as a static lib with C exports. The executable target builds `src/main.zig` which imports the smithers module.

## File Plan

| File | Type | Purpose |
|------|------|---------|
| `src/lib.zig` | Namespace | Library root, CAPI exports block, re-exports |
| `src/main.zig` | CLI entry | smithers-ctl stub |
| `src/App.zig` | Struct-as-file | App type (opaque to C), lifecycle |
| `src/config.zig` | Namespace | RuntimeConfig with callbacks |
| `src/host.zig` | Namespace | Platform abstraction comptime vtable |
| `src/action.zig` | Namespace | ActionTag enum, ActionPayload union |
| `src/memory.zig` | Namespace | Arena helpers |
| `src/root.zig` | DELETE | Replaced by lib.zig |

## Reference Files

- Ghostty CAPI: `/Users/williamcory/smithers/ghostty/src/main_c.zig`
- Ghostty App: `/Users/williamcory/smithers/ghostty/src/App.zig`
- Ghostty embedded runtime: `/Users/williamcory/smithers/ghostty/src/apprt/embedded.zig`
- Ghostty actions: `/Users/williamcory/smithers/ghostty/src/apprt/action.zig`
- Ghostty apprt namespace: `/Users/williamcory/smithers/ghostty/src/apprt.zig`
- Ghostty lib build: `/Users/williamcory/smithers/ghostty/src/build/GhosttyLib.zig`
- Ghostty Terminal (self-poisoning): `/Users/williamcory/smithers/ghostty/src/terminal/Terminal.zig`
- Ghostty config CApi: `/Users/williamcory/smithers/ghostty/src/config/CApi.zig`
- Current build.zig: `/Users/williamcory/agent/build.zig`
- Zig 0.15.2 stdlib: `/Users/williamcory/.zvm/0.15.2/lib/std/`
