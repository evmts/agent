# Terminal Subsystem

## 9. Terminal Subsystem

### 9.1 GhosttyApp Singleton

```swift
final class GhosttyApp {
    static let shared = GhosttyApp()
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?, tickScheduled = false

    private init() {
        ghostty_init(...)
        // Create config, load defaults, finalize
        // Create runtime w/ callbacks (wakeup, action, clipboard, close_surface)
        // Create app handle
    }

    func scheduleTick() {
        // Coalesced: one tick per main queue cycle
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.tickScheduled = false
            ghostty_app_tick(self?.app)
        }
    }
}
```

**Callback pattern:** C callbacks = static funcs. Extract Swift obj via `Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()`. Dispatch main queue for UI.

**Focus tracking:** Observes `NSApplication.didBecomeActiveNotification`/`didResignActive` → calls `ghostty_app_set_focus()`.

### 9.2 GhosttyTerminalView

`NSView` subclass, conforms `NSTextInputClient`.

**Lifecycle:**
1. `init(app:workingDirectory:command:optionAsMeta:)` — creates surface via `ghostty_surface_new()`, stores `self` as userdata
2. `shutdown()` — frees surface (main thread) via `ghostty_surface_free()`, stops frame scheduler

**Surface access:** Static `from(surface:) -> GhosttyTerminalView?` extracts Swift obj from C surface userdata.

**Frame scheduling:** `GhosttyFrameScheduler` uses display link → `setNeedsDisplay()` at refresh rate. Visibility-aware, pauses when not visible.

**Input:** `GhosttyInput.swift` maps `NSEvent` keycodes → Ghostty constants. Handles modifiers, Option-as-Meta, IME via `NSTextInputClient`.

### 9.3 Terminal Tabs

Terminal tabs = `TabItem` kind `.terminal(id:title:)`. Each has `GhosttyTerminalView` stored in dict on `AppModel` (or `TerminalManager`). Title updates (shell escape sequences) → tab title via Ghostty action callback.

Working directory defaults to workspace root.
