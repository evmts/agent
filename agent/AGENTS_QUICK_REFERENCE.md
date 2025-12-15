# Agent Quick Reference

## Quick Comparison

| Agent     | Mode      | Temp | Python | Shell      | Write | Web   | Best For |
|-----------|-----------|------|--------|------------|-------|-------|----------|
| build     | PRIMARY   | 0.7  | ✓      | ✓ All      | ✓     | ✓     | General development |
| general   | SUBAGENT  | 0.7  | ✓      | ✓ All      | ✓     | ✓     | Parallel tasks |
| plan      | PRIMARY   | 0.6  | ✗      | ✓ Limited  | ✗     | ✓     | Read-only analysis |
| explore   | PRIMARY   | 0.5  | ✗      | ✓ Limited  | ✗     | ✗     | Fast code search |

## One-Line Summaries

- **build**: Full-featured agent for all development tasks
- **general**: Parallel execution specialist for multi-step workflows
- **plan**: Read-only analyst for code review and planning
- **explore**: Fast search specialist for code navigation

## Usage

```python
from agent import create_agent

# Default (full access)
agent = create_agent()
agent = create_agent(agent_name="build")

# Parallel execution
agent = create_agent(agent_name="general")

# Read-only analysis
agent = create_agent(agent_name="plan")

# Fast search
agent = create_agent(agent_name="explore")
```

## Decision Tree

```
Need to modify code?
├─ Yes
│  ├─ Running multiple tasks in parallel?
│  │  ├─ Yes → use "general"
│  │  └─ No  → use "build"
│  └─ No (read-only)
│     ├─ Just exploring/searching?
│     │  ├─ Yes → use "explore"
│     │  └─ No  → use "plan"
```

## Shell Command Examples

### Build Agent (unrestricted)
```bash
✓ ls -la
✓ git status
✓ python script.py
✓ npm install
✓ make build
# All commands allowed
```

### Plan Agent (read-only)
```bash
✓ ls -la
✓ git status
✓ git log
✓ grep pattern file
✗ rm -rf /
✗ python script.py
✗ npm install
```

### Explore Agent (search-focused)
```bash
✓ ls -la
✓ find . -name "*.py"
✓ git log --oneline
✓ rg "pattern"
✗ npm install
✗ python script.py
```

## Common Use Cases

### Code Review
```python
agent = create_agent(agent_name="plan")
# Agent can read, search, use git, but can't modify
```

### Feature Implementation
```python
agent = create_agent(agent_name="build")
# Full access to all tools
```

### Refactoring Multiple Files
```python
agent = create_agent(agent_name="general")
# Optimized for parallel operations
```

### Finding Code Patterns
```python
agent = create_agent(agent_name="explore")
# Fast, focused on search and navigation
```

## Tool Access Matrix

| Tool     | build | general | plan | explore |
|----------|-------|---------|------|---------|
| python   | ✓     | ✓       | ✗    | ✗       |
| shell    | ✓ All | ✓ All   | ✓ R/O| ✓ R/O   |
| read     | ✓     | ✓       | ✓    | ✓       |
| write    | ✓     | ✓       | ✗    | ✗       |
| edit     | ✓     | ✓       | ✗    | ✗       |
| search   | ✓     | ✓       | ✓    | ✓       |
| grep     | ✓     | ✓       | ✓    | ✓       |
| ls       | ✓     | ✓       | ✓    | ✓       |
| fetch    | ✓     | ✓       | ✓    | ✗       |
| web      | ✓     | ✓       | ✓    | ✗       |

Legend: ✓ = Enabled, ✗ = Disabled, R/O = Read-only/Restricted

## See Also

- Full documentation: `/Users/williamcory/agent/agent/REGISTRY.md`
- Demo script: `/Users/williamcory/agent/examples/agent_registry_demo.py`
- Implementation: `/Users/williamcory/agent/agent/registry.py`
