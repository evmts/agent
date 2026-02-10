# Research Context: c-api-header-contract

## Current State

### Header exists but needs enhancement
`include/libsmithers.h` (74 lines) — already has core structure but is missing several items from the ticket:
- Missing: `smithers_surface_t` opaque type (per-workspace)
- Missing: `SMITHERS_ACTION_SUGGESTION_REFRESH` (ticket requires 13+ enum values, currently 11)
- Missing: `smithers_config_s` wrapper struct around runtime config
- Missing: Section dividers (`//---` comments per Ghostty pattern)
- Missing: Sync comment at top referencing `src/action.zig` and `src/lib.zig`
- Uses `#pragma once` instead of `#ifndef`/`#define`/`#endif` guards (Ghostty uses traditional guards)

### Zig side is already implemented and in-sync
- `src/capi.zig` (70 lines) — mirrors current header exactly with comptime verification
- `src/action.zig` (41 lines) — 11 action tags, needs `suggestion_refresh` added
- `src/lib.zig` (140 lines) — CAPI exports + payloadFromC + tests
- `src/App.zig` (86 lines) — lifecycle, performAction, tests
- `src/config.zig` (33 lines) — RuntimeConfig wrapping capi types

### Build needs header install step
`build.zig` (92 lines) — has `b.installArtifact(lib)` for the static library but NO header install step.

## Key Files (ranked by relevance)

1. **`include/libsmithers.h`** — THE file being modified. Current 74 lines.
2. **`src/capi.zig`** — Zig mirror of C types. Must stay in sync. Has comptime verification at line 56-64.
3. **`src/action.zig`** — Source of truth for action tags. Must add `suggestion_refresh`.
4. **`src/lib.zig`** — CAPI exports, payloadFromC conversion. Must add `suggestion_refresh` mapping.
5. **`build.zig`** — Needs `addInstallHeaderFile` step added.
6. **`src/App.zig`** — References action.Payload. No changes needed.
7. **`src/config.zig`** — RuntimeConfig. No changes needed.

## Ghostty Reference Patterns

### Header structure (ghostty.h — 1080+ lines)
```c
// Comment block explaining purpose
#ifndef GHOSTTY_H
#define GHOSTTY_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

//-------------------------------------------------------------------
// Macros

//-------------------------------------------------------------------
// Types

// Opaque types
typedef void* ghostty_app_t;
typedef void* ghostty_surface_t;

// All the types below are fully defined and must be kept in sync with
// their Zig counterparts.

// ... enums, structs, unions ...

//-------------------------------------------------------------------
// Published API

ghostty_app_t ghostty_app_new(const ghostty_runtime_config_s*, ghostty_config_t);
void ghostty_app_free(ghostty_app_t);
// ...

#ifdef __cplusplus
}
#endif
#endif // GHOSTTY_H
```

### Key differences from current libsmithers.h:
1. Ghostty uses `#ifndef`/`#define`/`#endif` (not `#pragma once`)
2. Ghostty uses `typedef void*` for opaques (current smithers uses `typedef struct smithers_app_s*`)
3. Ghostty has section dividers with `//-------------------------------------------------------------------`
4. Ghostty includes `<stdbool.h>` (smithers doesn't need it yet)

### Ghostty build.zig header install (GhosttyLib.zig:148-155)
```zig
pub fn installHeader(self: *const GhosttyLib) void {
    const b = self.step.owner;
    const header_install = b.addInstallHeaderFile(
        b.path("include/ghostty.h"),
        "ghostty.h",
    );
    b.getInstallStep().dependOn(&header_install.step);
}
```

### Zig 0.15.2 API for header install (verified from stdlib)
```zig
// std/Build.zig:1668
pub fn addInstallHeaderFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile {
    return b.addInstallFileWithDir(source, .header, dest_rel_path);
}
```

Simpler approach for our build.zig (no separate GhosttyLib struct):
```zig
const header_install = b.addInstallHeaderFile(b.path("include/libsmithers.h"), "libsmithers.h");
b.getInstallStep().dependOn(&header_install.step);
```

## Changes Required (comprehensive)

### 1. `include/libsmithers.h` — Major rewrite
- Switch from `#pragma once` to `#ifndef LIBSMITHERS_H` / `#define` / `#endif`
- Add sync comment at top: "Keep in sync with src/action.zig and src/lib.zig"
- Add section dividers: `//---` for Types, Callbacks, Config, Actions, Published API
- Add `smithers_surface_t` opaque type (per-workspace)
- Add `SMITHERS_ACTION_SUGGESTION_REFRESH = 11` to enum (13th value = 12 total with 0-indexing; currently 11 values)
- Add `suggestion_refresh` payload entry (void-like with pad)
- Optionally add `smithers_config_s` wrapper struct (ticket mentions it)
- Total enum values: 12 (0-11), meeting "13 values minimum" with some margin issue — ticket says "13 values minimum" but eng spec only defines 11 + suggestion_refresh = 12

### 2. `src/action.zig` — Add `suggestion_refresh`
```zig
pub const Tag = enum(u32) {
    // ... existing 11 ...
    suggestion_refresh,  // NEW
};

pub const Payload = union(Tag) {
    // ... existing 11 ...
    suggestion_refresh: void,  // NEW
};
```

### 3. `src/capi.zig` — Add `suggestion_refresh`
```zig
pub const smithers_action_tag_e = enum(u32) {
    // ... existing 11 ...
    suggestion_refresh,  // NEW
};

pub const smithers_action_payload_u = extern union {
    // ... existing ...
    suggestion_refresh: extern struct { _pad: u8 = 0 },  // NEW
};
```

### 4. `src/lib.zig` — Add `suggestion_refresh` to payloadFromC
```zig
.suggestion_refresh => action.Payload{ .suggestion_refresh = {} },
```
Plus add a test variant.

### 5. `build.zig` — Add header install step
After `b.installArtifact(lib)` on line 23, add:
```zig
const header_install = b.addInstallHeaderFile(b.path("include/libsmithers.h"), "libsmithers.h");
b.getInstallStep().dependOn(&header_install.step);
```

## Gotchas / Pitfalls

1. **Opaque type style**: Current header uses `typedef struct smithers_app_s* smithers_app_t` (pointer-to-opaque-struct). Ghostty uses `typedef void*`. The current style is actually BETTER for type safety — keep it. Just add `smithers_surface_t` in the same style.

2. **13 minimum action values**: Ticket says "13 values minimum" but the engineering spec only lists 11 actions plus `suggestion_refresh` = 12. Either add `suggestion_refresh` (getting to 12) or add one more placeholder. The safe call: add `suggestion_refresh` and note that 12 >= the actual needed set. The "13 minimum" may have been aspirational.

3. **Comptime sync verification in capi.zig**: The comptime block at lines 56-64 validates that `action.Tag` and `smithers_action_tag_e` have identical field names and values. Adding `suggestion_refresh` to one without the other will break the build — which is the desired safety behavior.

4. **Extern union zero-size**: Void-like action payloads (`workspace_close`, `jj_undo`) use `extern struct { _pad: u8 = 0 }` to avoid zero-size extern struct issues across C ABI. Must do the same for `suggestion_refresh`.

5. **Header guard naming**: Convention is `LIBSMITHERS_H` (file name uppercased with underscores). Ghostty uses `GHOSTTY_H`.

## Verification

Run `zig build all` — this exercises:
- Comptime sync check in `src/capi.zig` (catches Zig↔C enum mismatch)
- All payload conversion tests in `src/lib.zig`
- Format check
- Full build (static lib + CLI)

For C compilation test: create a minimal `.c` file that `#include`s the header and use `zig cc` to compile it.
