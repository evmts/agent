# IDE Window Spec (Secondary)

## 6.1 Layout

Root: `NavigationSplitView` — sidebar 180–400pt (default 240pt), detail flexible

`IDEWindowRootView` → `FileTreeSidebar` + `IDEWorkspaceDetailView`

## 6.2 File tree sidebar

### Empty state

Centered: folder icon, "No Folder Open", "Open Folder…" button, "⌘⇧O" hint

### Tree appearance

Bg `surface1`, root header `surface2`; Indent 16pt per level, guides 1px `border@35%`; Row height 28–32pt

### Row spec

HStack: disclosure chevron (folders, 12pt), file/folder icon 16pt colored (Swift orange, TS/JS blue/yellow, Python green, Rust red-brown, Zig orange-gold, JSON/YAML gray, Markdown light blue, folders accent when expanded, SF Symbols fallback `doc`), name 11pt, spacer, modified dot 6pt `color.warning` (unsaved)

States: Hover `white@4%`, selected accent capsule 3pt width radius 2 full height minus 6pt inset; Current file `accent@6%` bg + capsule

Context: Folders (New File/Folder, Copy Path, Reveal, Rename, Delete), Files (Copy Path, Reveal, Open in Terminal, Rename, Delete); Inline rename Enter commits Esc cancels

### Keyboard nav

Arrows Up/Down move; Right expands folder or first child; Left collapses or parent; Enter opens; Space quick-look; Delete confirms

### Lazy loading & auto-refresh

Expand triggers children load, chevron rotates 90° 0.15s ease-in-out; Auto-refresh via `FSEvents` 250ms debounce; Respects `.gitignore`/`.jj/ignore`, toggle "Show Hidden Files" in context/palette

---

## 6.3 IDE detail

`IDEWorkspaceDetailView` (VStack spacing 0): TabBar (32pt if tabs) + BreadcrumbBar (18–22pt if file) + Divider + ContentArea (fills) + Divider + StatusBar (22pt)

### 6.3.1 Tab bar

Types: file, terminal, diff, webview, chat (sub-agents, forked chats — any chat can open as tab)

Nova-like: bg `surface2`; Selected `white@6%` + accent underline 2pt; Unselected secondary text; Geometry 28–30pt in 32pt bar, radius 8, padding 10pt h, min 120pt max 220pt; Distribute evenly if fits else h-scroll

Contents: leading icon (colored), filename 11pt, modified dot OR close on hover; Tooltip shows path

Interactions: Click selects, drag reorder (insertion highlight, animate swap), middle-click closes; Context: Close / Close Others / All / to Right, Copy Path, Reveal Finder/Sidebar

Right: overflow menu (ellipsis — "Switch To" list, close actions)

### 6.3.2 Breadcrumb bar

Bg `surface1` (or `surface2`), 10pt font, clickable segments, last bold, opacity gradient (earlier tertiary, later secondary/primary)

### 6.3.3 Content area

#### A) Code editor

Bg `surface1`; Gutter 44–56pt line numbers, bg `surface1`, divider 1px `border`; Current line `white@6–10%`, matching bracket `white@16%`, indent guides 1px `border@35%`; Minimap optional 70pt + separator 1px; Scrollbar overlay (always/auto/never)

**Multi-cursor:** Opt+Click add cursor, Opt+Shift+Up/Down adjacent line, Cmd+D next occurrence, Cmd+Shift+L all occurrences, Esc collapse; All cursors type/delete/select together, grouped undo, multi-clipboard; Each cursor identical blink/block per pref

**Ghost text:** `GhostTextOverlayView` dim `white@35–45%` overlay at cursor, pass-through no hit; Fade in 0.12s ease-out, fade out 0.12s dismiss/accept; Tab accepts, Esc dismisses, typing advances or cancels; `CompletionService` 300ms debounce to codex-app-server, streaming updates, generation counter cancels previous; Not in Neovim mode

**Pinch-to-zoom:** trackpad adjusts font 8–48pt real-time, persists on gesture end, smooth no flicker

**Press-and-hold disable:** macOS accent popup disabled (`ApplePressAndHoldEnabled = false` scoped), ensures key repeat for vim (holding j/h/etc)

**Smooth scrolling:** `SmoothScrollController` velocity-based easing (not jarring jumps); Terminal snaps to cell grid; Integrated with Neovim mouse scroll RPC; Respects natural/inverted system pref

**Link detection:** File paths `path:line:col` clickable (accent underline hover, opens IDE via `showInEditor()`); URLs in chat/terminal clickable (browser or webview tab per pref); Terminal Cmd+Click paths/URLs, Ghostty handles URLs natively, add file path detection workspace-relative

**Neovim mode parity:** When active, STTextView replaced by Ghostty terminal running embedded Neovim

| Feature | Editor mode | Neovim mode |
|---------|-------------|-------------|
| Syntax highlight | TreeSitter Swift-side | Neovim built-in |
| Multi-cursor | Custom | Plugins (vim-visual-multi) |
| Ghost text | GhostTextOverlayView | N/A (Neovim completion) |
| Auto-save | Editor interval | BufWritePost detected |
| JJ auto-snapshot | On save | BufWritePost triggers |
| Pinch-to-zoom | Trackpad gesture | N/A (terminal font) |
| Line numbers | Editor gutter | `set number` |
| Current line | Editor feature | `cursorline` |
| Bracket matching | Editor feature | `matchparen` |
| Find/replace | Command palette | `/` and `:%s` |
| Undo/redo | Editor stack | Undo tree |

**Loading:** skeleton lines shimmer pulse 0.8s autoreverse

#### B) Terminal (Ghostty)

Full terminal, tab title updates live; Same scrollbar overlay; Smooth scrolling velocity + grid snap; Link detection Cmd+Click URLs + workspace-relative file paths open editor

#### C) Diff viewer

Standalone for IDE tabs, chat sheets, inline cards

**Header 32pt:** left filename 13pt medium + `+N −M` mono success/danger, right hunk arrows up/down + counter "3/12", "Open in Tab" if inline/sheet

**Content:** Syntax highlighting within diffs — added/removed retain TreeSitter syntax under tint; Line bg: additions `success@12%`, deletions `danger@12%`, hunks `@@` `accent@8%` bg `info` text, context no tint; Line numbers dual gutter (old | new) mono 10pt tertiary; Long lines h-scroll (no wrap default)

**Controls (toolbar trailing):** Wrap toggle (icon `text.word.spacing`), Compact toggle (hides context, icon `arrow.up.and.down.text.horizontal`), Full-screen (fills area, hides sidebar/tabs, Esc or button)

**Keyboard:** `]c` / `[c` vim-style next/prev hunk; Arrows Up/Down scroll; Cmd+Up/Down next/prev file (multi-file)

**Sources:** AI changes (Codex), JJ working copy diffs, JJ change-to-change, session diffs, manual `smithers-ctl diff show`

**Multi-file:** left sidebar 200pt file list `+N −M` per-file; Click scrolls diff pane to file section; Order: modified > added > deleted

#### D) Webview

`WKWebView` title observation, tab uses page title; Back/forward hidden default (reduce noise, accessible via palette/context)

---

## 6.4 Status bar

22pt, `surface2`, top divider 1px

Left: `Ln X, Col Y | UTF-8 | LF` mono 10pt secondary; Center: Skills "Skills: a, b +N" (click popover); Right: `Language | Spaces: 4` 10pt secondary

**Additional indicators:**

- **Neovim mode** (left after line/col): badge shows vim mode — NORMAL `accent@15%` bg accent text, INSERT `success@15%` success text, VISUAL `warning@15%` warning text, COMMAND `info@15%` info text
- **Tmux prefix** (left): "PREFIX" badge `accent@20%` bg when Ctrl+A pressed awaiting follow-up, auto-dismiss 1s

---

## 6.5 Neovim mode

Major feature — many users spend most time here. When enabled, STTextView replaced by Ghostty terminal running embedded Neovim with full UI extensions.

### 6.5.1 Activation

Toggle Cmd+Shift+N (global both windows); Switches `CodeEditorView` ↔ `NvimTerminalView`; File state (cursor, unsaved) preserved across transitions; Persisted per-workspace

### 6.5.2 Architecture

1. `NvimController` creates Unix socket `/tmp/smithers-nvim-<uuid>.sock`
2. Launches Neovim hidden Ghostty terminal `--listen <socket>`
3. Connects retry (10 attempts, 100ms backoff)
4. Attaches UI extensions: `ext_multigrid`, `ext_cmdline`, `ext_popupmenu`, `ext_messages`, `ext_hlstate`
5. Installs autocmds `BufEnter`/`BufLeave`/`BufWritePost` track file changes
6. Starts notification loop handle events

### 6.5.3 Bidirectional sync

- User selects file sidebar → NvimController `:edit <path>` RPC, Neovim opens
- User opens file Neovim → `BufEnter` autocmd → update `TabModel` (ensure tab exists/selected) + `EditorStateModel`
- User saves Neovim → `BufWritePost` → mark clean tab model, triggers JJ auto-snapshot (2s debounce same as editor)
- Tab model changes → switch tabs bar click/keyboard → NvimController `:edit <path>` sync
- File tree, terminal, tab model coordinate with NvimController as source of truth active file Neovim mode

### 6.5.4 External UI overlays

Neovim ext_ui render native SwiftUI overlays on terminal (not in char grid)

**Cmdline (`NvimCmdlineOverlay`):** bottom editor area above status, `surface2` radius 8 1px `border`, shows current cmdline (`:` `/` `?` `!`), mono same font editor, cursor visible blinking, dismisses on exec/cancel

**Popup menu (`NvimPopupMenuOverlay`):** anchored cursor position, `surface2` radius 8 shadow, completion candidates Neovim native; Rows icon (type) + text + detail (secondary trailing); Selected `accent@12%`; Max 10 rows scrollable; Arrows + Enter/Esc

**Message (`NvimMessageOverlay`):** floating notifications top-right editor; Max 6 visible, oldest auto-expire 4s; `surface2` radius 8 shadow; Levels → colors: error danger, warning warning, info/echo primary; Slide-in right, fade-out dismiss

**Floating windows (`NvimFloatingWindowView`):** plugin floats (hover docs, signature help); Native views on terminal; Configurable: blur 0–30pt (pref default 10), shadow 0–30pt (pref default 8), corner radius 0–20pt (pref default 8); Bg `surface2` blur vibrancy, border 1px `border`

### 6.5.5 Theme sync

Neovim mode reads highlight groups derives `AppTheme`: `Normal.bg` → `background`, `Normal.fg` → `foreground`, `Visual.bg` → `selectionBackground`, `CursorLine.bg` → `lineHighlight`, `TabLine*` → tab bars, `Pmenu*` → popup/panels, `LineNr`/`CursorLineNr` → line numbers; Missing derived via alpha blend bg+fg

Overrides app theme while active, reverts on deactivate

### 6.5.6 Mode indicator

Status bar (6.4) + cursor shape changes mode: bar (insert), block (normal), underline (replace) — Ghostty handles via escape sequences; Real-time updates

### 6.5.7 Input method (CJK)

**Critical CJK.** `InputMethodSwitcher` auto: switches ASCII-capable input source entering normal mode (so j/k/dd work without IME), restores previous input source entering insert mode (type native language); Automatic no config

### 6.5.8 Crash recovery

If Neovim dies, `NvimRecoveryView` instead silent fail: centered editor area, `surface1` bg; Warning icon large `color.warning`, title "Neovim crashed unexpectedly", subtitle crash type (startup/runtime/unexpected exit); Actions: Restart Neovim (PrimaryButton — attempts restart full state restoration same files/positions), Disable Neovim Mode (secondary — switches standard editor preserves files), Reveal Crash Report (tertiary link — opens Finder `~/Library/Application Support/Smithers/Nvim/Reports/`)

Crash report: captures logs, workspace state, open files, last RPC messages → `~/Library/Application Support/Smithers/Nvim/Reports/`; Neovim logs → `~/Library/Application Support/Smithers/Nvim/Logs/`

### 6.5.9 Settings

Neovim category in Preferences:

- Nvim binary path: text field + file picker, validates working `nvim`, default system PATH
- Option-as-Meta: dropdown Left/Right/Both/None, controls Option→Meta terminal (same as Terminal prefs)
- Floating window blur: toggle + slider 0–30pt
- Floating window shadow: toggle + slider 0–30pt
- Floating window corner radius: slider 0–20pt
