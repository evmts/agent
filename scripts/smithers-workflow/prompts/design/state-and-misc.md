# State Management, Animations, Responsive, Accessibility & Implementation

## 11) State management (shared across windows)

### 11.1 Core model layers

Shared `AppModel` injected both window roots.

Recommended structure:

- `AppModel` (@Observable)
  - `workspace: WorkspaceModel?`
  - `preferences: PreferencesModel`
  - `windowCoordinator: WindowCoordinator` (show/hide/focus IDE, routing)

- `WorkspaceModel`
  - `fileTreeModel`, `tabModel` (open tabs, selected), `editorModel` (per-file view state: scroll, selection), `chatModel` (sessions, selected, messages), `jjModel` (status/log/bookmarks/ops/snapshots), `agentModel` (orchestrator state), `skillsModel`
  - `services`: `CodexService`, `JJService`, `SearchService`, etc.

### 11.2 Window-local UI state

Ephemeral UI state per window:

- `ChatWindowUIState`: sidebar mode, sidebar search query, message hover state, active action bar, composer draft + attachments
- `IDEWindowUIState`: sidebar width/collapsed, active overlays (palette/search/shortcuts), command palette query + selection

Persist only what improves "return-to-work": window frames, open tabs + selected tab, editor per-file positions, selected chat session

---

## 12) Animations & timing

Consistent motion vocabulary (short, subtle).

| Interaction | Duration | Curve |
|-------------|----------|-------|
| Chat message insert | 0.20s | ease-in-out |
| Auto-scroll to bottom | 0.20s | ease-out |
| Hover action bar appear | 0.15s delay + 0.12s fade | ease-out |
| Folder disclosure rotate | 0.15s | ease-in-out |
| Command palette appear | 0.25s | spring (bounce 0.15) |
| Search panel slide | 0.20s | ease-in-out |
| Toast appear | 0.25s | ease-out |
| Toast dismiss | 0.15s | ease-in |
| Progress bar value | 0.20s | ease-in-out |
| Editor jump-to-line | 0.20s | ease-in-out |
| Cursor blink | 0.53s interval | linear fade 0.22s |

---

## 13) Responsive behavior

### Chat window

Sidebar min 200pt; collapses entirely below window width 680pt; Detail content: message bubble max 80–90% (lines not too long), composer sticks bottom always

### IDE window

Sidebar collapsible: toggle ⌘B, auto-collapse if window <720pt wide (optional); Tab bar: if narrow hide subtitles, icons + filename only

---

## 14) Accessibility

Every interactive element: accessibility label, identifier (UI tests), tooltip via `.help()`

Full keyboard nav: sidebar lists arrows + Enter select, command palette arrows + Enter, chat Cmd+Up/Down jump messages (optional recommended)

VoiceOver: message bubbles grouped; action bar buttons explicit labels ("Copy message", "Fork from here", etc.)

---

## Implementation notes (non-visual, critical)

**Chat rendering** highly optimized: `LazyVStack`, avoid reflow on streaming by appending attributed runs rather rerendering entire markdown tree each delta

**File tree** virtualized lazy-loaded as already done

Centralize tokens in `AppTheme`/`ThemeTokens`, never hardcode colors in views

### Image storage & management

Chat images (pasted/dropped/attached) stored disk, not inline database:

- **Storage:** `~/Library/Application Support/Smithers/images/<hash>` — content-addressed by hash
- **Database ref:** `images` table stores `(id, message_id, filename, data_hash)`, hash references file on disk
- **Thumbnails:** generated 56×56 for attachment strip + chat display, cached memory
- **Full-size viewer:** clicking thumbnail opens fullscreen overlay (5.4.2)
- **Cleanup:** unused images (not referenced any message) **pruned periodically** app launch or workspace close, prevents disk bloat deleted messages
- **Size limits:** individual 20MB cap, total 1GB per workspace (configurable), oldest pruned when limit reached

### Commit style detection

`CommitStyleDetector` analyzes last 30 commits `jjService.log(limit: 30)` detects team conventions:

- **Conventional commits:** `type(scope): description` (e.g., `feat(auth): add OAuth login`)
- **Emoji prefixes:** messages starting emoji (e.g., `✨ Add new feature`)
- **Freeform:** no consistent pattern detected

Detected style used by AI generating commit descriptions (JJ panel "Describe" action or automatic snapshot descriptions). Ensures AI messages match team conventions without manual config.

### IPC server & smithers-ctl CLI

Smithers runs **Unix socket IPC server** `~/Library/Application Support/Smithers/smithers.sock` (or `/tmp/smithers.sock`) for external tools.

**`smithers-ctl` CLI commands:**

| Command | Description |
|---------|-------------|
| `smithers-ctl open-file <path> [+line:col]` | Open file at location (vim-style `+line:col`) |
| `smithers-ctl terminal [run] <command>` | Open terminal, optionally run command |
| `smithers-ctl search <query>` | Trigger workspace search |
| `smithers-ctl diff show` | Open diff viewer with piped diff content |
| `smithers-ctl webview open <url>` | Open URL in webview tab |
| `smithers-ctl webview eval <js>` | Execute JavaScript in active webview |
| `smithers-ctl agent spawn <task>` | Spawn new sub-agent |
| `smithers-ctl agent cancel <id>` | Cancel running agent |
| `smithers-ctl agent status [id]` | Get agent status |
| `smithers-ctl jj status` | Get JJ status |
| `smithers-ctl status` | Get app/workspace status |
| `smithers-ctl read <path>` | Read file contents |
| `smithers-ctl write <path>` | Write file contents from stdin |
| `smithers-ctl set <key> <value>` | Change setting |

**Wait-for-close:** `smithers-ctl open-file --wait` blocks until file closed editor. Useful `$EDITOR` integration (e.g., `export EDITOR="smithers-ctl open-file --wait"`)

**Unified capability surface:** CLI provides same capabilities as command palette + MCP server. Adding capability to one surface must add to all three (see engineering spec capability matrix)
