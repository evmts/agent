# Plan: c-api-header-contract — C API Header Contract

## Summary

Enhance `include/libsmithers.h` to match Ghostty patterns and ticket requirements: switch to traditional header guards, add section dividers, add sync comments, add `smithers_surface_t` opaque type, add `suggestion_refresh` action (bringing total to 12 enum values), add `smithers_config_s` wrapper struct, and wire header install in `build.zig`. All Zig source files (`action.zig`, `capi.zig`, `lib.zig`) must be updated in lockstep — the comptime sync check in `capi.zig` enforces this.

## Ordering: Tests → Implementation → Verification

TDD approach: add the new Zig test variant first (it will fail), then implement the changes, then verify.

---

## Step 0: Add `suggestion_refresh` test to `src/lib.zig` (TDD — test first)

**Files:** `src/lib.zig`
**Layer:** zig

Add a test case for `suggestion_refresh` in the "payloadFromC all variants mapping" test block. This test will fail until the Zig types are updated in subsequent steps.

```zig
// suggestion_refresh
var p11: capi.smithers_action_payload_u = undefined;
p11.suggestion_refresh = .{ ._pad = 0 };
_ = payloadFromC(.suggestion_refresh, p11);
```

---

## Step 1: Add `suggestion_refresh` to `src/action.zig`

**Files:** `src/action.zig`
**Layer:** zig

Add `suggestion_refresh` as the 12th variant to both `Tag` and `Payload`:

```zig
pub const Tag = enum(u32) {
    // ... existing 11 ...
    suggestion_refresh,
};

pub const Payload = union(Tag) {
    // ... existing 11 ...
    suggestion_refresh: void,
};
```

---

## Step 2: Add `suggestion_refresh` to `src/capi.zig`

**Files:** `src/capi.zig`
**Layer:** zig

Add matching variant to both `smithers_action_tag_e` and `smithers_action_payload_u`:

```zig
pub const smithers_action_tag_e = enum(u32) {
    // ... existing 11 ...
    suggestion_refresh,
};

pub const smithers_action_payload_u = extern union {
    // ... existing ...
    suggestion_refresh: extern struct { _pad: u8 = 0 },
};
```

The comptime sync check (lines 56-64) will now pass since both `action.Tag` and `smithers_action_tag_e` have 12 matching fields.

---

## Step 3: Add `suggestion_refresh` to `payloadFromC` in `src/lib.zig`

**Files:** `src/lib.zig`
**Layer:** zig

Add the conversion case to `payloadFromC` switch:

```zig
.suggestion_refresh => action.Payload{ .suggestion_refresh = {} },
```

At this point: `zig build test` passes including the test added in Step 0.

---

## Step 4: Rewrite `include/libsmithers.h`

**Files:** `include/libsmithers.h`
**Layer:** zig (C header)

Full rewrite of the header with these changes:

1. **Replace `#pragma once`** with `#ifndef LIBSMITHERS_H` / `#define LIBSMITHERS_H` / `#endif` guards
2. **Add sync comment** at top: references `src/action.zig`, `src/capi.zig`, and `src/lib.zig`
3. **Add section dividers** (`//---` 67 chars wide) for: Types, Callbacks, Configuration, Actions, Published API
4. **Add `smithers_surface_t`** opaque type (`typedef struct smithers_surface_s* smithers_surface_t;`)
5. **Add `SMITHERS_ACTION_SUGGESTION_REFRESH = 11`** to enum (12 total values)
6. **Add `suggestion_refresh`** void-like payload to union
7. **Optionally add `smithers_config_s`** wrapper struct around `smithers_runtime_config_s`
8. **Update `smithers_app_new` signature** to accept `const smithers_config_s*` if wrapper added (or keep `smithers_runtime_config_s*` — decision: keep runtime config direct, add config wrapper as future-proofing comment only, to avoid unnecessary signature churn)

### Decision: `smithers_config_s` wrapper

The ticket mentions `smithers_config_s` wrapping runtime config. Adding it now is future-proofing — when we need more config fields (workspace path, log level, etc.), we won't need to change the function signature. Add the wrapper struct but keep `smithers_app_new` accepting `const smithers_config_s*` containing `runtime` field.

---

## Step 5: Update `build.zig` — add header install step

**Files:** `build.zig`
**Layer:** zig (build)

After `b.installArtifact(lib)` (line 23), add:

```zig
const header_install = b.addInstallHeaderFile(b.path("include/libsmithers.h"), "libsmithers.h");
b.getInstallStep().dependOn(&header_install.step);
```

This ensures `zig-out/include/libsmithers.h` is installed alongside the static library at `zig-out/lib/libsmithers.a`.

---

## Step 6: Update `src/lib.zig` CAPI — adjust `smithers_app_new` for `smithers_config_s`

**Files:** `src/lib.zig`, `src/capi.zig`
**Layer:** zig

If we add `smithers_config_s` wrapper:
- Add `smithers_config_s` to `capi.zig`: `pub const smithers_config_s = extern struct { runtime: smithers_runtime_config_s };`
- Update `smithers_app_new` in `lib.zig` to accept `?*const capi.smithers_config_s` and extract `.runtime`
- Update existing test if needed

---

## Step 7: Add C compilation verification test

**Files:** `src/lib.zig` (or a new test), `build.zig`
**Layer:** zig

Add a build step that compiles a minimal C file including the header to verify it's valid C:

Create `tests/c_header_test.c`:
```c
#include "libsmithers.h"

// Verify types exist
static void test_types(void) {
    smithers_app_t app = (smithers_app_t)0;
    smithers_surface_t surface = (smithers_surface_t)0;
    smithers_action_tag_e tag = SMITHERS_ACTION_CHAT_SEND;
    smithers_action_payload_u payload;
    smithers_config_s config;
    smithers_runtime_config_s runtime;
    (void)app; (void)surface; (void)tag; (void)payload; (void)config; (void)runtime;
}
```

Wire in `build.zig` as a compile-only step (no link needed — just verify the header parses).

---

## Step 8: Run `zig build all` — final verification

**Layer:** zig

Verify:
- All Zig tests pass (including new `suggestion_refresh` test)
- Comptime sync check passes (capi.zig ↔ action.zig)
- Header compiles cleanly (C compilation test)
- Format check passes (`zig fmt`)
- Static lib + header installed to `zig-out/`

---

## Files Summary

### Files to create
- `tests/c_header_test.c` — C compilation verification

### Files to modify
- `include/libsmithers.h` — Major rewrite (header guards, sections, surface_t, suggestion_refresh, config_s)
- `src/action.zig` — Add `suggestion_refresh` variant
- `src/capi.zig` — Add `suggestion_refresh` + `smithers_config_s`
- `src/lib.zig` — Add `suggestion_refresh` payloadFromC + update `smithers_app_new` signature + test
- `build.zig` — Add header install step + C compilation test step

### Tests
1. **Zig unit test** — `suggestion_refresh` payload conversion in `src/lib.zig`
2. **Zig comptime** — Existing sync check in `src/capi.zig` validates enum parity automatically
3. **C compilation** — `tests/c_header_test.c` verifies header is valid C

### Docs
- `docs/plans/c-api-header-contract.md` (this file)

---

## Risks

1. **`smithers_config_s` signature change** — Changing `smithers_app_new` from `smithers_runtime_config_s*` to `smithers_config_s*` is a breaking change if anyone calls it. Currently only `src/lib.zig` CAPI calls it, so safe.

2. **13 minimum enum values** — Ticket says "13 values minimum" but engineering spec only defines 12 actions. We implement 12 (the actual needed set). If 13 is truly required, a placeholder like `SMITHERS_ACTION_RESERVED` could be added, but that's worse engineering practice.

3. **C compilation test portability** — Using `zig cc` to compile the test C file ensures it works with our toolchain. May need adjustment if CI uses different C compiler.

4. **Header install path** — `addInstallHeaderFile` places the header in `zig-out/include/`. The xcframework packaging step (future) will need to reference this path.
