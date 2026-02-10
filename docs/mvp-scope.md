# MVP Scope Gating

Prevents agents from implementing post-MVP features prematurely.

## P0 — Must Ship

- Scaffold: repo structure, build.zig, libsmithers stub, C API, xcframework pipeline
- Design system: tokens, shared components, theme
- Chat window: sidebar (chats/source/agents modes), messages, composer, streaming
- Codex integration: in-process Zig API, send/receive/stream
- Chat persistence: SQLite, session CRUD
- IDE window: file tree, editor (TreeSitter syntax), tabs, breadcrumbs, status bar
- Cross-window: "Open in Editor" from chat, AI diff preview
- Terminal: GhosttyKit embedded surfaces, terminal tabs
- JJ: bundled binary, working copy status, commit, undo, snapshot
- Agent orchestration: sub-agent spawn, status tracking, jj branch per agent
- Command palette: Cmd+P file open, Cmd+Shift+P commands, Cmd+/ shortcuts
- Web app: SolidJS parity for all P0 features, Playwright e2e tests
- Keyboard: all core actions keyboard-accessible, tmux-compat prefix
- Settings: core prefs (theme, font size, keybindings, agent config)

## P1 — Nice to Have

- Background/scheduled agents (issue 007)
- Multiple agent backends beyond Codex (issue 004 — Claude Code, OpenCode)
- Neovim modal editing mode
- Image paste/drop + fullscreen viewer
- Search: workspace-wide Cmd+Shift+F (ripgrep)
- Light theme
- Diff viewer (tabs + sheets)
- Toast notifications, progress indicators
- Auto-update (Sparkle)

## P2 — Stubs/Reserved UI OK, No Implementation

- Skills system (scanner, registry, installer)
- URL scheme deep linking
- IPC server (Unix socket)
- Menu bar background mode with agent status

## Post-MVP — Do Not Implement

- Multi-workspace / Conductor parity (issue 038)
- Workflow Studio (issue 039)
- Workspace tools sidebar panels (issue 020)
- MiniApps (issue 013)
- Telegram agent bridge (issue 010)
- Remote development (issue 033)
- JJ merge queue UI
- LSP integration
- Cross-platform (Linux/iOS)

## Gating Rule

When Discover compares "what SHOULD exist vs what does", it MUST check this scope:
- P0 items that are incomplete = valid tickets
- P1 items = valid tickets only after all P0 complete
- P2 items = stubs only, no full implementation
- Post-MVP items = NEVER create tickets for these
