# Custom Slash Commands

Custom slash commands allow you to create reusable prompt templates via markdown files in `~/.agent/prompts/`.

## Quick Start

1. Create a markdown file in `~/.agent/prompts/`:
   ```bash
   mkdir -p ~/.agent/prompts
   cat > ~/.agent/prompts/review-pr.md << 'EOF'
   ---
   name: review-pr
   description: Review a pull request by number
   args:
     - name: pr_number
       required: true
       description: PR number to review
   ---

   Please review pull request #{{pr_number}}.

   Focus on:
   1. Code quality and style
   2. Potential bugs or edge cases
   3. Test coverage
   4. Documentation
   EOF
   ```

2. The command is automatically available via the API:
   ```bash
   # List all commands
   curl http://localhost:8000/command

   # Get command details
   curl http://localhost:8000/command/review-pr

   # Expand command with arguments
   curl -X POST http://localhost:8000/command/expand \
     -H "Content-Type: application/json" \
     -d '{"name": "review-pr", "args": ["123"]}'
   ```

3. Use in TUI (when integrated):
   ```
   /review-pr 123
   ```

## Command File Format

### Basic Command (No Arguments)

```markdown
---
name: commit
description: Create a conventional commit message
---
Look at the staged changes and create a conventional commit message.
Use format: <type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore
```

### Command with Required Arguments

```markdown
---
name: explain
description: Explain a piece of code
args:
  - name: file
    required: true
    description: Path to the file to explain
---
Please explain the code in {{file}}:
- What does it do?
- How does it work?
- Any notable patterns or issues?
```

### Command with Optional Arguments and Defaults

```markdown
---
name: test
description: Generate tests for a file
args:
  - name: file
    required: true
    description: Path to the file to test
  - name: framework
    default: pytest
    description: Test framework to use
---
Generate comprehensive tests for {{file}} using {{framework}}.
Include:
- Unit tests for each function
- Edge cases
- Error handling
```

## Variable Substitution

Commands support two types of variable substitution:

### Positional Arguments (`$1`, `$2`, etc.)

```markdown
Greet $1 from $2!
```

Usage: `/greet Alice Wonderland` → "Greet Alice from Wonderland!"

### Named Arguments (`{{variable}}`)

```markdown
Greet {{name}} from {{location}}!
```

Usage with positional: `/greet Alice Wonderland` → "Greet Alice from Wonderland!"
Usage with named: `expand_command("greet", kwargs={"name": "Alice", "location": "Wonderland"})`

## API Endpoints

### GET `/command`

Lists all available commands (built-in and custom).

**Response:**
```json
[
  {
    "name": "help",
    "description": "Show help information",
    "custom": false
  },
  {
    "name": "review-pr",
    "description": "Review a pull request by number",
    "custom": true
  }
]
```

### GET `/command/{name}`

Gets detailed information about a specific command.

**Response:**
```json
{
  "name": "review-pr",
  "description": "Review a pull request by number",
  "template": "Please review pull request #{{pr_number}}...",
  "args": [
    {
      "name": "pr_number",
      "required": true,
      "description": "PR number to review",
      "default": null
    }
  ],
  "file_path": "/Users/user/.agent/prompts/review-pr.md",
  "custom": true
}
```

### POST `/command/expand`

Expands a command template with provided arguments.

**Request:**
```json
{
  "name": "review-pr",
  "args": ["123"],
  "kwargs": {}
}
```

**Response:**
```json
{
  "expanded": "Please review pull request #123..."
}
```

### POST `/command/reload`

Reloads all custom commands from disk.

**Response:**
```json
{
  "count": 5
}
```

## Python API

```python
from config.commands import command_registry

# Load commands (happens automatically on first access)
command_registry.load_commands()

# List all commands
commands = command_registry.list_commands()

# Get a specific command
cmd = command_registry.get_command("review-pr")

# Expand command with positional arguments
expanded = command_registry.expand_command("review-pr", args=["123"])

# Expand command with named arguments
expanded = command_registry.expand_command(
    "review-pr",
    kwargs={"pr_number": "123"}
)

# Reload commands from disk
command_registry.reload()
```

## Best Practices

1. **Use Descriptive Names**: Choose clear, memorable command names
2. **Document Arguments**: Provide descriptions for all arguments
3. **Set Sensible Defaults**: For optional arguments, provide useful defaults
4. **Keep Commands Focused**: Each command should do one thing well
5. **Use Frontmatter**: Always include YAML frontmatter with metadata
6. **Test Commands**: Verify variable substitution works as expected

## Examples

### Code Review Command
```markdown
---
name: review
description: Comprehensive code review
args:
  - name: file
    required: true
---
Review {{file}} for:
1. Code quality and style
2. Potential bugs
3. Performance issues
4. Security concerns
5. Test coverage
```

### Bug Fix Command
```markdown
---
name: fix
description: Debug and fix an issue
args:
  - name: issue
    required: true
  - name: file
    required: false
---
Fix issue: {{issue}}
{{#if file}}Focus on file: {{file}}{{/if}}

Steps:
1. Reproduce the issue
2. Identify root cause
3. Implement fix
4. Add tests
5. Verify fix
```

### Documentation Command
```markdown
---
name: doc
description: Generate documentation
args:
  - name: file
    required: true
  - name: style
    default: google
---
Generate {{style}}-style documentation for {{file}}.
Include:
- Function/class descriptions
- Parameter documentation
- Return value documentation
- Usage examples
```

## Troubleshooting

### Command Not Found
- Ensure the file is in `~/.agent/prompts/`
- Check that the file has a `.md` extension
- Verify the YAML frontmatter is valid
- Try reloading: `POST /command/reload`

### Missing Required Argument
- Check the command definition for required arguments
- Provide all required arguments when invoking
- Error message will indicate which argument is missing

### Variable Not Substituted
- Ensure variable names match between frontmatter and template
- Check for typos in variable names
- Verify correct syntax: `{{variable}}` for named, `$1` for positional
