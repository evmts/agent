# Terminal Implementation Unification Plan

## Current State Analysis

### Working Implementations

1. **macOS PTY (Recommended Primary Implementation)**
   - **Zig**: `src/macos_pty.zig`
   - **Swift**: `MacOSPtyTerminal.swift`, `MacOSPtyTerminalView.swift`, `TerminalSurfaceView.swift`
   - **Status**: Fully functional, uses native macOS PTY APIs
   - **Pros**: 
     - Native performance
     - Proper terminal emulation
     - Thread-safe
     - Supports resize
     - Clean FFI interface
   - **Cons**: macOS-specific

2. **Mini Terminal**
   - **Zig**: `src/mini_terminal.zig`
   - **Swift**: `MiniTerminal.swift`, `MiniTerminalView.swift`
   - **Status**: Functional but simplified
   - **Pros**: Cross-platform potential
   - **Cons**: Less feature-complete

3. **PTY Terminal**
   - **Zig**: `src/pty_terminal.zig`
   - **Swift**: `PtyTerminal.swift`
   - **Status**: Basic functionality
   - **Pros**: Uses std.process.Child for portability
   - **Cons**: Not true PTY, limited terminal features

### Non-functional/Stub Implementations

1. **Ghostty Terminal**
   - **Status**: Stubs only, missing dependencies
   - **Issue**: Requires complex Ghostty build integration

2. **Simple Terminal**
   - **Status**: Disabled due to API issues

3. **Other variants**: MockTerminal, ProperTerminalView, etc.

## Unification Recommendations

### Short-term (Immediate)

1. **Standardize on macOS PTY as primary implementation**
   - It's the most complete and functional
   - Already integrated with the UI via `MacOSPtyTerminalView`
   - Provides real terminal emulation

2. **Clean up redundant implementations**
   - Remove or mark as deprecated: simple_terminal, minimal_terminal
   - Keep mini_terminal as a fallback option
   - Keep ghostty stubs for future integration

3. **Fix the current terminal tab**
   - ✅ Already fixed the undefined `terminal` reference
   - The terminal tab now properly uses `MacOSPtyTerminal`

### Medium-term

1. **Improve the terminal UI**
   - Add proper ANSI color support (ANSIParser exists but needs integration)
   - Implement terminal scrollback
   - Add copy/paste support
   - Improve font rendering

2. **Create a unified terminal interface**
   ```zig
   // src/terminal_interface.zig
   pub const TerminalInterface = struct {
       init: fn() c_int,
       start: fn() c_int,
       stop: fn() void,
       write: fn(data: [*]const u8, len: usize) isize,
       read: fn(buffer: [*]u8, len: usize) isize,
       resize: fn(cols: u16, rows: u16) void,
       get_fd: fn() c_int,
   };
   ```

3. **Implement platform abstraction**
   - macOS: Use current PTY implementation
   - Linux: Add Linux PTY support
   - Windows: Add ConPTY support

### Long-term

1. **Ghostty Integration**
   - Work with Nix flake to properly integrate Ghostty
   - This would provide the most feature-complete terminal

2. **Performance optimizations**
   - Implement efficient terminal buffer management
   - Add GPU-accelerated rendering
   - Optimize ANSI parsing

## Implementation Priority

1. **Immediate**: Use current macOS PTY implementation (✅ Done)
2. **Next Sprint**: Clean up redundant code
3. **Following Sprint**: Improve terminal UI features
4. **Future**: Platform abstraction and Ghostty integration

## File Organization Proposal

```
src/
├── terminal/
│   ├── interface.zig      # Common terminal interface
│   ├── macos_pty.zig     # macOS implementation
│   ├── linux_pty.zig     # Future Linux implementation
│   └── windows_conpty.zig # Future Windows implementation
├── terminal.zig          # Public API that selects platform
└── libplue.zig          # Exports terminal functions

Sources/plue/
├── Terminal/
│   ├── TerminalView.swift      # Unified terminal view
│   ├── TerminalSurface.swift   # NSView-based surface
│   └── ANSIParser.swift        # ANSI escape sequence parser
└── ContentView.swift           # Uses TerminalView
```

## Testing Strategy

1. Create terminal test suite:
   - Basic I/O operations
   - ANSI escape sequences
   - Resize handling
   - Process lifecycle

2. Manual testing checklist:
   - [ ] Terminal starts and displays prompt
   - [ ] Can type commands and see output
   - [ ] ANSI colors work
   - [ ] Terminal resizes properly
   - [ ] Copy/paste works
   - [ ] Terminal cleanup on exit

## Conclusion

The macOS PTY implementation is currently the best option and is already working. The immediate fix has been applied to make the terminal tab functional. Future work should focus on:

1. Cleaning up redundant implementations
2. Improving the terminal UI/UX
3. Adding cross-platform support
4. Eventually integrating Ghostty for advanced features