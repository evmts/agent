# Commands

Slash command parsing and registry for the TUI.

## Architecture

```
User Input: "/model sonnet-4"
       │
       ▼
┌────────────────────────┐
│  Parser (parser.zig)   │
│                        │
│  1. Validate /prefix   │
│  2. Extract cmd name   │
│  3. Parse arguments    │
│  4. Validate args      │
└──────────┬─────────────┘
           │
           │ ParsedCommand
           ▼
┌────────────────────────┐
│Registry (registry.zig) │
│                        │
│  - COMMANDS[]          │
│  - findCommand()       │
│  - Command metadata    │
└────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `parser.zig` | Parse slash commands from input strings |
| `registry.zig` | Command definitions, metadata, lookup |

## Command Structure

```zig
pub const Command = struct {
    name: []const u8,
    aliases: []const []const u8,
    args: []const Arg,
    description: []const u8,
    examples: []const []const u8,
};
```

## Parsing Flow

```
Input String
     │
     ▼
"/model sonnet-4"
     │
     ▼
ParsedCommand {
    command: &Command{ .name = "model" },
    args_str: "sonnet-4",
    raw_input: "/model sonnet-4",
}
     │
     ▼
Execute Command Handler
```

## Available Commands

| Command | Aliases | Args | Description |
|---------|---------|------|-------------|
| `new` | - | - | Create new session |
| `sessions` | `ls` | - | List sessions |
| `switch` | `sw` | `id` (required) | Switch session |
| `model` | `m` | `name` (optional) | List/set model |
| `effort` | `e` | `level` (optional) | Set reasoning effort |
| `status` | - | - | Show session status |
| `undo` | - | `n` (optional) | Undo turns |
| `clear` | - | - | Clear conversation |
| `help` | `h` | - | Show help |
| `quit` | `q`, `exit` | - | Exit TUI |

## Usage

```zig
const parser = @import("commands/parser.zig");

// Parse command
const result = parser.parse(allocator, "/model sonnet-4") catch |err| {
    // Handle errors: NotACommand, UnknownCommand, etc
};

// Access parsed data
const cmd_name = result.command.name;       // "model"
const first_arg = result.getArg(0);         // "sonnet-4"
const arg_count = result.argCount();        // 1
```

## Error Handling

```zig
pub const ParseError = error{
    NotACommand,        // Doesn't start with /
    UnknownCommand,     // Command not in registry
    MissingRequiredArg, // Required arg missing
    TooManyArgs,        // Too many args provided
    OutOfMemory,
};
```
