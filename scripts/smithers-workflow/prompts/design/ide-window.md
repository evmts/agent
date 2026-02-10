# Design IDE Window Spec (Secondary)

## 6) IDE Window spec (Secondary)

### 6.1 Layout overview

Root container: `NavigationSplitView`

- Sidebar width: **180–400pt** (default 240pt)
- Detail area: flexible

**Structure:**

- `IDEWindowRootView` (NavigationSplitView)

  - Sidebar: `FileTreeSidebar`
  - Detail: `IDEWorkspaceDetailView`

### 6.2 File tree sidebar

#### Empty state

- Centered icon + text:

  - Icon: `folder`
  - Title: "No Folder Open"
  - Button: "Open Folder…"
  - Shortcut hint: "⌘⇧O"

#### Tree appearance

- Background: `surface1`
- Root header (folder name) uses `surface2`
- Indentation:

  - 16pt per depth level
  - Indent guides: 1px line `border @ 35%` opacity

- Row height: 28–32pt (files), 28–32pt (folders)

#### Row spec: `FileTreeRow`

- Layout (HStack):

  - Disclosure chevron (folders only), 12pt icon
  - **File/folder icon (16pt, colored by file type):**

    - Swift: orange
    - TypeScript/JavaScript: blue/yellow
    - Python: green
    - Rust: red-brown
    - Zig: orange-gold
    - JSON/YAML: gray
    - Markdown: light blue
    - Folders: default folder icon, accent when expanded
    - Use SF Symbols where possible; fall back to generic `doc` icon

  - Name text (11pt)
  - Spacer
  - **Modified dot** (files only): 6pt circle, `color.warning` (yellow), visible when file has unsaved changes

- States:

  - Hover: white@4%
  - Selected: accent "capsule" indicator on left edge

    - Indicator: 3pt wide, radius 2, full row height minus 6pt inset

  - **Current file:** The file open in the active editor tab gets a subtle background highlight (`accent@6%`) in addition to the capsule indicator.

- Context menus:

  - Folders: New File, New Folder, Copy Path, Reveal in Finder, Rename, Delete
  - Files: Copy Path, Reveal in Finder, Open in Terminal, Rename, Delete

- **Inline rename:** On "Rename", the name label becomes a focused text field. Enter commits, Esc cancels.

#### Keyboard navigation

- **Arrow Up/Down:** Move selection through visible rows.
- **Arrow Right:** Expand folder (if collapsed) or move to first child.
- **Arrow Left:** Collapse folder (if expanded) or move to parent.
- **Enter:** Open selected file in editor tab.
- **Space:** Quick-look preview (optional).
- **Delete/Backspace:** Delete with confirmation.

#### Lazy loading & auto-refresh

- Expand folder triggers children load (lazy, not preloaded).
- Chevron rotates 90° on expand, animation 0.15s ease-in-out.
- **Auto-refresh:** File tree watches the workspace directory via `FSEvents`. When files are created, deleted, or renamed on disk (by the AI agent, terminal, or external tools), the tree updates automatically without manual refresh. Debounce filesystem events by 250ms to avoid flicker during rapid changes.
- **`.gitignore` / `.jj/ignore` respect:** Hidden files and ignored patterns are excluded by default. Toggle "Show Hidden Files" in context menu or command palette.

---

## 6.3 IDE detail view

`IDEWorkspaceDetailView` (VStack spacing 0)

1. `IDETabBar` (32pt) — only if at least one tab open
2. `BreadcrumbBar` (18–22pt) — only for file tabs
3. Divider
4. `IDEContentArea` (fills)
5. Divider
6. `IDEStatusBar` (22pt)

### 6.3.1 Tab bar

Tab types allowed:

- file
- terminal
- diff
- webview
- chat (sub-agent conversations, forked chats — any chat can be opened as a tab in the workspace panel)

**Tab bar styling (Nova-like):**

- Background: `surface2`
- Selected tab:

  - subtle brighter background (white@6% over surface2)
  - accent underline capsule 2pt height

- Unselected:

  - text secondary

- Tab geometry:

  - Height: 28–30pt inside a 32pt bar
  - Radius: 8
  - Padding: 10pt horizontal per tab
  - Min width: 120pt, max width: 220pt
  - If total tabs <= available width: distribute evenly
  - Else: horizontal scroll

**Tab item contents:**

- Leading file type icon (colored)
- Filename (11pt)
- Modified dot OR close button on hover
- Optional subtitle (path) appears in tooltip rather than constant UI to reduce noise.

**Interactions:**

- Click selects tab
- Drag reorder:

  - show insertion highlight
  - animate swap

- Middle-click closes
- Context menu:

  - Close / Close Others / Close All / Close to Right
  - Copy Path
  - Reveal in Finder
  - Reveal in Sidebar

Right side:

- Overflow menu button (ellipsis.circle)

  - "Switch To" list of tabs
  - "Close" actions

### 6.3.2 Breadcrumb bar

- Background: `surface1` (or surface2 if you want chrome continuity)
- Font: 10pt
- Path segments are clickable
- Last segment bold
- Opacity gradient: earlier segments tertiary, later segments secondary/primary

### 6.3.3 Content area (switch by selected tab)

#### A) Code editor

This describes the visual contract; your current STTextView/TextKit2-based editor already supports much of it.

- Background: `surface1`
- Gutter:

  - Line numbers width: 44–56pt depending on digits
  - Background: `surface1`
  - Divider: 1px `border`

- Current line highlight: `white@6–10%`
- Matching bracket highlight: `white@16%`
- Indent guides: 1px `border @ 35%`
- Minimap (optional):

  - Width: 70pt
  - Separator: 1px `border`

- Scrollbar overlay:

  - right edge overlay
  - modes: always / automatic / never

#### Multi-cursor support

- **Option+Click:** Add a cursor at click position.
- **Option+Shift+Up/Down:** Add cursor on adjacent line above/below.
- **Cmd+D:** Select next occurrence of current selection (adds cursor).
- **Cmd+Shift+L:** Select all occurrences of current selection (adds cursors at each).
- **Escape:** Collapse all cursors back to a single primary cursor.
- All cursors type, delete, and select simultaneously.
- Grouped undo: a multi-cursor edit is one undo step.
- Multi-cursor copy/paste: each cursor gets its own clipboard line.
- Visual: each cursor rendered identically (blinking bar/block per preference). Selections at each cursor highlighted with `selectionBackground`.

#### Ghost text completions (AI inline suggestions)

- **`GhostTextOverlayView`** renders dimmed preview text at the cursor position.
- Display: dim text (`white@35–45%`) overlaid at cursor, pass-through to editor (no hit testing).
- **Fade in:** 0.12s ease-out when suggestion arrives.
- **Fade out:** 0.12s when dismissed or accepted.
- **Accept:** Tab inserts the full suggestion.
- **Dismiss:** Esc clears the suggestion.
- **Typing:** If user types characters that match the suggestion, advance through it. If user diverges, cancel the suggestion and request a new one.
- **Completion pipeline:** `CompletionService` sends requests to codex-app-server after **300ms debounce**. Streaming partial results update the ghost text in real time. Each keystroke cancels the previous request (generation counter pattern).
- **No ghost text in Neovim mode** — Neovim has its own completion system.

#### Pinch-to-zoom

- **Pinch gesture** (trackpad) adjusts editor font size in real time.
- Range: 8pt–48pt (matches font size preference range).
- Persists the new font size to preferences on gesture end.
- Smooth scaling with no layout flicker.

#### Press-and-hold disable

- macOS normally shows an accent character popup when you press-and-hold a key (e.g., holding "e" shows é, ê, ë, etc.).
- Smithers **disables this behavior** globally for the editor and terminal views. This ensures key repeat works correctly for vim-style navigation (holding `j` to scroll down, holding `h` to move left, etc.).
- Implemented via `NSUserDefaults` `ApplePressAndHoldEnabled = false` scoped to the app.

#### Smooth scrolling

- **`SmoothScrollController`** provides velocity-based animated scrolling for the editor and terminal.
- Scroll events are interpolated with easing (not jarring pixel jumps).
- Terminal scrolling snaps to cell grid boundaries for clean rendering.
- Integrated with Neovim mouse scroll RPC when in Neovim mode.
- Direction detection: natural vs. inverted scrolling respects system preference.

#### Link detection

- **File paths** in assistant chat messages: Recognize `path:line:col` patterns, render as clickable links (accent color, underline on hover). Click opens IDE to location via `showInEditor()`.
- **URLs** in chat messages and terminal output: Recognized and rendered as clickable links. Click opens in default browser or as a webview tab (user preference).
- **Terminal link detection:** Cmd+Click on file paths or URLs in terminal output. Ghostty handles URL detection natively; we add file path detection for workspace-relative paths.

#### Neovim mode parity

Every editor feature must be considered through the lens of Neovim mode. When Neovim mode is active, the STTextView editor is **replaced** by a Ghostty terminal running embedded Neovim. Features that are editor-only vs. shared:

| Feature | Editor mode | Neovim mode |
|---------|-------------|-------------|
| Syntax highlighting | TreeSitter (Swift-side) | Neovim's built-in |
| Multi-cursor | Custom implementation | Neovim plugins (vim-visual-multi, etc.) |
| Ghost text | GhostTextOverlayView | Not applicable (Neovim has own completion) |
| Auto-save | Editor auto-save on interval | **Also works** — BufWritePost detected |
| JJ auto-snapshot | Triggered on save | **Also works** — BufWritePost triggers snapshot |
| Pinch-to-zoom | Trackpad gesture | Not applicable (terminal font size) |
| Line numbers | Editor gutter | Neovim's `set number` |
| Current line highlight | Editor feature | Neovim's `cursorline` |
| Bracket matching | Editor feature | Neovim's `matchparen` |
| Find/replace | Command palette search | Neovim's `/` and `:%s` |
| Undo/redo | Editor undo stack | Neovim's undo tree |

#### Loading state

- Skeleton lines with shimmer:

  - pulsing opacity 0.8s autoreverse

#### B) Terminal (Ghostty)

- Full terminal view; tab title updates live.
- Use same scrollbar overlay style for consistency.
- **Smooth scrolling:** Velocity-based with grid snapping (see Smooth scrolling above).
- **Link detection:** Cmd+Click on URLs and file paths. Workspace-relative paths open in editor.

#### C) Diff viewer (unified)

Standalone component used in IDE tabs, chat sheet previews, and inline diff cards.

**Header bar (32pt):**

- Left: filename (13pt medium) + `+N −M` summary (monospace, success/danger tint)
- Right: hunk navigation arrows (up/down icon buttons) + hunk counter ("3/12")
- "Open in Tab" button if diff appears as inline panel or chat sheet

**Diff content:**

- **Syntax highlighting within diffs:** Added/removed lines retain full syntax coloring from TreeSitter, not just green/red tinting. The background tint is applied underneath the syntax colors.
- Diff line backgrounds:

  - Additions: `success@12%` background
  - Deletions: `danger@12%` background
  - Hunk headers (`@@`): `accent@8%` background, `info` text
  - Context lines: no background tint

- Line numbers: dual gutter (old line number | new line number), monospace 10pt, tertiary
- Long lines: horizontal scroll (no wrapping by default)

**Controls (toolbar, trailing):**

- **Wrap lines toggle:** Wraps long lines instead of horizontal scroll. Icon: `text.word.spacing`.
- **Compact mode toggle:** Hides context lines, shows only changed hunks. Icon: `arrow.up.and.down.text.horizontal`.
- **Full-screen mode:** Expands diff to fill the entire content area (hides sidebar, tab bar). Toggle with Escape or button.

**Keyboard navigation:**

- **]c / [c** (vim-style): Jump to next/previous hunk.
- **Arrow Up/Down:** Scroll through diff lines.
- **Cmd+Up/Down:** Jump to next/previous file (multi-file diffs).

**Diff sources:**

- AI file changes (from Codex turn)
- JJ working copy diffs
- JJ change-to-change diffs
- Session diffs (before/after a chat session)
- Manual `smithers-ctl diff show` invocation

**Multi-file diff:**

- Left sidebar (200pt) shows file list with per-file `+N −M` counts.
- Clicking a file scrolls the diff pane to that file's section.
- Files ordered by: modified > added > deleted.

#### D) Webview tab

- `WKWebView` with title observation
- Tab label uses page title
- Back/forward buttons are hidden by default (reduce noise); accessible via command palette commands or context menu.

---

## 6.4 Status bar

Height: 22pt
Background: `surface2`
Top divider: 1px border

Sections:

- Left: `Ln X, Col Y | UTF-8 | LF` (monospace, 10pt secondary)
- Center: Skills indicator (if any active)

  - "Skills: a, b +N"
  - click opens skills popover

- Right: `Language | Spaces: 4` (10pt secondary)

**Additional status bar indicators:**

- **Neovim mode indicator** (left, after line/col): When Neovim mode is active, shows current vim mode in a small badge:

  - NORMAL: `accent@15%` background, accent text
  - INSERT: `success@15%` background, success text
  - VISUAL: `warning@15%` background, warning text
  - COMMAND: `info@15%` background, info text

- **Tmux prefix indicator** (left): When tmux prefix key (Ctrl+A) is pressed and awaiting follow-up, shows "PREFIX" badge with `accent@20%` background. Auto-dismisses after 1s timeout.

---

## 6.5 Neovim mode

Neovim mode is a **major feature** — not a secondary concern. Many Smithers users will spend most of their editing time in Neovim mode. When enabled, the STTextView-based code editor is **replaced** by a Ghostty terminal running an embedded Neovim instance with full UI extensions.

### 6.5.1 Activation

- Toggle: **Cmd+Shift+N** (global shortcut, both windows).
- When activated, the current file tab's content view switches from `CodeEditorView` to `NvimTerminalView`.
- When deactivated, switches back. File state (cursor position, unsaved changes) is preserved across transitions.
- Persisted per-workspace (if you enable Neovim mode, it stays enabled next launch).

### 6.5.2 Architecture overview

1. `NvimController` creates a Unix domain socket at `/tmp/smithers-nvim-<uuid>.sock`.
2. Launches Neovim in a hidden Ghostty terminal with `--listen <socket>`.
3. Connects to the socket with retry (10 attempts, 100ms backoff).
4. Attaches UI with extensions: `ext_multigrid`, `ext_cmdline`, `ext_popupmenu`, `ext_messages`, `ext_hlstate`.
5. Installs autocmds for `BufEnter`/`BufLeave`/`BufWritePost` to track file changes.
6. Starts a notification loop to handle Neovim events.

### 6.5.3 Bidirectional sync

Neovim and the Smithers UI must stay in sync at all times:

- **User selects file in sidebar →** NvimController sends `:edit <path>` via RPC. Neovim opens the file.
- **User opens file in Neovim →** `BufEnter` autocmd fires → NvimController updates `TabModel` (ensures tab exists and is selected) and `EditorStateModel`.
- **User saves in Neovim →** `BufWritePost` autocmd fires → NvimController marks file as clean in tab model. This **also triggers JJ auto-snapshot** (same 2s debounce as editor auto-save). This ensures JJ snapshotting works identically whether the user saves from the editor or from Neovim.
- **Tab model changes →** If user switches tabs via the tab bar (clicking, keyboard), NvimController sends `:edit <path>` to sync Neovim to the new tab.
- **File tree, terminal, and tab model** all coordinate with NvimController as the source of truth for which file is active when in Neovim mode.

### 6.5.4 External UI overlays

Neovim's ext_ui extensions allow Smithers to render Neovim's UI elements as native SwiftUI overlays on top of the terminal view, rather than inside the terminal character grid:

**Command line overlay (`NvimCmdlineOverlay`):**

- Position: bottom of editor area, above status bar.
- Background: `surface2`, radius 8, 1px `border`.
- Shows the current command line (`:`, `/`, `?`, `!` prompts).
- Monospace text, same font as editor.
- Cursor visible and blinking.
- Dismisses when command is executed or cancelled.

**Popup menu overlay (`NvimPopupMenuOverlay`):**

- Position: anchored at cursor position in the terminal.
- Background: `surface2`, radius 8, shadow (overlay spec).
- Shows completion candidates from Neovim's native completion.
- Rows: icon (type) + text + detail (secondary, trailing).
- Selected row: `accent@12%` background.
- Max visible rows: 10 (scrollable).
- Arrow keys navigate, Enter selects, Esc dismisses.

**Message overlay (`NvimMessageOverlay`):**

- Position: floating notifications, top-right of editor area.
- Max 6 visible simultaneously; oldest auto-expire after 4s.
- Background: `surface2`, radius 8, shadow.
- Message levels map to semantic colors: error → danger, warning → warning, info/echo → primary.
- Slide-in from right, fade-out on dismiss.

**Floating windows (`NvimFloatingWindowView`):**

- Plugin-created floating windows (hover docs, signature help, etc.).
- Rendered as native views on top of the terminal.
- Configurable appearance:

  - **Blur:** 0–30pt radius (preference, default 10).
  - **Shadow:** 0–30pt radius (preference, default 8).
  - **Corner radius:** 0–20pt (preference, default 8).

- Background: `surface2` with blur effect (vibrancy).
- Border: 1px `border`.

### 6.5.5 Theme synchronization

When Neovim mode is activated, Smithers reads Neovim's highlight groups and derives an `AppTheme`:

- `Normal.bg` → `background`, `Normal.fg` → `foreground`
- `Visual.bg` → `selectionBackground`
- `CursorLine.bg` → `lineHighlight`
- `TabLine*` → tab bar colors
- `Pmenu*` → popup/panel colors
- `LineNr` / `CursorLineNr` → line number colors
- Missing groups: derived via alpha blending from background + foreground.

This theme **overrides the default app theme** while Neovim mode is active, so the entire UI matches the user's Neovim colorscheme. When Neovim mode is deactivated, the app reverts to the standard theme.

### 6.5.6 Mode indicator

The current Neovim mode is displayed in the status bar (see section 6.4). Additionally:

- **Cursor shape changes** with mode: bar (insert), block (normal), underline (replace). Ghostty handles this natively via terminal escape sequences.
- The mode indicator updates in real-time as the user switches between normal/insert/visual/command modes.

### 6.5.7 Input method switching (CJK support)

**Critical for CJK (Chinese/Japanese/Korean) users.** `InputMethodSwitcher` automatically:

- Switches to an **ASCII-capable input source** when entering Neovim normal mode (so `j`, `k`, `dd`, etc. work without interference from IME).
- **Restores the previous input source** when entering insert mode (so the user can type in their language).
- This behavior is automatic and requires no user configuration.

### 6.5.8 Crash recovery

If the Neovim process dies unexpectedly, show a **recovery view** (`NvimRecoveryView`) instead of silently failing:

- Centered in the editor area where Neovim was running.
- Background: `surface1`.
- Content:

  - Warning icon (large, `color.warning`)
  - Title: "Neovim crashed unexpectedly"
  - Subtitle: crash type (startup failure / runtime crash / unexpected exit)
  - Three action buttons:

    - **Restart Neovim** (PrimaryButton): Attempts to restart with full workspace state restoration (same files, same positions).
    - **Disable Neovim Mode** (secondary button): Switches back to the standard editor, preserving all open files.
    - **Reveal Crash Report** (tertiary link): Opens Finder to `~/Library/Application Support/Smithers/Nvim/Reports/`.

- **Crash report generation:** Captures Neovim logs, workspace state, open files, and last RPC messages. Saved to `~/Library/Application Support/Smithers/Nvim/Reports/`.
- **Neovim log routing:** All Neovim output is routed to `~/Library/Application Support/Smithers/Nvim/Logs/` for debugging.

### 6.5.9 Neovim settings (Preferences)

Under the "Neovim" category in Settings:

- **Nvim binary path:** Text field with file picker. Validates that the path points to a working `nvim` binary. Default: system `nvim` from PATH.
- **Option-as-Meta:** Dropdown (Left / Right / Both / None). Controls whether Option key sends Meta in the Neovim terminal. Same setting as Terminal preferences.
- **Floating window blur:** Toggle + radius slider (0–30pt).
- **Floating window shadow:** Toggle + radius slider (0–30pt).
- **Floating window corner radius:** Slider (0–20pt).
