# AI Integration

## 10.0 Orchestrator Architecture

Main chat = orchestrator ("top agent"). Has full app state context (workspace, running agents, settings, file tree). Answers directly OR delegates to sub-agents.

**Core flow:**
1. User msg → main chat (pane 0)
2. Orchestrator Codex interprets intent. Has **libsmithers MCP server** (injected at runtime) — same capabilities as command palette + CLI: open files, run terminals, search, read tree, spawn agents, change settings, etc.
3. Simple queries ("what's in this file?", "change theme to dark") → responds directly via MCP tools
4. Work tasks ("fix login bug", "add API tests") → spawns **sub-agent** (ephemeral Codex process, workspace-scoped tools only: filesystem + terminal, **NO MCP**)
5. **Sub-agents run YOLO (no approvals) to completion.** Execute task, apply to jj branch, complete.
6. **HITL = sub-agent completes → orchestrator asks → new sub-agent.** No pause/resume — complete → ask → new agent with updated context.
7. Sub-agent runs **hidden by default.** Status in agent dashboard. Work in background.
8. User can **unhide** → opens `.chat` tab in workspace panel (attach to background process).
9. Main chat sidebar dashboard shows all agent statuses. Active sorted top, past below (toggleable).
10. Sub-agent completes → changes enter merge queue (jj).

**Sub-agents hidden by default.** User's primary interaction = main chat. Sub-agents = background workers. Monitor via dashboard, open any to see full conversation.

**Codex session multiplexing.** Share **one Codex session** with multiplexed sub-sessions. Single `codex-app-server` process, orchestrator + all sub-agents communicate through it. Reduces overhead, enables context caching, simplifies lifecycle. Each sub-agent = logical session ID within shared connection.

**Orchestrator toolset = command palette = CLI = MCP server.** Unified capability surface.

| Tool | MCP method | CLI command | Command palette |
|------|-----------|-------------|-----------------|
| Open file | `open_file(path, line, col)` | `smithers-ctl open-file <path> --line N` | Cmd+P → select |
| Search workspace | `search_workspace(query)` | `smithers-ctl search <query>` | Cmd+Shift+F |
| Run terminal | `run_terminal(command, cwd)` | `smithers-ctl terminal --cwd PATH` | Cmd+` → type |
| Read file | `read_file(path)` | `smithers-ctl read <path>` | Open in editor |
| Write file | `write_file(path, content)` | `smithers-ctl write <path>` | Edit + Cmd+S |
| Get workspace state | `get_workspace_state()` | `smithers-ctl status` | Look at tree |
| Get JJ status | `get_jj_status()` | `smithers-ctl jj status` | Source tab |
| Spawn agent | `spawn_agent(task)` | `smithers-ctl agent spawn <task>` | "New Agent" |
| Cancel agent | `cancel_agent(id)` | `smithers-ctl agent cancel <id>` | Cancel row |
| Change setting | `change_setting(key, value)` | `smithers-ctl set <key> <value>` | Preferences |
| Get agent status | `get_agent_status(id)` | `smithers-ctl agent status <id>` | Dashboard |
| Show diff | `show_diff(content)` | `smithers-ctl diff show` | Open diff tab |

Sub-agents NO MCP — only standard Codex tools (file r/w, terminal) scoped to jj branch.

**Multiple sub-agents run in parallel.** Each gets own jj branch, multiplexed Codex session, hidden conversation. Orchestrator has global visibility via MCP.

**Project config files.** On workspace open, reads/respects:
- `AGENTS.md` — project agent instructions (Codex compat), injected into orchestrator
- `CLAUDE.md` — Claude Code project instructions, injected
- Skills — from `<workspace>/.agents/skills/`, `~/.agents/skills/`, injected per-session

Ensures compat with Codex CLI / Claude Code users — config carries over.

## 10.0.1 Codex Feature Parity

Full user-facing feature parity with Codex CLI. Reference implementation.

**Slash commands (type `/` in composer):**

| Command | Behavior |
|---------|----------|
| `/plan` | Plan mode — agent plans before executing. Inline args + pasted images. |
| `/review` | Code review — summarize working tree issues, focus on behavior + missing tests. |
| `/diff` | Inspect exact file changes from reviews. |
| `/fork` | Clone conversation → new chat session with fresh ID. Original intact. |
| `/new` | Fresh conversation, same session. |
| `/resume` | Resume saved session from picker. |
| `/status` | Show active model, approval policy, writable roots, token usage. |
| `/compact` | Summarize long conversations to free context. |
| `/mention` | Add file by path (e.g., `/mention src/lib/api.ts`). |
| `/init` | Create AGENTS.md for project config. |
| `/model` | Switch models. |

**@Mention (type `@` in composer):**
- `@` → autocomplete popup with workspace files
- Select → insert as context reference
- Referenced files persist across follow-up turns
- MVP: files + open tabs. Future: symbols, functions, agent names.

**Steer mode (real-time agent interaction — match Codex CLI):**
- Agent running → type in composer → **Enter** → send mid-turn steering message
- **Tab** → queue follow-up for next turn (after agent finishes)
- Mid-turn corrections without stopping agent
- Study Codex CLI source for exact behavior. In-process Zig API → call steering function directly. If no steering API → inject follow-up into conversation context.

**Skills (invoke `$skill-name` or via Skills button):**
- Reusable instruction bundles with SKILL.md
- Explicit: `$skill-name` in composer
- Implicit: Codex auto-selects based on context
- Browse, install, activate/deactivate per session
- `AGENTS.md` at project root = project-wide config

**Thread management:**
- Thread = durable container (many turns)
- Turn = one user msg → agent response
- Fork, resume, compact ops on threads
- All threads auto-saved (SQLite, not JSON)
- History syncs across sessions

**Execution mode — YOLO only:**
- No approvals, no sandbox, unrestricted. Agent reads/writes any file, runs any command, no confirmation.
- Intentional for power users.
- Future: sandboxing + per-action approval. MVP: user's responsibility to sandbox environment.
- `/permissions` NOT implemented in MVP — remove from slash table.

**Model selection:**
- Switch via `/model` or settings
- MVP: Codex (OpenAI) only. Future: Claude, others (issue 004).

**Multi-provider support (MVP lower priority — issue 004):**
- Architecture must support multiple backends, not just Codex
- MVP ships Codex (fork) as primary. Claude Code + OpenCode = MVP but lower priority — implement end of MVP.
- **Unified Agent Protocol Adapter** abstracts backend → swap Codex for Claude Code (WebSocket MCP) or OpenCode (ACP) = backend change, not UI change.
- Adapter interface: send msg, receive events (deltas, commands, file changes, turn complete), manage threads.

## 10.0.2 Background + Scheduled Agents (MVP — issue 007)

Background agents = core (already in 10.0). Scheduled agents extend:

**Scheduled agents:**
- Config agents on cron schedules (e.g., "code review every morning")
- Config in SQLite (not TOML — v1 spec stale)
- `SchedulerService` (Zig: `src/scheduler.zig`) manages triggers
- Schedule fires → spawn sub-agent via orchestrator with configured prompt/skill
- Results in agent dashboard
- **Scheduler runs in-app.** Background-capable macOS app (stays alive when "closed" — menu bar icon). Scheduled agents fire while backgrounded.
- **Future: cloud scheduling.** MVP = local only.

**Review queue:**
- Scheduled agent results enter review queue (agent dashboard)
- User reviews + approves/rejects before applying to main workspace
- NOT merge queue (post-MVP) — simpler: list of completed scheduled runs awaiting review.

## 10.1 CodexService

Codex **linked into libsmithers** as static lib — not child process. `src/codex_client.zig` calls Codex Zig API (from `submodules/codex/`) directly. Swift `CodexService` = thin wrapper around libsmithers C API.

**Session multiplexing (study Codex source):** In-process → multiplexing simpler. Orchestrator + all sub-agents communicate through same linked Codex lib. Each sub-agent = logical session within shared instance.

**Orchestrator session (main chat):**
- Init on app start via Codex Zig API
- Connected to **libsmithers MCP server** (injected at runtime) → controls IDE
- Full visibility: workspace state, running agents, settings
- Job: interpret intent, delegate to sub-agents

**Sub-agent sessions:**
- Created by orchestrator (Codex Zig API) as new sessions in shared instance
- NO MCP — only filesystem + terminal
- Scoped to jj workspace branch
- Run hidden until user opens tab

**Startup sequence (Zig-managed):**
1. Init Codex Zig API (in-process from `submodules/codex/`)
2. Pass storage callbacks (`src/storage.zig` + `pkg/sqlite/`) — replace Codex JSONL with shared SQLite
3. Attach MCP server endpoint (runtime injection) for orchestrator
4. Init orchestrator session via Codex Zig API
5. If thread ID exists (SQLite lookup) → resume, else new
6. Register event callbacks — Codex → libsmithers (chat deltas, commands, file changes, turn completions)
7. Sub-agent sessions created on-demand via Codex Zig API

**Event distribution:** `CodexService` exposes `events: AsyncStream<CodexEvent>`. `AppModel` consumes, routes to sub-models:

```swift
// In AppModel, after starting CodexService:
Task {
    for await event in services.codex!.events {
        switch event {
        case .agentMessageDelta(let turnId, let text):
            chat.appendDelta(text: text, turnId: turnId)
        case .commandStarted(let turnId, let itemId, let command, let cwd):
            chat.appendCommand(turnId: turnId, itemId: itemId, command: command, cwd: cwd)
        case .fileChange(let turnId, let item):
            chat.appendDiffPreview(turnId: turnId, item: item)
            handleAIFileChange(item)
        case .turnCompleted(let turnId, _):
            chat.completeTurn(turnId: turnId)
            workspace?.jj.autoSnapshot()
        // ...
        }
    }
}
```

## 10.2 Codex Zig API (In-Process, No JSON-RPC)

Codex fork linked as static lib → **NO JSON-RPC**. `src/codex_client.zig` calls Codex Zig API directly — function calls, not serialized msgs.

- **Calls:** Direct Zig function calls into Codex lib (send msg, create session, manage threads)
- **Events:** Codex → libsmithers via Zig callback function pointers (chat deltas, commands, file changes, turn completions)
- **Error handling:** Zig error unions, not JSON-RPC codes
- **Types:** Zig structs shared between `src/codex_client.zig` + Codex fork Zig API layer. Defined once in fork, imported by libsmithers.

**Note:** `JSONRPCTransport` may exist for other backends (Claude Code, OpenCode) using JSON-RPC. Primary Codex integration = in-process Zig API.

## 10.2.1 Shared SQLite (Codex Fork Zig API + Storage Callbacks)

Fork shares **same SQLite** as Smithers (`~/Library/Application Support/Smithers/smithers.db`). Wraps Codex in Zig API, accepts storage callbacks — Codex doesn't know SQLite.

**Architecture:**
1. Fork compiles Rust as **static lib** (not binary). Thin Zig wrapper (`submodules/codex/build.zig`) exposes **Zig-native API** libsmithers calls. ONLY thing fork does.
2. libsmithers (`src/codex_client.zig`) calls Codex Zig API — create sessions, send msgs, manage threads — direct Zig function calls. No JSON-RPC, pipes, child process.
3. Init Codex Zig API → pass **storage callback functions** (Zig function pointers) for persistence: save_session, load_session, list_threads, delete_thread, etc. Implemented in `src/storage.zig` + `pkg/sqlite/`.
4. Codex calls callbacks for persistence. Doesn't know it's SQLite — just calls.
5. Swift (GRDB.swift) accesses same db for UI queries. SQLite WAL mode → concurrent access from Zig + Swift.

**Why Zig API wrapper (not JSON-RPC, not C FFI vtable):**
- **In-process** — No child overhead, IPC latency, serialization. Codex = linked lib within libsmithers.
- **Zig-native** — Idiomatic Zig. libsmithers calls like any Zig module. Error handling, memory, lifetime = Zig-native.
- **Minimal fork** — Zig wrapper on Rust code. Rust internals mostly untouched. Easy rebase on upstream.
- **Single artifact** — Codex compiles into libsmithers. One binary, no external runtime deps.
- **Storage callbacks** — Clean dependency injection. Codex calls callbacks; we provide SQLite impl. Pattern = libghostty callbacks.

**Fork maintenance:** Minimal, rebased (not merged) on upstream Codex releases. Zig API wrapper isolated from Rust internals → upstream changes rarely conflict.

**Schema ownership:** Codex (via callbacks) owns tables (sessions, threads, msgs, items). Smithers owns tables (workspace state, prefs, schedules, snapshots). Both coexist. Migrations versioned independently.

## 10.3 SmithersCtlInterpreter

Parses CLI strings from AI, dispatches to IDE actions.

Commands: `open`, `terminal`, `diff show`, `overlay`, `dismiss-overlay`, `webview open/close/eval/url`.

**Arg parsing:** Manual tokenizer (splits whitespace, respects quotes). Switch on first token → handler methods. Supports vim-style `+line:column`.

**Integration:** v2 receives `AppModel` ref (not `WorkspaceState`). Calls `appModel.showInEditor()`, `appModel.workspace?.tabs.openTerminal()`, etc.

## 10.4 CompletionService

Separate from CodexService. Editor ghost text completions.

- 300ms debounce after keystroke
- Send request: file path, cursor, surrounding context
- Stream partial results → update ghost text overlay
- Cancellation: each keystroke increments generation counter. Stale responses discarded.

## 10.5 Chat History Persistence

`ChatHistoryStore` uses **SQLite (GRDB.swift)** at `~/Library/Application Support/Smithers/smithers.db`.

- **Tables:** `sessions` (id, title, workspace_path, thread_id, created_at, updated_at), `messages` (id, session_id, role, kind, content, timestamp, metadata_json), `images` (id, message_id, filename, data_hash)
- **Images** stored as files at `~/Library/Application Support/Smithers/images/<hash>`, referenced by hash
- **Migrations** via GRDB's `DatabaseMigrator`
- **Save:** 1s debounce after msg changes. GRDB write transactions for atomicity.
- **Load:** app launch (all sessions) + workspace open (workspace-specific). Graceful degradation on migration fail.
- **Cleanup:** unused images pruned periodically.
