# Unimplemented Features from Codex

Features that Codex has which are **not implemented** in our agent. This list excludes features that are already work-in-progress in `prompts/`.

---

## WIP Features (Excluded from this list)

The following are already being worked on and are excluded from the gap analysis:

| Prompt | Feature |
|--------|---------|
| 18 | Patch tool (multi-file patches) |
| 20 | Bypass mode backend |
| 22 | Runtime approval prompts (ask/allow/deny) |
| 23 | Task delegation to sub-agents |
| 24 | File modification tracking (mtime) |
| 25 | Search context lines (-A/-B/-C) |
| 26 | Search pagination (offset/head_limit) |
| 27 | Multiline pattern matching |
| 29 | Project-aware LSP analysis |

---

## CLI Commands

### Missing Commands

| Command | Description | Priority |
|---------|-------------|----------|
| `exec / e` | Non-interactive automation mode | High |
| `review` | Non-interactive code review | Medium |
| `apply / a` | Apply latest diff as git apply | High |
| `login / logout` | Dedicated authentication commands | Medium |
| `mcp add/list/get/remove` | Full MCP server management | Medium |
| `sandbox` | Run commands directly in sandbox | Low |
| `execpolicy check` | Policy rule checking | Low |
| `completion <shell>` | Shell completion generation (bash/zsh/fish) | Low |
| `features` | Inspect feature flags | Low |

---

## Tools

### Missing Tools

| Tool | Description | Priority |
|------|-------------|----------|
| `list_dir` with depth/pagination | We only have basic listing; Codex has depth, offset, limit | Medium |
| `unified_exec` + `write_stdin` | Interactive PTY sessions with stdin input | High |
| `update_plan` | Agent-managed task planning (different structure than todowrite) | Low |

### Tool Enhancements Needed

| Current Tool | Missing Feature |
|--------------|-----------------|
| `read_file` | Indentation-aware block reading mode |
| `grep` | Results sorted by mtime (most recent first) |

---

## TUI Features

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **@ File Search** | Fuzzy filename search in composer (type `@`) | High |
| **Esc-Esc Backtrack Mode** | Edit message history, fork from any point | Medium |
| **Image Paste** | Paste images directly (Ctrl+V/Cmd+V) | Medium |
| **Desktop Notifications** | System notifications for agent-turn-complete, approval-requested | Low |
| **Animations** | Terminal animations (configurable) | Low |
| **Session Forking** | Fork conversation from any message | Medium |

---

## Slash Commands

### Missing Commands

| Command | Description | Priority |
|---------|-------------|----------|
| `/model` | Switch model and reasoning effort | High |
| `/approvals` | Configure approval requirements | Medium |
| `/review` | In-session code review | Medium |
| `/init` | Create AGENTS.md file | Low |
| `/compact` | Manual context compaction | High |
| `/undo` | Undo turns | Medium |
| `/diff` | Show git diff in session | Medium |
| `/mention` | @ file mention helper | Low |
| `/experimental` | Experimental features menu | Low |
| `/skills` | Browse/insert skills | Low |
| `/feedback` | Send logs to maintainers | Low |

---

## Configuration

### Missing Configuration Options

| Category | Options | Priority |
|----------|---------|----------|
| **Model Reasoning** | reasoning_effort, reasoning_summary, verbosity | Medium |
| **Sandbox Modes** | read-only, workspace-write, full-access levels | High |
| **Shell Environment** | inherit, exclude, include_only, set policies | Medium |
| **Custom Providers** | base_url, env_key, wire_api, headers | Medium |
| **OSS Models** | LM Studio, Ollama integration | Medium |
| **History Config** | max_bytes, persistence modes | Low |
| **File Opener** | IDE deep links (VSCode, Cursor, Windsurf) | Low |
| **Instruction Overrides** | developer_instructions, instruction files | Low |
| **Ghost Snapshots** | Per-turn ghost commits | Low |
| **Profiles** | Named configuration presets | Low |
| **Project Trust** | Per-path trust levels | Low |

---

## Security

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **macOS Seatbelt** | Security policies for macOS | Medium |
| **Linux Landlock** | Capability-based sandbox for Linux | Medium |
| **Windows Sandbox** | Restricted token sandbox for Windows | Low |
| **Execpolicy** | Starlark rule engine for command approval | Medium |
| **Credential Keyring** | OS-native credential storage (Keychain, Credential Manager) | Low |

---

## Observability

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **OpenTelemetry** | Full OTEL integration with OTLP HTTP/gRPC export | Low |
| **Telemetry Events** | Structured event logging (api_request, tool_decision, etc.) | Low |
| **External Notifications** | Webhook-style program invocation | Low |
| **Reasoning Display** | Options to show/hide raw reasoning | Low |

---

## Extensibility

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Skills System** | Custom skill files with YAML frontmatter | Medium |
| **Execpolicy Rules** | Starlark-based command approval rules | Medium |
| **Custom Slash Commands** | ~/.codex/prompts/*.md files for custom commands | Medium |
| **AGENTS.md Hierarchy** | Directory-level instruction inheritance | Low |
| **AGENTS.override.md** | Override file for directory-specific instructions | Low |

---

## Authentication

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Device Code Flow** | ChatGPT-style login with device code | Low |
| **Keyring Storage** | OS credential managers (Keychain, Credential Manager, Secret Service) | Low |
| **OAuth for MCP** | MCP server OAuth flows | Low |
| **Forced Login Methods** | Enforce chatgpt/api authentication | Low |

---

## Session Features

### Missing Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Ghost Commits** | Per-turn git commits for tracking | Medium |
| **Turn Diff Tracking** | Track file changes per turn | Medium |
| **Conversation Forking** | Fork from any message in history | Medium |
| **History Compaction** | Auto/manual context compression | High |

---

## Feature Flags System

### Missing Capability

Our agent lacks a feature flag system. Codex has:

| Flag Type | Examples |
|-----------|----------|
| Experimental | unified_exec, tui2, skills, ghost_commit |
| Beta | apply_patch_freeform |
| Stable | view_image_tool, shell_tool |

This allows gradual rollout and testing of features.

---

## Priority Summary

### High Priority (Core Functionality)

1. `exec` command - Non-interactive automation mode
2. `apply` command - Apply diffs to working tree
3. `/compact` - Manual context compaction
4. `/model` - Model switching in session
5. Sandbox modes - read-only, workspace-write levels
6. `unified_exec` - Interactive PTY sessions
7. @ File Search - Fuzzy filename search in TUI
8. History compaction - Auto/manual context compression

### Medium Priority (Enhanced UX)

1. `/undo` - Undo turns
2. `/diff` - Show git diff
3. `/review` - In-session code review
4. Esc-Esc backtrack - Message history editing
5. Session forking - Fork from any point
6. Image paste - Direct paste support
7. Ghost commits - Per-turn git commits
8. Turn diff tracking
9. Skills system
10. Custom slash commands
11. Execpolicy rules
12. Custom model providers
13. OSS model support (LM Studio, Ollama)

### Low Priority (Nice to Have)

1. Desktop notifications
2. Terminal animations
3. Shell completion generation
4. Feature flags system
5. OpenTelemetry integration
6. Keyring credential storage
7. File opener IDE integration
8. Configuration profiles
9. Project trust levels
10. AGENTS.md hierarchy
11. OAuth for MCP
12. Platform-specific sandboxes

---

## Implementation Notes

When implementing these features, refer to:

- **Codex source**: `/Users/williamcory/agent/codex/codex-rs/`
- **Our agent**: `/Users/williamcory/agent/agent/`
- **Existing prompts**: `/Users/williamcory/agent/prompts/` (for WIP patterns)

Key reference files in Codex:
- CLI: `codex-rs/cli/src/main.rs`
- Tools: `codex-rs/core/src/tools/`
- Config: `codex-rs/core/src/config/`
- TUI: `codex-rs/tui/src/`
