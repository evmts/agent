# Design Spec: Keyboard Shortcuts (Section 10)

## 10) Keyboard shortcuts

### Global (both windows)

| Shortcut | Action                                               |
| -------- | ---------------------------------------------------- |
| ⌘S       | Save current file                                    |
| ⌘⇧S      | Save all                                             |
| ⌘⇧O      | Open folder                                          |
| ⌘P       | Go to file (opens IDE + palette if needed)           |
| ⌘⇧F      | Search in files (opens IDE + search panel if needed) |
| ⌘K       | Focus chat composer (from any window)                |
| ⌘Q       | Quit Smithers (explicit quit, not window close)      |

### Chat window

| Shortcut | Action                           |
| -------- | -------------------------------- |
| Return   | Send (or Steer if agent running) |
| Tab      | Queue follow-up (if agent running) |
| ⇧Return  | New line                         |
| ⌘N       | New chat                         |
| ⌘V       | Paste image                      |
| Esc      | Interrupt (if running) / defocus |
| ⌘↑/⌘↓   | Jump between messages            |

### IDE window

| Shortcut | Action                 |
| -------- | ---------------------- |
| ⌘B       | Toggle sidebar         |
| ⌘`       | New terminal           |
| ⌘⇧N      | Toggle Neovim mode     |
| ⌘/       | Toggle shortcuts panel |

### Tmux-style prefix keys (Ctrl+A)

`TmuxKeyHandler` monitors keyboard events at the app level via `NSEvent.addLocalMonitorForEvents`. When **Ctrl+A** is pressed, it enters prefix mode and waits for the follow-up key. This is **critical for the TUI-native experience** — users coming from tmux expect these keybindings to work identically.

| Follow-up key | Action                |
| ------------- | --------------------- |
| c             | New terminal          |
| n             | Next tab              |
| p             | Previous tab          |
| 1–9           | Select tab by index   |
| &             | Close current tab     |
| z             | Toggle terminal zoom (full-pane) |
| \|            | Split vertical        |
| -             | Split horizontal      |

**Prefix timeout:** If no follow-up key within **1 second**, cancel prefix mode. A subtle "PREFIX" indicator appears in the status bar while in prefix mode (see section 6.4).

**The terminal is always one keystroke away:** Ctrl+A c opens a new terminal immediately, from any context. This must feel instantaneous.

### TUI-native keyboard philosophy

Every core action must be achievable without a mouse. The keyboard navigation flow:

- **Ctrl+A c** → new terminal (always, from any window)
- **Cmd+`** → new terminal (macOS-native alternative)
- **Cmd+P** → command palette (fuzzy find anything: files, commands, settings)
- **Cmd+K** → focus chat composer (from any window)
- **Esc** → dismiss current overlay / return to previous context
- **Tab / Shift+Tab** → cycle through panes within a window

The goal: a user who never touches their mouse should feel at home in Smithers.
