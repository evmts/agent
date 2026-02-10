# Web Application (SolidJS)

## 12A. Web Application (SolidJS)

The native macOS app is the primary product. **Developed completely in tandem**, we build a **SolidJS web application** (`web/`) that talks to the same `libsmithers` backend via the HTTP/WebSocket server (`src/http_server.zig`). Every feature implemented in the native app is also implemented in the web app. This serves two critical purposes:

1. **Cross-platform access** — Users can access Smithers from a browser while the native app remains macOS-only.
2. **End-to-end testing via Playwright** — The web app enables comprehensive **Playwright tests** that exercise the full libsmithers Zig core end-to-end. This is a primary motivation for building the web app: it gives us a testable surface for the entire backend logic without needing XCUITest.

### 12A.1 Stack

- **SolidJS + Vite** — reactive UI framework bundled with Vite. **PWA** (Progressive Web App) — installable, works offline for cached resources. SPA with client-side routing — feels like a native app. Plain SolidJS stores (`createStore`) for state management — mirrors the Swift `@Observable` model structure, follows SolidJS best practices.
- **shadcn-solid** (hngngn/shadcn-solid) — port of shadcn/ui to SolidJS. Provides unstyled, accessible, composable primitives.
- **Tailwind CSS** — utility-first styling. Design tokens from `docs/design.md` mapped to Tailwind config.
- **Monaco Editor** — VS Code's editor component for the IDE code editing surface.
- **xterm.js** — terminal emulator for the web. Connects to a PTY managed by libsmithers via WebSocket.
- **Playwright** — end-to-end test framework. Tests exercise the full stack: web UI → HTTP/WS → libsmithers (Zig) → Codex/JJ.
- **pnpm** — package manager (consistent with project convention).

### 12A.2 Feature parity (developed in tandem)

**Every feature in the native app is implemented in the web app.** The two are developed simultaneously — not as a "port later" effort. When a feature is added to `macos/Sources/Features/Chat/`, the corresponding SolidJS implementation goes into `web/src/features/Chat/` in the same development cycle.

`web/src/features/` mirrors `macos/Sources/Features/`:

```
web/src/
├── features/
│   ├── Chat/           — Chat sidebar, message list, composer, slash commands, @mention, steer mode
│   ├── IDE/            — File tree, tab bar, breadcrumbs, Monaco editor, status bar
│   ├── Agents/         — Agent dashboard, scheduled agents
│   ├── Terminal/       — xterm.js terminal (connects to libsmithers PTY via WebSocket)
│   ├── Settings/       — Preferences UI
│   └── Skills/         — Skills browser, activation
├── components/         — shadcn-solid primitives (Button, Dialog, Popover, etc.)
├── lib/
│   ├── api-client.ts   — HTTP REST client for libsmithers
│   ├── ws-client.ts    — WebSocket connection for real-time events (chat deltas, agent status, file changes)
│   ├── store.ts        — SolidJS reactive stores (createStore — mirrors AppModel/WorkspaceModel)
│   └── types.ts        — Hand-maintained TypeScript types (kept in sync with Zig/Swift by AI + e2e tests)
├── styles/
│   └── tokens.css      — CSS custom properties matching design.md section 2.1 (same as prototype)
└── tests/
    └── e2e/            — Playwright test suites (mirrors feature structure)
```

### 12A.3 Visual parity with native app

The web app should look **as close to the native app as possible**. The prototype (`prototype/`) is the design reference for **both** the native and web apps — same colors, same spacing, same layout, same component structure. The CSS custom properties (`--sm-base`, `--sm-surface1`, `--sm-accent`, etc.) from the prototype are used directly in the web app's `tokens.css`.

**Prototype lifecycle:** The `prototype/` directory is a frozen design reference. It will be **deleted** once the SolidJS web app is fully functional and has replaced it as the visual reference.

### 12A.4 Communication with libsmithers

The web app does NOT bundle or run libsmithers directly. It connects to the running libsmithers HTTP/WebSocket server (`src/http_server.zig`, interface #4 from section 2.6). **No authentication for now** — localhost only, internal use.

**HTTP REST API:**
- `POST /api/chat/send` — send a chat message
- `GET /api/chat/sessions` — list chat sessions
- `GET /api/workspace/files` — file tree
- `POST /api/workspace/open` — open a file
- `POST /api/agent/spawn` — spawn a sub-agent
- `POST /api/terminal/create` — create a PTY session
- etc. (same capability surface as the C API, MCP server, and CLI)

**WebSocket (real-time events):**
- `ws://localhost:<port>/ws` — streams events: chat deltas, agent status changes, file change notifications, turn completions.
- `ws://localhost:<port>/ws/terminal/<id>` — PTY I/O for xterm.js terminals.
- Mirrors the same event types as `CodexEvent` on the Swift side.

### 12A.5 Playwright testing

Playwright tests are a **primary reason** the web app exists. They provide end-to-end coverage of the libsmithers Zig core without requiring XCUITest:

```
web/tests/e2e/
├── chat.spec.ts          — Send message, receive response, verify streaming
├── chat-commands.spec.ts — Slash commands, @mentions, steer mode
├── file-tree.spec.ts     — Open workspace, browse files, open in editor
├── editor.spec.ts        — Edit file, save, verify persistence
├── terminal.spec.ts      — Open terminal, run command, verify output
├── agents.spec.ts        — Spawn agent, monitor progress, verify completion
├── jj.spec.ts            — VCS operations, snapshot creation, undo
└── skills.spec.ts        — Skill activation, skill-modified prompts
```

**Test strategy:** Playwright tests run against a real libsmithers instance (not mocks). This validates the full stack: SolidJS UI → HTTP/WebSocket → Zig core → Codex/JJ subprocesses. Combined with Zig unit tests (`zig build test`) and Swift XCUITests, this gives three layers of testing.

**CI integration:** `zig build playwright` starts the HTTP server, runs `pnpm exec playwright test`, and tears down.

### 12A.6 Build integration

- `zig build web` — runs `cd web && pnpm install && pnpm build`
- `zig build dev` includes the web build as a step
- `zig build playwright` — builds web app, starts HTTP server, runs Playwright tests
- The HTTP server serves the built web app's static files directly (no separate web server needed)
