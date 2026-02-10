# Design Principles & Window Architecture

## Ultimate UX for Agentic Coding — TUI to GUI

**Goal: build ultimate UX for agentic coding evolving TUI to GUI.**

Targets TUI power-users living in terminal — Claude Code, vim, tmux users want better harness, NOT VS Code users seeking AI plugin. Must **feel like TUI, have GUI UX**:

- **Keyboard first.** Every core action achievable without mouse. Tmux-style prefix, vim-compatible nav, command palette everything.
- **Feels like terminal, built as GUI.** Native Swift app — not terminal app. Designed to *feel* like terminal to power users. One keystroke from literal terminal (via **GhosttyKit** — Ghostty's emulator library embedded as terminal surfaces). Neovim mode makes file editing feel vim. Tmux shortcuts work everywhere. GUI adds value through things painful in raw terminal — orchestrating multiple agents, visual diff review, quad-pane layouts — without losing what terminal users love: speed, keyboard control, directness.
- **Chat first.** Primary interaction conversational. Main chat window = "pane 0" — always present. Everything else (editor, file tree, JJ panel, agents, terminals) attaches to and orchestrated from chat.

NOT "chat + IDE." A **chat-first agentic coding environment** where AI orchestrates work across multiple sub-agents, human monitors/steers/intervenes when needed.

### Chat sidebar modes

Main chat window sidebar not just chat history. Three modes (visible in `prototype1/`):

1. **Chats** — Top-level conversation history grouped by time, ability to **fork** any conversation at any point. User's direct conversations with main agent.
2. **Source** — JJ (Jujutsu) version control panel: working copy changes, change log, bookmarks, operation log, snapshots.
3. **Agents** — Background sub-agent dashboard. **Separate from top-level chats.** Sub-agents = ephemeral background workers spawned by main agent. Run without human in loop, user monitors status here.

**Top-level chats vs. sub-agents are different.** Top-level chat = user talking to orchestrator. Sub-agent = background worker delegated by orchestrator for specific task. Agent dashboard shows sub-agent status; chat history shows conversation threads.

### Reference prototype

Target look/feel in `prototype1/` — Next.js + TypeScript + Tailwind CSS mockup ("Smithers v2 prototype"). Also live v0: https://v0.app/chat/mac-os-ide-prototype-cEqmBbcomU7

**Prototype = design reference for BOTH native macOS app and SolidJS web app.** Web app (`web/`) should look close to native — same colors, spacing, layout, components. CSS custom properties (`--sm-*`) from prototype used directly in web app.

---

## Chat‑First Dual‑Window macOS IDE (SwiftUI, macOS 14+)

Translates "chat‑as‑primary" paradigm into implementable pixel‑precise UI system. Assumes all core capabilities remain functionally available (editor/terminal/JJ/agents/skills/search/diffs), reorganized into **two independent windows** sharing state.

---

## 0) Product principles

1. **Chat default workspace.** User never opens IDE window, app still feels complete.
2. **Secondary tools on-demand.** IDE window revealed only when human wants inspect/edit or AI produces work worth reviewing.
3. **Least-noisy UI.** No persistent clutter. Observable constraints:
   - Hover-only action bars appear within 100ms of hover
   - No more than 3 persistent toolbar buttons in composer/footer
   - Chrome controls hidden until hover or focus; no always-visible icons for actions used <20% of the time
4. **macOS-native behaviors.** Traffic lights, standard Cmd shortcuts, proper focus rings, contextual menus, draggable window background.
5. **Performance-first rendering.** Observable constraints:
   - Chat list uses `LazyVStack` (Swift) / virtualized list (web) — no full DOM/view tree for off-screen messages
   - No full markdown reparse on each streaming token delta — append-only rendering
   - File tree loads children on expand (lazy), no eager recursion of entire workspace
   - Debounce search/filter inputs by 150ms
   - No blur effects except small overlays (<400x400px)
6. **One design system shared.** Same tokens, same components. IDE chrome uses Nova-inspired syntax palette (see `system-tokens.md` §2.3). Chat density follows compact messaging app conventions (8-12px vertical padding between messages).
7. **TUI-native feel.** Keyboard-first nav, tmux-compatible prefix keys, terminal always one keystroke away. GUI exists as harness making complex workflows possible — orchestrating multiple agents, visual diff review, long-running parallel tasks — things painful in raw terminal.

---

## 1) Window architecture & lifecycle

### 1.1 Windows

Two `NSWindow` instances, two SwiftUI roots, one shared app state.

- **Chat Window (primary)**
  - Created on launch
  - Closing **hides window, does NOT quit app**. Smithers continues background with **menu bar icon** (like Slack, Discord). Required for scheduled agents fire on schedule. Menu bar shows agent status, allows quick access. Quitting explicit via Cmd+Q or menu "Quit".
  - Always shows chat detail

- **IDE Window (secondary)**
  - Created on demand
  - Closing **hides** (doesn't destroy state)
  - Reopening restores last tab set, scroll positions, sidebar widths

### 1.2 Default sizing & placement

Per workspace, persist both window frames independently (WindowFrameStore expanded to two keys).

Default Chat Window: width 45% screen visible frame, height 85%, origin center-left (x offset −6% screen width from center)

Default IDE Window: width 55%, height 85%, origin center-right (x offset +6%)

### 1.3 Window chrome (both)

`titlebarAppearsTransparent = true`, `.hiddenTitleBar` / "full-size content view"; Traffic lights standard position; Content extends behind titlebar; `isMovableByWindowBackground = true` — ensure only non-interactive chrome regions participate drag

### 1.4 Focus / activation rules

Opening IDE from chat: brings IDE front; If invoked "Open in Editor" on diff/file path, IDE selects that file tab scrolls target line

When AI finishes applying changes: chat window remains focused unless pref "Auto-open IDE on file change" enabled

### 1.5 Menu bar icon & background mode

Smithers persists **menu bar app** even all windows closed. Menu bar icon (`NSStatusItem`) provides:

- **Status indicator:** Idle (default icon), Working (animated dot/spinner), Completed (badge count finished agents)
- **Click menu:** "Show Smithers" (reveal chat), "New Chat" (new session + reveal), "Active Agents" (submenu listing running agents + status), separator, "Check for Updates…", "Preferences…", "Quit Smithers" (⌘Q)
- **Notification badge:** background/scheduled agent completes, icon briefly pulses + macOS notification (if enabled)

Required **scheduled agents** feature (cron-like background tasks) + agents running while user switched to another app.

### 1.6 URL scheme deep linking

Registers URL schemes Info.plist:

- `smithers://` — general deep linking
- `smithers-open-file://<path>?line=N&col=M` — opens file at location. Used by external tools, terminal output, Finder.
- `smithers-chat://<session-id>` — opens specific chat session

Behavior: all funnel through `ExternalOpenRequest` handler with batch support; Pending URL queue if files opened before workspace ready, process once workspace loads; Workspace root inference when opening file — walk up directory hierarchy looking `.jj/`, `.git/`, or project files
