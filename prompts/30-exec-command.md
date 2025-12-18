# Non-Interactive Exec Command

<metadata>
  <priority>high</priority>
  <category>cli-feature</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>tui/, server/, agent/</affects>
</metadata>

## Objective

Implement a non-interactive `exec` command that runs the agent in automation mode, accepting a prompt and returning results without requiring user interaction.

<context>
Codex provides `codex exec` / `codex e` for running the agent non-interactively. This is essential for:
- CI/CD pipelines
- Scripted automation
- Batch processing
- Integration with other tools
- Headless server environments

The exec command reads a prompt, runs the agent to completion, and outputs the result to stdout. It should support various output formats and handle errors gracefully.
</context>

## Requirements

<functional-requirements>
1. Add `exec` / `e` subcommand to CLI
2. Accept prompt via:
   - Command line argument: `agent exec "fix the bug in login.py"`
   - Stdin: `echo "fix the bug" | agent exec`
   - File: `agent exec -f prompt.txt`
3. Run agent to completion without user interaction
4. Output modes:
   - Default: Final assistant message only
   - `--full`: All messages including tool calls
   - `--json`: JSON-formatted output
   - `--stream`: Stream output as it's generated
5. Exit codes:
   - 0: Success
   - 1: Agent error
   - 2: Configuration/input error
6. Support all standard flags (`--model`, `-C`, etc.)
7. Timeout support with `--timeout` flag (default: no timeout)
8. Respect environment variables for API keys
</functional-requirements>

<technical-requirements>
1. Add `exec` subcommand to Go CLI in `tui/main.go`
2. Create `exec.go` module for exec logic
3. Implement non-interactive agent session:
   - Create session via API
   - Send prompt
   - Poll or stream for completion
   - Collect results
4. Handle SSE streaming for real-time output
5. Implement proper signal handling (SIGINT, SIGTERM)
6. Add timeout handling with context cancellation
7. Parse output into appropriate format
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/main.go` - Add exec subcommand
- `tui/exec.go` (CREATE) - Exec command implementation
- `tui/output.go` (CREATE) - Output formatting utilities
</files-to-modify>

<cli-interface>
```
agent exec [OPTIONS] [PROMPT]

Arguments:
  [PROMPT]  The prompt to send to the agent (reads from stdin if not provided)

Options:
  -f, --file <FILE>      Read prompt from file
  -m, --model <MODEL>    Model to use
  -C, --cd <DIR>         Working directory
  --timeout <SECONDS>    Timeout in seconds (0 = no timeout)
  --full                 Include all messages in output
  --json                 Output in JSON format
  --stream               Stream output in real-time
  --no-tools             Disable tool execution
  -q, --quiet            Suppress status messages
  -h, --help             Print help
```
</cli-interface>

<example-usage>
```bash
# Simple execution
agent exec "What files are in the current directory?"

# From stdin
echo "List all TODO comments" | agent exec

# From file with JSON output
agent exec -f prompt.txt --json > result.json

# With timeout and streaming
agent exec --timeout 300 --stream "Refactor the auth module"

# Quiet mode for scripting
result=$(agent exec -q "What is the main entry point?")
```
</example-usage>

<output-formats>
```go
// Default output - just the final message
fmt.Println(finalMessage.Content)

// JSON output format
type ExecOutput struct {
    Success    bool              `json:"success"`
    Messages   []Message         `json:"messages,omitempty"`
    FinalText  string            `json:"final_text"`
    ToolCalls  []ToolCall        `json:"tool_calls,omitempty"`
    Duration   float64           `json:"duration_seconds"`
    TokensUsed int               `json:"tokens_used,omitempty"`
    Error      string            `json:"error,omitempty"`
}

// Streaming output - one event per line
{"type": "text", "content": "I'll help you..."}
{"type": "tool_call", "name": "read_file", "args": {...}}
{"type": "tool_result", "content": "..."}
{"type": "done", "success": true}
```
</output-formats>

## Acceptance Criteria

<criteria>
- [ ] `agent exec "prompt"` runs agent non-interactively
- [ ] Prompt accepted from argument, stdin, or file
- [ ] Default output shows only final assistant message
- [ ] `--full` shows all messages including tool calls
- [ ] `--json` outputs structured JSON
- [ ] `--stream` outputs real-time streaming events
- [ ] `--timeout` properly cancels after specified duration
- [ ] Exit codes reflect success/failure appropriately
- [ ] Signal handling (Ctrl+C) works correctly
- [ ] Works in headless/non-TTY environments
- [ ] Error messages go to stderr, results to stdout
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test exec command with various inputs and output modes
4. Test timeout and signal handling
5. Test in CI-like environment (non-TTY)
6. Rename this file from `30-exec-command.md` to `30-exec-command.complete.md`
</completion>
