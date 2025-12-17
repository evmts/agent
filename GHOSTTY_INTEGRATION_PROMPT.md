# Ghostty Terminal Integration Task

<task_overview>
Replace the current SwiftTerm-based terminal implementation in the AgentApp with libghostty (Ghostty's embeddable terminal library). This is a multi-phase project requiring careful coordination.
</task_overview>

<context>
## Current State

The AgentApp is a SwiftUI macOS application located at `/Users/williamcory/agent/AgentApp/`. It currently uses:
- **SwiftTerm** for terminal emulation (via `SwiftTermView.swift`)
- **Stub FFI functions** in `Terminal.swift` that return failure (Zig backend not connected)
- A mock terminal implementation that doesn't actually work

## Target State

Replace SwiftTerm with **libghostty** - Ghostty's high-performance terminal library that provides:
- GPU-accelerated rendering via Metal
- Full VT100/VT220 terminal emulation
- Native macOS integration
- Better performance than SwiftTerm
</context>

<reference_materials>
## Ghostty Repository

The ghostty source has been cloned to `/tmp/libghostty/`. Key locations:

```
/tmp/libghostty/
├── include/ghostty.h          # C API header (1100+ lines)
├── macos/
│   ├── Sources/
│   │   ├── Ghostty/           # Swift wrappers for C API
│   │   │   ├── Package.swift
│   │   │   ├── Ghostty.App.swift
│   │   │   ├── Ghostty.Config.swift
│   │   │   ├── Ghostty.Surface.swift
│   │   │   ├── Ghostty.Input.swift
│   │   │   ├── SurfaceView.swift
│   │   │   └── SurfaceView_AppKit.swift
│   │   ├── Helpers/           # Utility extensions
│   │   └── Features/Terminal/ # Terminal window features
│   └── Ghostty.xcodeproj
├── src/                       # Zig source code
└── build.zig                  # Zig build system
```

## Key API Functions (from ghostty.h)

```c
// Initialization
int ghostty_init(uintptr_t, char**);
ghostty_info_s ghostty_info(void);

// Configuration
ghostty_config_t ghostty_config_new();
void ghostty_config_free(ghostty_config_t);
void ghostty_config_finalize(ghostty_config_t);

// App lifecycle
ghostty_app_t ghostty_app_new(const ghostty_runtime_config_s*, ghostty_config_t);
void ghostty_app_free(ghostty_app_t);
void ghostty_app_tick(ghostty_app_t);

// Surface (terminal view)
ghostty_surface_t ghostty_surface_new(ghostty_app_t, const ghostty_surface_config_s*);
void ghostty_surface_free(ghostty_surface_t);
void ghostty_surface_draw(ghostty_surface_t);
void ghostty_surface_set_size(ghostty_surface_t, uint32_t, uint32_t);
bool ghostty_surface_key(ghostty_surface_t, ghostty_input_key_s);
void ghostty_surface_text(ghostty_surface_t, const char*, uintptr_t);
```

## Surface Configuration (for embedding)

```c
typedef struct {
  ghostty_platform_e platform_tag;    // GHOSTTY_PLATFORM_MACOS
  ghostty_platform_u platform;         // Contains nsview pointer
  void* userdata;
  double scale_factor;
  float font_size;
  const char* working_directory;
  const char* command;                 // Shell to run
  ghostty_env_var_s* env_vars;
  size_t env_var_count;
  const char* initial_input;
  bool wait_after_command;
} ghostty_surface_config_s;
```
</reference_materials>

<phases>
## Phase 1: Build libghostty Library

**Objective**: Build libghostty as a static library that can be linked into the Swift app.

**Steps**:
1. Navigate to `/tmp/libghostty/`
2. Run `zig build` to build the library
3. Locate the output artifacts:
   - Static library: `zig-out/lib/libghostty.a`
   - Header: Already at `include/ghostty.h`
4. Copy artifacts to AgentApp:
   - Create `/Users/williamcory/agent/AgentApp/Libraries/` directory
   - Copy `libghostty.a` and `ghostty.h`

**Verification**: The `.a` file exists and is a valid static library.

**Notes**:
- Requires Xcode 26 with macOS 26 SDK (check HACKING.md for latest requirements)
- May need to build with specific flags for embedding: `-Dapp-runtime=none`

---

## Phase 2: Create Swift Bridging Layer

**Objective**: Set up Swift-to-C bridging for libghostty.

**Steps**:
1. Create bridging header at `AgentApp/AgentApp/ghostty-bridging-header.h`:
   ```c
   #import "ghostty.h"
   ```

2. Update `Package.swift` to:
   - Add the bridging header
   - Link against `libghostty.a`
   - Add necessary system frameworks (Metal, CoreGraphics, etc.)

3. Create Swift wrapper types (reference `/tmp/libghostty/macos/Sources/Ghostty/`):
   - `GhosttyApp.swift` - Wraps `ghostty_app_t`
   - `GhosttyConfig.swift` - Wraps `ghostty_config_t`
   - `GhosttyTypes.swift` - Swift enums for C enums

**Verification**: Swift code can call `ghostty_info()` and get version.

---

## Phase 3: Create GhosttyTerminalView

**Objective**: Create a SwiftUI view that renders a Ghostty terminal surface.

**Steps**:
1. Create `GhosttyTerminalView.swift` as an `NSViewRepresentable`
2. Implement the NSView subclass that:
   - Creates a ghostty surface with the view's NSView
   - Handles keyboard input via `keyDown(with:)`
   - Handles mouse input
   - Manages the render loop (Metal)

3. Key implementation details:
   ```swift
   class GhosttyNSView: NSView {
       var surface: ghostty_surface_t?
       var app: ghostty_app_t

       func createSurface() {
           var config = ghostty_surface_config_new()
           config.platform_tag = GHOSTTY_PLATFORM_MACOS
           config.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
           config.scale_factor = window?.backingScaleFactor ?? 2.0
           config.command = "/bin/zsh"
           surface = ghostty_surface_new(app, &config)
       }
   }
   ```

**Reference files**:
- `/tmp/libghostty/macos/Sources/Ghostty/SurfaceView_AppKit.swift`
- `/tmp/libghostty/macos/Sources/Ghostty/SurfaceView.swift`

**Verification**: A basic terminal renders and accepts keyboard input.

---

## Phase 4: Replace SwiftTerm in AgentApp

**Objective**: Swap out SwiftTerm for the new Ghostty implementation.

**Steps**:
1. Update `TerminalView.swift` to use `GhosttyTerminalView` instead of `SwiftTerminalView`
2. Update `Package.swift` to remove SwiftTerm dependency
3. Remove or archive old files:
   - `SwiftTermView.swift`
   - `TerminalEmulatorView.swift`
   - Old terminal buffer/parser code

4. Update any code that references the old terminal:
   - `PlueCore.swift` terminal state handling
   - Event handling for terminal input

**Verification**: App builds and terminal tab shows working Ghostty terminal.

---

## Phase 5: Integration Testing & Polish

**Objective**: Ensure full functionality and polish the integration.

**Steps**:
1. Test all terminal functionality:
   - Shell commands execute correctly
   - Colors and styling work
   - Scrollback works
   - Copy/paste works
   - Resize works

2. Performance testing:
   - Render performance with lots of output
   - Memory usage

3. Polish:
   - Match styling with rest of app
   - Handle errors gracefully
   - Clean up any debug code

**Verification**: Full terminal functionality matches or exceeds SwiftTerm.
</phases>

<subagent_instructions>
## How to Use Subagents

For each phase, spawn a dedicated subagent to handle the implementation:

```
Phase 1: subagent_type="Explore" -> Research build process
         subagent_type="general-purpose" -> Execute build and copy artifacts

Phase 2: subagent_type="Explore" -> Study Swift bridging patterns in ghostty
         subagent_type="general-purpose" -> Implement bridging layer

Phase 3: subagent_type="Explore" -> Study SurfaceView implementation details
         subagent_type="general-purpose" -> Implement GhosttyTerminalView

Phase 4: subagent_type="general-purpose" -> Perform the swap

Phase 5: subagent_type="general-purpose" -> Testing and fixes
```

## Subagent Prompts Template

When spawning subagents, provide them with:
1. Clear objective for their phase
2. Reference file paths to read
3. Expected deliverables
4. Success criteria
</subagent_instructions>

<important_notes>
## Critical Considerations

1. **Xcode Version**: Ghostty tip requires Xcode 26 with macOS 26 SDK. If not available, may need to use a stable release tag.

2. **Metal Rendering**: Ghostty uses Metal for GPU rendering. The NSView must be properly configured for Metal layer.

3. **Runtime Callbacks**: The `ghostty_runtime_config_s` requires callback functions for:
   - `wakeup_cb` - Wake up the main thread
   - `action_cb` - Handle actions from ghostty
   - `read_clipboard_cb` / `write_clipboard_cb` - Clipboard access
   - `close_surface_cb` - Surface close requests

4. **Thread Safety**: Ghostty API calls must happen on the main thread.

5. **Memory Management**: Ghostty uses manual memory management. All `_new` functions have corresponding `_free` functions.

## Fallback Plan

If libghostty integration proves too complex:
1. Keep SwiftTerm as fallback
2. Consider using ghostty as a subprocess instead of embedded library
3. Or wait for official libghostty embedding documentation
</important_notes>

<success_criteria>
The integration is successful when:

1. [ ] AgentApp builds without SwiftTerm dependency
2. [ ] Terminal tab shows a functional Ghostty-powered terminal
3. [ ] Shell commands execute and output displays correctly
4. [ ] Keyboard input works (including special keys, ctrl sequences)
5. [ ] Mouse input works (selection, scrolling)
6. [ ] Terminal resizes correctly with window
7. [ ] Performance is smooth (60fps rendering)
8. [ ] No memory leaks
9. [ ] Error states are handled gracefully
</success_criteria>

<files_to_modify>
## AgentApp Files

- `Package.swift` - Add libghostty, remove SwiftTerm
- `Terminal.swift` - Update FFI stubs or remove
- `TerminalView.swift` - Use new GhosttyTerminalView
- `SwiftTermView.swift` - Remove or archive

## New Files to Create

- `Libraries/libghostty.a` - Compiled library
- `Libraries/ghostty.h` - C header
- `ghostty-bridging-header.h` - Swift bridging header
- `GhosttyApp.swift` - Swift wrapper for ghostty_app_t
- `GhosttyConfig.swift` - Swift wrapper for ghostty_config_t
- `GhosttyTerminalView.swift` - SwiftUI terminal view
</files_to_modify>
