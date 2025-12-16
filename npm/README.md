# @tevm/agent

AI agent with Claude integration - terminal UI and API server.

## Installation

```bash
npm install -g @tevm/agent
```

Or run directly with npx:

```bash
npx @tevm/agent
```

## Requirements

- **ANTHROPIC_API_KEY** environment variable must be set
- macOS (arm64, x64) or Linux (arm64, x64)

## Usage

```bash
# Start the agent TUI
agent

# The TUI includes an embedded server - no separate setup needed
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key (required) | - |
| `ANTHROPIC_MODEL` | Model ID | `claude-sonnet-4-20250514` |

## More Information

See the [GitHub repository](https://github.com/williamcory/agent) for full documentation.

## License

MIT
