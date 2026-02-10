# Web Application (SolidJS)

## 12A. Web App (SolidJS)

Native macOS = primary. **Developed in tandem**: SolidJS web app (`web/`) talks to same `libsmithers` via HTTP/WS server (`src/http_server.zig`). Every native feature also in web. Two purposes:

1. **Cross-platform access** — browser access while native stays macOS-only
2. **E2E via Playwright** — **primary motivation**: testable surface for backend without XCUITest

### 12A.1 Stack

- **SolidJS+Vite** — reactive UI + bundler. **PWA** (installable, offline cached). SPA w/ client routing, feels native. Plain stores (`createStore`) — mirrors Swift `@Observable`, SolidJS best practices.
- **shadcn-solid** (hngngn/shadcn-solid) — shadcn/ui port, unstyled accessible composable primitives
- **Tailwind CSS** — utility-first. Design tokens from `docs/design.md` → Tailwind config
- **Monaco Editor** — VS Code component for IDE editing
- **xterm.js** — terminal emulator, connects PTY (libsmithers) via WS
- **Playwright** — e2e tests: web UI → HTTP/WS → libsmithers (Zig) → Codex/JJ
- **pnpm** — package manager

### 12A.2 Feature Parity (In Tandem)

**Every native feature = web feature.** Simultaneous dev, NOT "port later". Feature added to `macos/Sources/Features/Chat/` → SolidJS in `web/src/features/Chat/` same cycle.

`web/src/features/` mirrors `macos/Sources/Features/`:

```
web/src/
├── features/
│   ├── Chat/           — sidebar, msgs, composer, slash cmds, @mention, steer
│   ├── IDE/            — file tree, tabs, breadcrumbs, Monaco, status bar
│   ├── Agents/         — dashboard, scheduled agents
│   ├── Terminal/       — xterm.js (libsmithers PTY via WS)
│   ├── Settings/       — prefs UI
│   └── Skills/         — browser, activation
├── components/         — shadcn-solid (Button, Dialog, Popover, etc)
├── lib/
│   ├── api-client.ts   — HTTP REST for libsmithers
│   ├── ws-client.ts    — WS real-time (chat deltas, agent status, file changes)
│   ├── store.ts        — SolidJS stores (createStore — mirrors AppModel/WorkspaceModel)
│   └── types.ts        — Hand-maintained TS types (synced by AI + e2e tests)
├── styles/
│   └── tokens.css      — CSS vars matching design.md §2.1 (same as prototype)
└── tests/
    └── e2e/            — Playwright (mirrors features)
```

### 12A.3 Visual Parity

Web looks **as close to native as possible**. `prototype/` = design ref for **both** — same colors, spacing, layout, components. CSS vars (`--sm-base`, `--sm-surface1`, `--sm-accent`, etc) from prototype → `tokens.css` directly.

**Prototype lifecycle:** `prototype/` = frozen ref. **Deleted** once SolidJS fully functional, replaces as visual ref.

### 12A.4 Communication w/ libsmithers

Web does NOT bundle/run libsmithers. Connects to running HTTP/WS server (`src/http_server.zig`, interface #4 from §2.6). **No auth** — localhost only.

**HTTP REST:**
`POST /api/chat/send`, `GET /api/chat/sessions`, `GET /api/workspace/files`, `POST /api/workspace/open`, `POST /api/agent/spawn`, `POST /api/terminal/create`, etc (same capability as C API, MCP, CLI)

**WebSocket:**
`ws://localhost:<port>/ws` — events: chat deltas, agent status, file changes, turn completions
`ws://localhost:<port>/ws/terminal/<id>` — PTY I/O for xterm.js
Mirrors `CodexEvent` on Swift side

### 12A.5 Playwright Testing

**Primary reason web exists.** E2E coverage of libsmithers Zig core without XCUITest:

```
web/tests/e2e/
├── chat.spec.ts          — send, receive, verify streaming
├── chat-commands.spec.ts — slash, @mentions, steer
├── file-tree.spec.ts     — open workspace, browse, Monaco
├── editor.spec.ts        — edit, save, persist
├── terminal.spec.ts      — xterm, run cmd, verify output
├── agents.spec.ts        — spawn, monitor, complete
├── jj.spec.ts            — VCS ops, snapshots, undo
└── skills.spec.ts        — activate, modified prompts
```

**Strategy:** Tests run against real libsmithers (not mocks). Validates: SolidJS → HTTP/WS → Zig → Codex/JJ. Combined w/ Zig unit + Swift XCUITests = three layers.

**CI:** `zig build playwright` starts HTTP server → `pnpm exec playwright test` → teardown

### 12A.6 Build Integration

- `zig build web` → `cd web && pnpm install && pnpm build`
- `zig build dev` includes web step
- `zig build playwright` → build web + start HTTP + run tests
- HTTP server serves built static files directly (no separate web server)
