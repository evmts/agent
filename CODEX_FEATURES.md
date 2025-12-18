# Codex Feature Inventory

Complete feature inventory of OpenAI's Codex CLI agent. This document catalogs all features discovered through codebase exploration for comparison purposes.

---

## 1. Core Tools

### File Operations

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| **read_file** | Read files with line number support | `file_path`, `offset`, `limit`, `mode` (slice/indentation) |
| **list_dir** | List directory entries with pagination | `dir_path`, `offset`, `limit`, `depth` |
| **grep_files** | Regex search sorted by mtime | `pattern`, `include` (glob), `path`, `limit` |

**Subfeatures:**
- Indentation-aware block reading with header/sibling inclusion
- 1-indexed line/entry numbering
- Recursive directory traversal with depth control
- Results sorted by modification time (most recent first)

### File Modification

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| **apply_patch** | Multi-file patches | `input` (patch text) |

**Subfeatures:**
- Two variants: freeform text and structured parameters
- Operations: add, update, delete, move files
- Context-aware matching with `@@` markers
- Lark grammar-based diff parsing

### Shell Execution

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| **shell** | Array-form commands (cross-platform) | `command[]`, `workdir`, `timeout_ms`, `sandbox_permissions`, `justification` |
| **shell_command** | String-form commands (user's shell) | `command`, `workdir`, `login`, `timeout_ms` |
| **unified_exec** | Interactive PTY sessions | `cmd`, `workdir`, `shell`, `login`, `yield_time_ms`, `max_output_tokens` |
| **write_stdin** | Write input to running process | `session_id`, `chars`, `yield_time_ms`, `max_output_tokens` |

**Subfeatures:**
- Platform-aware: Bash on Unix, PowerShell on Windows
- Interactive terminal session management
- Multiple concurrent sessions with write_stdin capability
- Sandbox permission escalation with justification

### Image/Media

| Tool | Description |
|------|-------------|
| **view_image** | Attach local images for vision analysis |

### Planning

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| **update_plan** | Task tracking | `explanation`, `plan[]` with step/status |

**Subfeatures:**
- Status: pending, in_progress, completed
- Maximum one step in_progress at a time
- Plan displayed in TUI

### Web

| Tool | Description |
|------|-------------|
| **web_search** | Feature-gated web search |

### MCP Integration

| Tool | Description |
|------|-------------|
| **list_mcp_resources** | List resources from MCP servers |
| **list_mcp_resource_templates** | List parameterized resource templates |
| **read_mcp_resource** | Read specific resource by URI |
| **mcp_tools** | Dynamic tool invocation from MCP servers |

---

## 2. CLI Commands

### Interactive Commands
```
codex                        Launch interactive TUI (default)
codex "prompt"               Launch TUI with initial prompt
codex resume                 Display session picker UI
codex resume --last          Resume most recent session
codex resume <SESSION_ID>    Resume specific session by UUID
```

### Non-Interactive Commands
```
codex exec / codex e         Run non-interactively in automation mode
codex review                 Run code review non-interactively
```

### Authentication
```
codex login                  Manage login
codex login --with-api-key   Read API key from stdin
codex login --device-auth    Use device code flow
codex login status           Show login status
codex logout                 Remove stored credentials
```

### Code Application
```
codex apply / codex a        Apply latest diff as git apply to working tree
```

### MCP Management
```
codex mcp                    Run Codex as MCP server and manage servers
codex mcp add <name> -- <cmd>  Add MCP server
codex mcp list               List servers (pretty or JSON)
codex mcp get <name>         Show server details
codex mcp remove <name>      Remove server
codex mcp login <name>       OAuth login for HTTP servers
codex mcp logout <name>      OAuth logout
codex mcp-server             Run Codex as MCP server (stdio transport)
```

### Sandbox/Security
```
codex sandbox                Run commands in sandbox
codex sandbox macos          Run under Seatbelt (macOS)
codex sandbox linux          Run under Landlock+seccomp (Linux)
codex sandbox windows        Run under Windows restricted token
codex execpolicy check       Check policy files against commands
```

### Cloud/Experimental
```
codex cloud                  Browse Codex Cloud tasks
codex app-server             Run app server or tooling
codex app-server generate-ts Generate TypeScript bindings
codex app-server generate-json-schema  Generate JSON Schema
```

### Utility
```
codex completion <shell>     Generate shell completions (bash/zsh/fish)
codex features               Inspect feature flags
```

### Global Flags
```
-m / --model <MODEL>         Specify model
-a / --ask-for-approval      Require approval for actions
-C / --cd <DIR>              Set working directory
--add-dir <DIR>              Expose additional writable directories
-i / --image <FILES>         Attach images (comma-separated)
--enable <FEATURE>           Enable feature flag
--disable <FEATURE>          Disable feature flag
-c / --config <KEY=VALUE>    Override config
```

---

## 3. Interactive Slash Commands

| Command | Description |
|---------|-------------|
| `/model` | Choose model and reasoning effort |
| `/approvals` | Configure what Codex can do without approval |
| `/review` | Review current changes and find issues |
| `/new` | Start new chat during conversation |
| `/resume` | Resume old chat |
| `/init` | Create AGENTS.md file with instructions |
| `/compact` | Summarize conversation to prevent context limit |
| `/undo` | Ask Codex to undo a turn |
| `/diff` | Show git diff (including untracked files) |
| `/mention` | Mention a file (file search) |
| `/status` | Show session configuration and token usage |
| `/mcp` | List configured MCP tools |
| `/experimental` | Open experimental features menu |
| `/skills` | Browse and insert skills |
| `/logout` | Log out of Codex |
| `/quit, /exit` | Exit Codex |
| `/feedback` | Send logs to maintainers |

---

## 4. TUI Features

### Interactive Features
- **@ File Search** - Type `@` to fuzzy-search filenames in composer
- **Esc-Esc Message Editing** - Backtrack through message history, fork conversations
- **Image Paste** - Paste images directly (Ctrl+V / Cmd+V)
- **Command Palette** - `/` commands with autocomplete

### Session Management
- Create new sessions
- List all sessions
- Switch between sessions
- Resume previous sessions
- Fork conversation from any point

### Visual Features
- Terminal animations (configurable)
- Desktop notifications (agent-turn-complete, approval-requested)
- Spinner animation during processing
- Syntax highlighting for responses
- Color styling for roles (user/agent)

### UI Components
- Multi-line text input
- Markdown rendering
- Diff visualization
- Tool call and result display
- Status line with mode indicator

---

## 5. Configuration System

### Model Selection
| Key | Description |
|-----|-------------|
| `model` | Model to use (default: gpt-5.1-codex-max) |
| `review_model` | Model for /review feature |
| `model_provider` | Provider ID from model_providers map |
| `model_context_window` | Context window size in tokens |
| `tool_output_token_limit` | Token budget for tool outputs |
| `model_auto_compact_token_limit` | Auto-compaction limit |

### Reasoning (Responses API)
| Key | Values |
|-----|--------|
| `model_reasoning_effort` | minimal, low, medium (default), high, xhigh |
| `model_reasoning_summary` | auto (default), concise, detailed, none |
| `model_verbosity` | low, medium (default), high |
| `model_supports_reasoning_summaries` | boolean |
| `model_reasoning_summary_format` | none (default), experimental |

### Approval Policy
| Key | Values |
|-----|--------|
| `approval_policy` | untrusted, on-failure, on-request (default), never |

### Sandbox Modes
| Key | Values |
|-----|--------|
| `sandbox_mode` | read-only (default), workspace-write, danger-full-access |
| `sandbox_workspace_write.writable_roots` | Extra writable directories |
| `sandbox_workspace_write.network_access` | Allow outbound network |

### Shell Environment Policy
| Key | Description |
|-----|-------------|
| `shell_environment_policy.inherit` | Template: all (default), core, none |
| `shell_environment_policy.exclude` | Glob patterns to remove |
| `shell_environment_policy.include_only` | Whitelist patterns |
| `shell_environment_policy.set` | Explicit key/value overrides |

### Model Providers
```toml
[model_providers.<id>]
name = "Display name"
base_url = "API base URL"
env_key = "Environment variable for API key"
wire_api = "chat" or "responses"
query_params = { api-version = "..." }
http_headers = { ... }
env_http_headers = { ... }
request_max_retries = 4
stream_max_retries = 5
stream_idle_timeout_ms = 300000
```

### OSS/Local Models
| Key | Values |
|-----|--------|
| `oss_provider` | lmstudio, ollama (default) |

### History
| Key | Description |
|-----|-------------|
| `history.persistence` | save-all (default), none |
| `history.max_bytes` | Maximum history size (oldest trimmed) |

### File Opener (IDE Integration)
| Key | Values |
|-----|--------|
| `file_opener` | vscode (default), vscode-insiders, windsurf, cursor, none |

### Project Documentation
| Key | Description |
|-----|-------------|
| `project_doc_max_bytes` | Max bytes from AGENTS.md (default: 32KB) |
| `project_doc_fallback_filenames` | Fallback files when AGENTS.md missing |

### Authentication
| Key | Values |
|-----|--------|
| `cli_auth_credentials_store` | file (default), keyring, auto |
| `mcp_oauth_credentials_store` | auto, file, keyring |
| `forced_login_method` | chatgpt, api |
| `forced_chatgpt_workspace_id` | Workspace ID restriction |

### Instruction Overrides
| Key | Description |
|-----|-------------|
| `developer_instructions` | Additional user instructions |
| `instructions` | Legacy base instructions override |
| `compact_prompt` | Compaction prompt override |
| `experimental_instructions_file` | Override built-in instructions with file |
| `experimental_compact_prompt_file` | Load compact prompt from file |

### TUI Settings
| Key | Description |
|-----|-------------|
| `tui.notifications` | Desktop notifications (boolean or filtered list) |
| `tui.animations` | Enable terminal animations |
| `tui.disable_paste_burst` | Disable burst-paste detection |
| `notify` | External notifier program |

### Observability
| Key | Description |
|-----|-------------|
| `hide_agent_reasoning` | Suppress reasoning events |
| `show_raw_agent_reasoning` | Show raw chain-of-thought |
| `check_for_update_on_startup` | Check for updates |

### Ghost Snapshots
| Key | Description |
|-----|-------------|
| `ghost_snapshot.disable_warnings` | Disable warnings |
| `ghost_snapshot.ignore_large_untracked_files` | Exclude files > N bytes |
| `ghost_snapshot.ignore_large_untracked_dirs` | Ignore dirs with N+ files |

### Profiles
```toml
profile = "profile_name"  # Active profile

[profiles.<name>]
# Override any root-level setting
model = "..."
approval_policy = "..."
```

### Project Trust
```toml
[projects.<path>]
trust_level = "trusted"
```

---

## 6. Feature Flags

| Flag | Default | Stage | Description |
|------|---------|-------|-------------|
| `unified_exec` | false | Experimental | PTY-backed exec tool |
| `rmcp_client` | false | Experimental | OAuth for HTTP MCP servers |
| `apply_patch_freeform` | false | Beta | Freeform apply_patch tool |
| `view_image_tool` | true | Stable | view_image tool |
| `web_search_request` | false | Stable | Model web searches |
| `ghost_commit` | false | Experimental | Ghost commit each turn |
| `enable_experimental_windows_sandbox` | false | Experimental | Windows sandbox |
| `tui2` | false | Experimental | TUI v2 implementation |
| `skills` | false | Experimental | Skill discovery/injection |
| `exec_policy` | - | - | Execpolicy enforcement |
| `shell_tool` | - | Stable | Default shell tool |
| `model_warnings` | - | Stable | Tool misuse warnings |
| `parallel_tool_calls` | - | Experimental | Parallel tool calls |
| `remote_compaction` | - | Experimental | Remote compaction |
| `remote_models` | - | Experimental | Refresh remote models |
| `shell_snapshot` | - | Experimental | Shell snapshotting |

---

## 7. MCP Support

### Transports
- **STDIO** - Standard input/output
- **Streamable HTTP** - HTTP with OAuth support

### Server Configuration
```toml
[mcp_servers.<server-id>]
# STDIO Transport
command = "launcher command"
args = ["arg1", "arg2"]
env = { KEY = "value" }
env_vars = ["VAR_TO_WHITELIST"]
cwd = "working directory"

# HTTP Transport
url = "MCP server URL"
bearer_token_env_var = "ENV_VAR_WITH_TOKEN"
http_headers = { ... }
env_http_headers = { ... }

# Common
enabled = true
startup_timeout_sec = 10
tool_timeout_sec = 60
enabled_tools = ["tool1", "tool2"]
disabled_tools = ["tool3"]
```

### Features
- Codex as MCP client (connect to external servers)
- Codex as MCP server (experimental JSON-RPC interface)
- OAuth support via rmcp_client feature flag
- Dynamic tool discovery and invocation

---

## 8. Security/Sandboxing

### Platform Sandboxes
| Platform | Technology | Description |
|----------|------------|-------------|
| macOS | Seatbelt | Security policies |
| Linux | Landlock + seccomp | Capability-based sandbox |
| Windows | Restricted Token | Process isolation |

### Execpolicy
- Starlark rule-based command approval
- Location: `~/.codex/rules/*.rules`
- Pattern: `prefix_rule(pattern=..., decision="allow|prompt|forbidden", ...)`
- CLI: `codex execpolicy check --rules <file> <command>`

### Dangerous Command Detection
- Built-in patterns for dangerous commands
- Pattern-based blocking
- Justification required for escalation

---

## 9. Observability

### OpenTelemetry
```toml
[otel]
environment = "dev"
exporter = "none" | "otlp-http" | "otlp-grpc"
log_user_prompt = false

[otel.exporter."otlp-http"]
endpoint = "https://otel.example.com/v1/logs"
protocol = "binary" | "json"
headers = { "x-otlp-api-key" = "${OTLP_TOKEN}" }
```

### Telemetry Events
- `codex.conversation_starts` - Session start
- `codex.api_request` - Outbound API requests
- `codex.sse_event` - SSE streaming events
- `codex.user_prompt` - User input (redacted by default)
- `codex.tool_decision` - Approval decisions
- `codex.tool_result` - Tool execution results

### External Notifications
- Webhook-style program invocation
- JSON payload with event details
- Event types: agent-turn-complete, approval-requested

---

## 10. Extensibility

### Skills
- Location: `~/.codex/skills/**/SKILL.md`
- Format: YAML frontmatter + Markdown body
- Usage: `$<skill-name>` or `/skills` command
- Feature flag: `skills` (disabled by default)

### Execpolicy Rules
- Starlark format
- Pattern-based command approval
- Interactive approval creates rules

### Project Instructions (AGENTS.md)
- Global: `~/.codex/AGENTS.md`
- Project: Directory hierarchy (root to cwd)
- Override: `AGENTS.override.md`
- Fallbacks: Configurable via `project_doc_fallback_filenames`

### Custom Slash Commands
- Location: `~/.codex/prompts/*.md`
- Usage: `/prompts:<name>` or `/` with name
- Can override built-in commands

---

## 11. Session Management

### Session Operations
- Create, get, list, update, delete sessions
- Fork session from parent at specific message
- Resume previous sessions
- Abort active processing

### State Tracking
- Message history persistence
- Turn-based diff tracking
- Ghost snapshots per turn
- Revert/unrevert capabilities

### Session Fields
- id, projectID, directory, title
- version, timestamps, parentID
- summary metadata
- bypass_mode flag

---

## 12. Authentication

### Methods
- **ChatGPT Auth** - Device code flow
- **API Key Auth** - Direct key entry
- **Keyring Storage** - OS-native (macOS Keychain, Windows Credential Manager, Linux Secret Service)
- **OAuth for MCP** - Server-specific OAuth flows

### Configuration
- `cli_auth_credentials_store` - file/keyring/auto
- `forced_login_method` - chatgpt/api
- `chatgpt_base_url` - Custom ChatGPT endpoint

---

## Architecture Summary

### Rust Workspace Structure
- **48+ crates** in monolithic workspace
- **Core**: Agent logic, tools, MCP, sandboxing
- **CLI**: Command-line interface and dispatch
- **TUI**: Interactive terminal UI (Ratatui)
- **Protocol**: Data structures and types
- **Utils**: Shared utilities, sandboxing, git

### Key Technologies
- **Tokio** - Async runtime
- **Ratatui** - TUI framework
- **Axum** - Web server (app-server)
- **Tree-sitter** - Code parsing
- **OpenTelemetry** - Observability
- **Landlock/Seatbelt** - Sandboxing

### Design Patterns
- State machine for conversation management
- Event-driven TUI with async events
- Plugin architecture via MCP
- Sandbox-first command execution
- Configuration-driven behavior
