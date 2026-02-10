# Design Spec: State Management, Animations, Responsive, Accessibility & Implementation Notes (Sections 11-14+)

## 11) State management approach (shared across windows)

### 11.1 Core model layers

Use a shared `AppModel` injected into both window roots.

**Recommended structure:**

- `AppModel` (ObservableObject)

  - `workspace: WorkspaceModel?`
  - `preferences: PreferencesModel`
  - `windowCoordinator: WindowCoordinator` (show/hide/focus IDE, routing)

- `WorkspaceModel`

  - `fileTreeModel`
  - `tabModel` (open tabs, selected tab)
  - `editorModel` (per-file view state: scroll, selection)
  - `chatModel` (sessions, selected session, messages)
  - `jjModel` (status/log/bookmarks/ops/snapshots)
  - `agentModel` (orchestrator state)
  - `skillsModel`
  - `services`: `CodexService`, `JJService`, `SearchService`, etc.

### 11.2 Window-local UI state

Keep ephemeral UI state per window:

- `ChatWindowUIState`

  - sidebar mode
  - sidebar search query
  - message hover state, active action bar
  - composer draft + attachments

- `IDEWindowUIState`

  - sidebar width / collapsed
  - active overlays: palette/search/shortcuts
  - command palette query + selection

Persist only what improves "return-to-work":

- window frames
- open tabs + selected tab
- editor per-file positions
- selected chat session

---

## 12) Animations & timing

Use a consistent motion vocabulary (short, subtle).

| Interaction              |                 Duration | Curve                |
| ------------------------ | -----------------------: | -------------------- |
| Chat message insert      |                    0.20s | ease-in-out          |
| Auto-scroll to bottom    |                    0.20s | ease-out             |
| Hover action bar appear  | 0.15s delay + 0.12s fade | ease-out             |
| Folder disclosure rotate |                    0.15s | ease-in-out          |
| Command palette appear   |                    0.25s | spring (bounce 0.15) |
| Search panel slide       |                    0.20s | ease-in-out          |
| Toast appear             |                    0.25s | ease-out             |
| Toast dismiss            |                    0.15s | ease-in              |
| Progress bar value       |                    0.20s | ease-in-out          |
| Editor jump-to-line      |                    0.20s | ease-in-out          |
| Cursor blink             |           0.53s interval | linear fade 0.22s    |

---

## 13) Responsive behavior

### Chat window

- Sidebar min width: 200pt; collapses entirely below window width 680pt
- Detail content:

  - message bubble max width remains 80–90% so lines don't get too long
  - composer sticks to bottom always

### IDE window

- Sidebar collapsible:

  - toggle with ⌘B
  - auto-collapse if window < 720pt wide (optional)

- Tab bar:

  - if narrow, hide tab subtitles; icons + filename only

---

## 14) Accessibility

- Every interactive element has:

  - accessibility label
  - identifier (for UI tests)
  - tooltip via `.help()`

- Full keyboard navigation:

  - sidebar lists: arrows, Enter to select
  - command palette: arrows + Enter
  - chat: Cmd+Up/Down to jump between messages (optional but recommended)

- VoiceOver:

  - message bubbles grouped; action bar buttons have explicit labels ("Copy message", "Fork from here", etc.)

---

## Implementation notes (non-visual, but critical)

- Keep **chat rendering** highly optimized:

  - `LazyVStack`
  - avoid reflow on streaming by appending attributed runs rather than rerendering entire markdown tree each delta.

- Keep **file tree** virtualized and lazy-loaded as you already do.
- Centralize all tokens in `AppTheme` / `ThemeTokens` and never hardcode colors in views.

### Image storage & management

Chat images (pasted, dropped, or attached) are stored on disk, not inline in the database:

- **Storage location:** `~/Library/Application Support/Smithers/images/<hash>` — images are content-addressed by hash.
- **Database reference:** The `images` table stores `(id, message_id, filename, data_hash)`. The hash references the file on disk.
- **Thumbnails:** Generated at 56×56 for the attachment strip and chat message display. Thumbnails are cached in memory.
- **Full-size viewer:** Clicking a thumbnail opens the fullscreen image viewer overlay (see section 5.4.2).
- **Cleanup:** Unused images (not referenced by any message) are **pruned periodically** on app launch or workspace close. This prevents disk bloat from deleted messages.
- **Size limits:** Individual images capped at 20MB. Total image storage capped at 1GB per workspace (configurable). Oldest images pruned when limit is reached.

### Commit style detection

`CommitStyleDetector` analyzes the last 30 commits from `jjService.log(limit: 30)` and detects the team's commit message conventions:

- **Conventional commits:** `type(scope): description` (e.g., `feat(auth): add OAuth login`).
- **Emoji prefixes:** Messages starting with emoji (e.g., `✨ Add new feature`).
- **Freeform:** No consistent pattern detected.

The detected style is used by the AI when generating commit descriptions (via the JJ panel's "Describe" action or automatic snapshot descriptions). This ensures AI-generated messages match the team's existing conventions without manual configuration.

### IPC server & smithers-ctl CLI

Smithers runs a **Unix socket IPC server** at `~/Library/Application Support/Smithers/smithers.sock` (or `/tmp/smithers.sock`) for communication with external tools.

**`smithers-ctl` CLI commands:**

| Command | Description |
|---------|-------------|
| `smithers-ctl open-file <path> [+line:col]` | Open file at location (vim-style `+line:col` syntax) |
| `smithers-ctl terminal [run] <command>` | Open terminal, optionally run a command |
| `smithers-ctl search <query>` | Trigger workspace search |
| `smithers-ctl diff show` | Open diff viewer with piped diff content |
| `smithers-ctl webview open <url>` | Open URL in webview tab |
| `smithers-ctl webview eval <js>` | Execute JavaScript in active webview |
| `smithers-ctl agent spawn <task>` | Spawn a new sub-agent |
| `smithers-ctl agent cancel <id>` | Cancel a running agent |
| `smithers-ctl agent status [id]` | Get agent status |
| `smithers-ctl jj status` | Get JJ status |
| `smithers-ctl status` | Get app/workspace status |
| `smithers-ctl read <path>` | Read file contents |
| `smithers-ctl write <path>` | Write file contents (from stdin) |
| `smithers-ctl set <key> <value>` | Change a setting |

**Wait-for-close pattern:** `smithers-ctl open-file --wait` blocks until the file is closed in the editor. Useful for `$EDITOR` integration (e.g., `export EDITOR="smithers-ctl open-file --wait"`).

**Unified capability surface:** The CLI provides the same capabilities as the command palette and MCP server. Adding a capability to one surface must add it to all three (see engineering spec for the full capability matrix).
