# Plan: libsmithers-zig-scaffold

## Summary

Replace placeholder `src/root.zig` + `src/main.zig` with proper libsmithers Zig scaffold following Ghostty patterns. This is the foundation all Zig modules build on.

**Layer:** Zig only (no Swift, no web)
**Estimated steps:** 10 atomic steps
**TDD approach:** Write tests inline with each module (Zig convention)

---

## Pre-Implementation Checklist

- [x] Research complete — Zig 0.15.2 API verified, Ghostty patterns documented
- [x] `zig build all` currently green (confirmed)
- [x] No `include/` or `pkg/` directories exist yet (will create `include/` for C header stub)

---

## Step 0: Write plan document

**Files:** `docs/plans/libsmithers-zig-scaffold.md`
**Action:** This document.

---

## Step 1: Update build.zig.zon — rename package to 'smithers'

**Files:** `build.zig.zon`
**Action:** Change `.name = .agent` to `.name = .smithers`
**Why first:** Package identity must be correct before any module references change.
**Verify:** `zig build` still compiles (module name in build.zig still says "agent" — that's OK, .zon name and build.zig module name are independent).

---

## Step 2: Create src/action.zig — action tag enum and payload union

**Files:** `src/action.zig` (CREATE)
**Action:** Define `ActionTag` enum (C-compatible via `c_int` backing) and `ActionPayload` extern union. Actions: `chat_send`, `workspace_open`, `workspace_close`, `agent_spawn`, `agent_cancel`, `file_save`, `file_open`, `search`, `jj_commit`, `jj_undo`, `settings_change`, `suggestion_refresh`.
**Pattern:** Ghostty `src/apprt/action.zig` — tagged union with C ABI compatibility.
**Tests:** Verify enum-to-int conversion, payload size/alignment, exhaustive switch.
**Why early:** No deps on other new modules. config.zig and App.zig will reference actions.

---

## Step 3: Create src/memory.zig — arena helpers and lifetime utilities

**Files:** `src/memory.zig` (CREATE)
**Action:** Arena creation helpers, owned-return pattern (copy to caller allocator), scoped arena utility. Uses `std.heap.ArenaAllocator` with Zig 0.15.2 API (`.init()` returns value, `.deinit()` takes value).
**Pattern:** Ghostty memory patterns — arena-per-lifetime, explicit allocator passing.
**Tests:** Arena create/destroy, owned duplication, leak detection via `std.testing.allocator`.
**Why early:** App.zig and host.zig will use memory utilities.

---

## Step 4: Create src/config.zig — runtime config with callback function pointers

**Files:** `src/config.zig` (CREATE)
**Action:** Define `RuntimeConfig` extern struct with callback function pointers: `wakeup_cb` (`fn(?*anyopaque) callconv(.c) void`), `action_cb` (`fn(?*anyopaque, ActionTag, ?*const anyopaque, usize) callconv(.c) void`), `userdata` (`?*anyopaque`). Also `AppConfig` for static configuration. Re-export action types.
**Pattern:** Ghostty `Options` extern struct in `src/apprt/embedded.zig`.
**Tests:** Config initialization, default values, callback type verification.
**Depends on:** `action.zig` (uses `ActionTag`).

---

## Step 5: Create src/host.zig — platform abstraction comptime vtable

**Files:** `src/host.zig` (CREATE)
**Action:** Define `Host` interface using comptime generic pattern. `Host` provides platform-specific operations (filesystem, time, logging) via comptime vtable — dependency injection so libsmithers stays platform-agnostic. Default `NullHost` for testing. Pattern: `pub fn Interface(comptime T: type) type { return struct { ... }; }`.
**Pattern:** Ghostty `src/apprt.zig` comptime platform switching + generic interface pattern.
**Tests:** NullHost satisfies interface, comptime validation of vtable completeness.
**Depends on:** `memory.zig` (allocator patterns).

---

## Step 6: Create src/App.zig — struct-as-file with full lifecycle

**Files:** `src/App.zig` (CREATE)
**Action:** Primary application struct. Fields: `alloc` (Allocator), `config` (AppConfig), `runtime_config` (RuntimeConfig). Lifecycle: `create(alloc, config)` allocates on heap with errdefer, `init(self, alloc, config)` uses `self.* = .{}`, `deinit(self)` cleans up + self-poisons (`self.* = undefined`), `destroy(self)` calls deinit then frees. `performAction(tag, payload)` dispatches via runtime callback.
**Pattern:** Ghostty `src/App.zig` exactly — struct-as-file, `@This()`, lifecycle, self-poisoning.
**Tests:** Create/destroy round-trip with `std.testing.allocator` (leak detection), action dispatch with mock callback, verify self-poisoning.
**Depends on:** `config.zig`, `action.zig`, `memory.zig`.

---

## Step 7: Create src/lib.zig — library root with CAPI exports

**Files:** `src/lib.zig` (CREATE)
**Action:** Library root. CAPI block with `comptime { _ = CAPI; }` force-export. Exports: `smithers_app_new(config) -> ?*App`, `smithers_app_free(app)`, `smithers_app_action(app, tag, payload_ptr, payload_len)`. Re-exports all public modules. Test discovery block `test { @import("std").testing.refAllDecls(@This()); }`.
**Pattern:** Ghostty `src/main_c.zig` — CAPI struct with export fn, comptime force-export block.
**Tests:** CAPI function existence (comptime), re-export verification, test discovery runs all module tests.
**Depends on:** `App.zig`, `config.zig`, `action.zig`.

---

## Step 8: Rewrite src/main.zig — CLI entry point (smithers-ctl stub)

**Files:** `src/main.zig` (REWRITE)
**Action:** Minimal CLI entry. Imports smithers module. Prints version/usage. Parses basic args (--help, --version). Stub for future smithers-ctl commands. Uses `std.io.getStdOut().writer()` for output.
**Pattern:** Ghostty `src/main.zig` — minimal CLI that delegates to library.
**Tests:** Basic arg parsing, help output.
**Depends on:** `lib.zig` exists as smithers module root.

---

## Step 9: Update build.zig — rename module, add library target

**Files:** `build.zig` (MODIFY)
**Action:**
1. Rename module from `"agent"` to `"smithers"`, root from `src/root.zig` to `src/lib.zig`
2. Add static library target `"smithers"` using same module root (`src/lib.zig`), link libc
3. Rename executable from `"agent"` to `"smithers-ctl"`, import module as `"smithers"`
4. Update test targets to use new module/exe
5. Keep all existing optional steps (web, playwright, dev, etc.)
6. Install library artifact alongside executable
**Pattern:** Ghostty build — shared module between library and executable targets.
**Verify:** `zig build` produces both `libsmithers.a` and `smithers-ctl`.

---

## Step 10: Delete src/root.zig + create include/libsmithers.h stub

**Files:** `src/root.zig` (DELETE), `include/libsmithers.h` (CREATE)
**Action:** Remove placeholder root.zig. Create C header stub with opaque types, action enum, callback typedefs, and function declarations matching the CAPI exports in lib.zig. Header follows Ghostty conventions: `smithers_` prefix, `_e` (enum), `_s` (struct), `_t` (opaque), `_cb` (callback).
**Pattern:** Ghostty `include/ghostty.h` conventions.
**Verify:** `zig build all` passes — zero errors, zero warnings, all tests green.

---

## Final Verification

After all steps:
1. `zig build` — produces `libsmithers.a` + `smithers-ctl` binary
2. `zig build test` — all module tests pass with leak detection
3. `zig build all` — full green (build + test + fmt + lint)
4. `zig build run` — smithers-ctl prints usage/version
5. No `src/root.zig` exists
6. `include/libsmithers.h` exists with matching C declarations

---

## Files Summary

### Create (7 files)
- `src/lib.zig` — library root, CAPI exports, re-exports, test discovery
- `src/App.zig` — struct-as-file, App lifecycle, action dispatch
- `src/config.zig` — RuntimeConfig callbacks, AppConfig
- `src/host.zig` — comptime vtable platform abstraction
- `src/memory.zig` — arena helpers, owned-return
- `src/action.zig` — ActionTag enum, ActionPayload union
- `include/libsmithers.h` — C API header stub

### Modify (3 files)
- `src/main.zig` — rewrite as smithers-ctl CLI stub
- `build.zig` — rename module, add library target, rename executable
- `build.zig.zon` — rename package to smithers

### Delete (1 file)
- `src/root.zig` — replaced by src/lib.zig

---

## Risks

1. **Zig 0.15.2 API surface** — ArenaAllocator, addLibrary, export fn semantics may have subtle differences from docs. Mitigated by verified stdlib source readings in research context.
2. **Static library + executable sharing module** — Must confirm both targets can share the same `addModule` without build graph conflicts. Ghostty does this successfully.
3. **C header manually synced** — `include/libsmithers.h` must match CAPI exports exactly. For scaffold this is trivial (3 functions); at scale needs generation or careful review.
4. **Self-poisoning in tests** — `self.* = undefined` after deinit means subsequent access is UB. Tests must not touch App after destroy. Testing allocator catches leaks but not UB.
5. **`export fn` forces C ABI** — Zig types in export signatures must be C-compatible (no slices, no error unions). Payload uses `?*const anyopaque` + length.
