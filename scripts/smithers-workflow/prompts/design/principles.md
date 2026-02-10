# Design Principles — Product Principles & Window Architecture

## The Ultimate UX for Agentic Coding — TUI to GUI

**Our goal is to build the ultimate UX for agentic coding that evolves from TUI to GUI.**

Smithers targets TUI power-users who already live in the terminal — people who use Claude Code, vim, tmux, and want a better harness, not VS Code users looking for an AI plugin. The app must **feel like a TUI but have the UX of a GUI**:

- **Keyboard first.** Every core action is achievable without a mouse. Tmux-style prefix keys, vim-compatible navigation, and command palette for everything.
- **Feels like a terminal, built as a GUI.** This is a native Swift app — not a terminal app. But it is designed to *feel* like a terminal to power users. You're always one keystroke away from a literal terminal (via **GhosttyKit**, Ghostty's terminal emulator library embedded as terminal surfaces). Neovim mode makes file editing feel like vim. Tmux shortcuts work everywhere. The GUI adds value through things painful in a raw terminal — orchestrating multiple agents, visual diff review, quad-pane layouts — without losing what terminal users love: speed, keyboard control, and directness.
- **Chat first.** The primary interaction is conversational. The main chat window is "pane 0" — always present. Everything else (editor, file tree, JJ panel, agents, terminals) attaches to and is orchestrated from the chat.

This is not "chat + IDE." It's a **chat-first agentic coding environment** where the AI orchestrates work across multiple sub-agents, and the human monitors, steers, and intervenes when needed.

### What the chat sidebar shows

The main chat window's sidebar is not just chat history. It has three modes (visible in the prototype at `prototype/`):

1. **Chats** — Top-level conversation history, grouped by time, with the ability to **fork** any conversation at any point. These are the user's direct conversations with the main agent.
2. **Source** — JJ (Jujutsu) version control panel: working copy changes, change log, bookmarks, operation log, snapshots.
3. **Agents** — Background sub-agent dashboard. These are **separate from top-level chats**. Sub-agents are ephemeral background workers spawned by the main agent. They run without a human in the loop, and the user monitors their status here.

**Top-level chats vs. sub-agents are two different things.** A top-level chat is the user talking to the orchestrator. A sub-agent is a background worker delegated by the orchestrator to do a specific task. The agent dashboard shows sub-agent status; the chat history shows conversation threads.

### Reference prototype

The target look and feel is captured in `prototype/` — a Next.js + TypeScript + Tailwind CSS mockup (codenamed "Smithers v2 prototype"). See also the live v0 prototype: https://v0.app/chat/mac-os-ide-prototype-cEqmBbcomU7

**This prototype is the design reference for BOTH the native macOS app and the SolidJS web app.** The web app (`web/`) should look as close to the native app as possible — same colors, spacing, layout, and component structure. The CSS custom properties (`--sm-*`) from the prototype are used directly in the web app.

---

## Chat‑First Dual‑Window macOS IDE (SwiftUI, macOS 14+)

This spec translates the "chat‑as‑primary" paradigm shift into an implementable, pixel‑precise UI system. It assumes all core capabilities remain functionally available (editor/terminal/JJ/agents/skills/search/diffs), but reorganized into **two independent windows** that share state.

---

## 0) Product principles

1. **Chat is the default workspace.** If a user never opens the IDE window, the app still feels complete.
2. **Secondary tools are on-demand.** The IDE window is revealed only when a human wants to inspect/edit, or when the AI produces work worth reviewing.
3. **Least-noisy UI.** No persistent clutter. Controls are contextual, hover-revealed, or consolidated into overlays/command palette.
4. **macOS-native behaviors.** Traffic lights, standard Cmd shortcuts, proper focus rings, contextual menus, draggable window background.
5. **Performance-first rendering.** Virtualize long lists; debounce expensive operations; avoid heavy blur except in small overlays.
6. **One design system shared across windows.** Same tokens, same components, with "Nova-like" IDE chrome and "T3.chat-like" chat density.
7. **TUI-native feel.** Keyboard-first navigation, tmux-compatible prefix keys, terminal always one keystroke away. The GUI exists as a harness that makes complex workflows possible — orchestrating multiple agents, visual diff review, long-running parallel tasks — things painful in a raw terminal.

---

## 1) Window architecture & lifecycle

### 1.1 Windows

**Two `NSWindow` instances, two SwiftUI roots, one shared app state.**

- **Chat Window (primary)**

  - Created on launch.
  - Closing **hides the window but does NOT quit the app**. Smithers continues running in the background with a **menu bar icon** (like Slack, Discord). This is required for scheduled agents to fire on schedule. The menu bar icon shows agent status and allows quick access. Quitting is explicit via Cmd+Q or the menu bar icon's "Quit" option.
  - Always shows chat detail.

- **IDE Window (secondary)**

  - Created on demand.
  - Closing **hides** (does not destroy state).
  - Reopening restores last tab set, scroll positions, and sidebar widths.

### 1.2 Default sizing & placement

Per workspace, persist both window frames independently (existing WindowFrameStore concept, expanded to two keys).

- Default Chat Window:

  - Width: **45%** of current screen visible frame
  - Height: **85%** of screen visible frame
  - Origin: center-left (x offset −6% of screen width from center)

- Default IDE Window:

  - Width: **55%**
  - Height: **85%**
  - Origin: center-right (x offset +6%)

### 1.3 Window chrome (both)

- `titlebarAppearsTransparent = true`
- `.hiddenTitleBar` / "full-size content view"
- Traffic lights in standard position.
- Content extends behind titlebar.
- Window draggable by background:

  - `isMovableByWindowBackground = true`
  - Ensure only non-interactive chrome regions participate in drag.

### 1.4 Focus / activation rules

- Opening IDE from chat:

  - Brings IDE window to front.
  - If invoked from "Open in Editor" on a diff/file path, the IDE selects that file tab and scrolls to target line.

- When AI finishes applying changes:

  - Chat window remains focused unless the user preference "Auto-open IDE on file change" is enabled.

### 1.5 Menu bar icon & background mode

Smithers persists as a **menu bar app** even when all windows are closed. The menu bar icon (`NSStatusItem`) provides:

- **Status indicator:** Idle (default icon), Working (animated dot or spinner), Completed (badge with count of finished agents).
- **Click menu:**

  - "Show Smithers" → reveals chat window
  - "New Chat" → new chat session + reveal
  - "Active Agents" → submenu listing running agents with status
  - Separator
  - "Check for Updates…"
  - "Preferences…"
  - "Quit Smithers" (⌘Q)

- **Notification badge:** When a background/scheduled agent completes, the menu bar icon briefly pulses and shows a macOS notification (if enabled).

This is required for the **scheduled agents** feature (cron-like background tasks) and for agents that run while the user has switched to another app.

### 1.6 URL scheme deep linking

Smithers registers the following URL schemes in Info.plist:

- **`smithers://`** — General deep linking.
- **`smithers-open-file://<path>?line=N&col=M`** — Opens a file at a specific location. Used by external tools, terminal output, and Finder.
- **`smithers-chat://<session-id>`** — Opens a specific chat session.

**Behavior:**

- All URL schemes funnel through a single `ExternalOpenRequest` handler with batch support.
- **Pending URL queue:** If files are opened before workspace is ready, they queue and process once workspace loads.
- **Workspace root inference:** When opening a file, infer the workspace root from the file's directory hierarchy (walk up looking for `.jj/`, `.git/`, or project files).
