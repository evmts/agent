# Custom Slash Commands

<metadata>
  <priority>medium</priority>
  <category>extensibility</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/, config/</affects>
</metadata>

## Objective

Implement support for user-defined slash commands via markdown files in `~/.agent/prompts/`, allowing users to create reusable command shortcuts.

<context>
Codex supports custom slash commands defined as markdown files. This enables:
- Project-specific command shortcuts
- Reusable prompt templates
- Workflow automation
- Team-shared commands

Custom commands are defined in `~/.codex/prompts/*.md` and invoked via `/command-name` or `/prompts:command-name`.
</context>

## Requirements

<functional-requirements>
1. Load custom commands from `~/.agent/prompts/*.md`
2. Command name derived from filename (without .md)
3. Command file content used as prompt template
4. Support variable substitution (`$1`, `$2`, or `{{variable}}`)
5. Commands appear in `/` autocomplete
6. `/prompts:name` syntax for explicit invocation
7. Custom commands can override built-in commands
8. Reload commands on file changes (optional)
</functional-requirements>

<technical-requirements>
1. Create prompts directory scanner
2. Implement command parser
3. Add custom commands to autocomplete
4. Template variable substitution
5. Priority handling for overrides
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `config/commands.py` (CREATE) - Custom command loading
- `tui/main.go` - Integrate custom commands
- `tui/internal/components/autocomplete/autocomplete.go` - Add custom commands
</files-to-modify>

<command-file-format>
```markdown
<!-- ~/.agent/prompts/review-pr.md -->
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

Fetch the PR diff using:
```bash
gh pr diff {{pr_number}}
```

Provide structured feedback with severity levels.
```
</command-file-format>

<command-loader>
```python
# config/commands.py

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import yaml
import re

@dataclass
class CommandArg:
    name: str
    required: bool = False
    description: str = ""
    default: Optional[str] = None

@dataclass
class CustomCommand:
    name: str
    description: str
    template: str
    args: list[CommandArg] = field(default_factory=list)
    file_path: Path = None

class CommandRegistry:
    def __init__(self, prompts_dir: Path = None):
        self.prompts_dir = prompts_dir or Path.home() / ".agent" / "prompts"
        self._commands: dict[str, CustomCommand] = {}

    def load_commands(self) -> None:
        """Load all custom commands from prompts directory."""
        self._commands.clear()

        if not self.prompts_dir.exists():
            self.prompts_dir.mkdir(parents=True, exist_ok=True)
            return

        for cmd_file in self.prompts_dir.glob("*.md"):
            try:
                command = self._parse_command_file(cmd_file)
                if command:
                    self._commands[command.name] = command
            except Exception as e:
                logger.warning(f"Failed to parse command {cmd_file}: {e}")

    def _parse_command_file(self, path: Path) -> Optional[CustomCommand]:
        """Parse a command file with optional YAML frontmatter."""
        content = path.read_text()

        # Default name from filename
        name = path.stem

        # Check for YAML frontmatter
        frontmatter = {}
        template = content

        match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
        if match:
            frontmatter = yaml.safe_load(match.group(1)) or {}
            template = match.group(2).strip()

        # Override name if specified
        name = frontmatter.get("name", name)
        description = frontmatter.get("description", "")

        # Parse args
        args = []
        for arg_def in frontmatter.get("args", []):
            args.append(CommandArg(
                name=arg_def.get("name", ""),
                required=arg_def.get("required", False),
                description=arg_def.get("description", ""),
                default=arg_def.get("default"),
            ))

        return CustomCommand(
            name=name,
            description=description,
            template=template,
            args=args,
            file_path=path,
        )

    def get_command(self, name: str) -> Optional[CustomCommand]:
        """Get command by name."""
        return self._commands.get(name)

    def list_commands(self) -> list[CustomCommand]:
        """List all custom commands."""
        return list(self._commands.values())

    def expand_command(self, name: str, args: list[str] = None, kwargs: dict = None) -> Optional[str]:
        """Expand command template with arguments."""
        command = self.get_command(name)
        if not command:
            return None

        template = command.template
        args = args or []
        kwargs = kwargs or {}

        # Substitute positional args ($1, $2, etc.)
        for i, arg in enumerate(args):
            template = template.replace(f"${i+1}", arg)

        # Substitute named args ({{name}})
        for key, value in kwargs.items():
            template = template.replace(f"{{{{{key}}}}}", value)

        # Substitute from command args with defaults
        for i, arg_def in enumerate(command.args):
            placeholder = f"{{{{{arg_def.name}}}}}"
            if placeholder in template:
                if i < len(args):
                    template = template.replace(placeholder, args[i])
                elif arg_def.name in kwargs:
                    template = template.replace(placeholder, kwargs[arg_def.name])
                elif arg_def.default:
                    template = template.replace(placeholder, arg_def.default)
                elif arg_def.required:
                    raise ValueError(f"Required argument missing: {arg_def.name}")

        return template


# Global instance
command_registry = CommandRegistry()
```
</command-loader>

<tui-integration>
```go
// In TUI command handling

func (m *Model) handleSlashCommand(input string) tea.Cmd {
    parts := strings.SplitN(strings.TrimPrefix(input, "/"), " ", 2)
    cmdName := parts[0]
    args := ""
    if len(parts) > 1 {
        args = parts[1]
    }

    // Check for custom command
    customCmd, err := m.client.GetCustomCommand(cmdName)
    if err == nil && customCmd != nil {
        // Expand template
        expanded, err := m.client.ExpandCommand(cmdName, strings.Fields(args))
        if err != nil {
            return showError(fmt.Errorf("command error: %w", err))
        }
        // Send as message
        return m.sendMessage(expanded)
    }

    // Handle built-in commands
    switch cmdName {
    case "help":
        return m.showHelp()
    // ... other built-in commands
    default:
        return showError(fmt.Errorf("unknown command: /%s", cmdName))
    }
}

// Add custom commands to autocomplete
func (m *Model) getSlashCommands() []AutocompleteItem {
    items := []AutocompleteItem{
        {Label: "/help", Description: "Show help"},
        {Label: "/model", Description: "Switch model"},
        // ... other built-in commands
    }

    // Add custom commands
    customCmds, _ := m.client.ListCustomCommands()
    for _, cmd := range customCmds {
        items = append(items, AutocompleteItem{
            Label:       "/" + cmd.Name,
            Description: cmd.Description,
            Custom:      true,
        })
    }

    return items
}
```
</tui-integration>

<example-commands>
```markdown
<!-- ~/.agent/prompts/commit.md -->
---
name: commit
description: Create a conventional commit message
---
Look at the staged changes and create a conventional commit message.
Use format: <type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore

Generate the commit message and ask me to confirm before committing.

---

<!-- ~/.agent/prompts/explain.md -->
---
name: explain
description: Explain a piece of code
args:
  - name: file
    required: true
---
Please explain the code in {{file}}:
- What does it do?
- How does it work?
- Any notable patterns or issues?

---

<!-- ~/.agent/prompts/test.md -->
---
name: test
description: Generate tests for a file
args:
  - name: file
    required: true
  - name: framework
    default: pytest
---
Generate comprehensive tests for {{file}} using {{framework}}.
Include:
- Unit tests for each function
- Edge cases
- Error handling
```
</example-commands>

## Acceptance Criteria

<criteria>
- [ ] Commands loaded from ~/.agent/prompts/*.md
- [ ] Command name from filename or frontmatter
- [ ] YAML frontmatter for metadata
- [ ] Variable substitution ($1, {{name}})
- [ ] Commands in autocomplete
- [ ] /command-name invokes command
- [ ] /prompts:name explicit syntax
- [ ] Args with defaults supported
- [ ] Required args validated
- [ ] Custom commands can override built-ins
- [ ] Descriptive error for missing args
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
2. Create sample custom commands and test
3. Test variable substitution
4. Test autocomplete integration
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `44-custom-slash-commands.md` to `44-custom-slash-commands.complete.md`
</completion>
