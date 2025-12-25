# AI Agent System

AI agent functionality with direct Anthropic API client integration. Provides agent execution, tool registry, and streaming capabilities for the Plue server.

## Key Files

| File | Purpose |
|------|---------|
| `agent.zig` | Core agent execution (runAgent, streamAgent) |
| `client.zig` | Anthropic API client with streaming support |
| `registry.zig` | Agent configuration registry (build, explore, plan, general) |
| `types.zig` | Shared types (StreamEvent, AgentConfig, ToolContext) |
| `tools/` | Agent tool implementations (filesystem, github, grep, etc.) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      AI Agent Module                        │
│                                                             │
│  ┌────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │  Registry  │───▶│    Agent     │───▶│   Anthropic    │  │
│  │            │    │   Executor   │    │     Client     │  │
│  │ • build    │    │              │    │                │  │
│  │ • explore  │    │ • runAgent   │    │ • HTTP/2       │  │
│  │ • plan     │    │ • streamAgent│    │ • SSE stream   │  │
│  │ • general  │    │              │    │ • Tool calls   │  │
│  └────────────┘    └──────┬───────┘    └────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│                    ┌─────────────┐                          │
│                    │    Tools    │                          │
│                    │             │                          │
│                    │ • filesystem│                          │
│                    │ • github    │                          │
│                    │ • grep      │                          │
│                    │ • read_file │                          │
│                    │ • write_file│                          │
│                    │ • multiedit │                          │
│                    │ • web_fetch │                          │
│                    └─────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Agent Modes

| Mode | Description | Tools |
|------|-------------|-------|
| `build` | Code generation and modification | Full filesystem access |
| `explore` | Codebase exploration and analysis | Read-only access |
| `plan` | Workflow planning and validation | Limited tools |
| `general` | General-purpose assistance | Standard toolset |

## Usage

```zig
const ai = @import("ai/mod.zig");

// Stream agent with callbacks
const callbacks = ai.StreamCallbacks{
    .onToken = handleToken,
    .onToolCall = handleToolCall,
    .onToolResult = handleToolResult,
};

try ai.streamAgent(allocator, .{
    .agent_name = "build",
    .messages = messages,
    .callbacks = callbacks,
});
```
