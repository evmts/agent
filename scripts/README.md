# Bug Fix Automation Scripts

This directory contains scripts for automating the bug-fixing workflow with Claude Code.

## Overview

The automation loop works as follows:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Bug Fix Automation Loop                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐                                               │
│   │ Fetch Bugs   │ ◄── gh issue list --label bug                │
│   └──────┬───────┘                                               │
│          │                                                       │
│          ▼                                                       │
│   ┌──────────────┐                                               │
│   │ Create       │                                               │
│   │ Handoff      │ ◄── Detailed prompt with context             │
│   │ Prompt       │                                               │
│   └──────┬───────┘                                               │
│          │                                                       │
│          ▼                                                       │
│   ┌──────────────┐                                               │
│   │ Run Claude   │ ◄── claude -p "prompt" (headless mode)       │
│   │ Code Session │     or SDK query()                           │
│   └──────┬───────┘                                               │
│          │                                                       │
│          ▼                                                       │
│   ┌──────────────┐                                               │
│   │ Write Report │ ◄── reports/bug-fixes/bug-N-timestamp.md     │
│   └──────┬───────┘                                               │
│          │                                                       │
│          ▼                                                       │
│   ┌──────────────┐                                               │
│   │ Commit &     │ ◄── git commit, gh issue close               │
│   │ Close Issue  │                                               │
│   └──────┬───────┘                                               │
│          │                                                       │
│          ▼                                                       │
│   ┌──────────────┐                                               │
│   │ Next Bug     │ ──► Loop until max reached or failure        │
│   └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Scripts

### `bug-fix-loop.sh` (Recommended)

Shell script using `claude -p` headless mode. More stable and debuggable.

```bash
# Dry run - see what would happen
./scripts/bug-fix-loop.sh --dry-run

# Fix up to 3 bugs
./scripts/bug-fix-loop.sh --max 3

# Run with defaults (5 bugs max)
./scripts/bug-fix-loop.sh
```

### `bug-fix-loop.py` (Alternative)

Python script using Claude Agent SDK. More flexible but requires SDK installation.

```bash
# Install SDK
pip install claude-agent-sdk

# Dry run
python scripts/bug-fix-loop.py --dry-run

# Fix specific issue onwards
python scripts/bug-fix-loop.py --start-issue 37 --max-bugs 3
```

## Reports

All fix attempts generate reports in `reports/bug-fixes/`:

```
reports/bug-fixes/
├── bug-38-20251220-143022.md   # Individual fix report
├── bug-37-20251220-144515.md
└── loop-20251220-143000.log    # Full loop log
```

Report format:
```markdown
# Bug Fix Report: Issue #38

**Status**: SUCCESS
**Date**: 2025-12-20T14:30:22
**Duration**: 127s

## Bug Details
- **Title**: API accepts null bytes and control characters
- **Priority**: High

## Output
[Claude Code output...]
```

## Prerequisites

1. **Claude Code CLI** installed and authenticated
2. **GitHub CLI** (`gh`) installed and authenticated
3. **Docker services** running (`docker-compose up -d`)
4. On **plue-git** branch

## Handoff Prompt Structure

The generated prompts follow this structure:

```
# Bug Fix Agent Task

Fix GitHub Issue #N: [Title]

## Critical Rules
1. Single-branch workflow (plue-git)
2. Test-driven verification
3. Commit and close issue

## Workflow
1. Read issue
2. Run failing test
3. Investigate and fix
4. Verify tests pass
5. Commit and push
6. Close issue

## Context
- Priority, gotchas, patterns from previous fixes
```

## Customization

### Adding New Bug Metadata

Edit the `KNOWN_BUGS` dict in `bug-fix-loop.py`:

```python
KNOWN_BUGS = {
    42: {"test_file": "e2e/bugs.spec.ts", "test_line": 600, "priority": "High"},
}
```

### Changing Max Turns

In `bug-fix-loop.py`:
```python
options = ClaudeAgentOptions(max_turns=50)  # Default is 30
```

In `bug-fix-loop.sh`:
```bash
claude -p "$prompt" --max-turns 50
```

### Permission Mode

The scripts use `acceptEdits` which auto-approves file changes but prompts for Bash commands. For full automation:

```python
options = ClaudeAgentOptions(permission_mode="bypassPermissions")
```

⚠️ Use with caution - this allows any command execution.

## Troubleshooting

### "No open bugs found"

```bash
# Check if gh is authenticated
gh auth status

# Check for bug label
gh issue list --label bug
```

### "Must be on plue-git branch"

```bash
git checkout plue-git
```

### Claude Code errors

```bash
# Check CLI is installed
claude --version

# Check authentication
claude --help
```

### Tests still failing after fix

Check the report file for details, then:
```bash
# Run specific test manually
bun playwright test -g "BUG-038" --reporter=list

# View trace
bun playwright show-trace test-results/*/trace.zip
```
