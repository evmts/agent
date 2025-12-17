# Search Context Lines

<metadata>
  <priority>medium</priority>
  <category>tool-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>agent/tools/, MCP grep implementation</affects>
</metadata>

## Objective

Add -A (after), -B (before), and -C (context) flags to the Grep tool to show lines before and/or after matches, making it easier to understand match context without reading entire files.

<context>
When searching code, seeing surrounding context lines helps understand how a match is used. The ripgrep tool supports -A (after), -B (before), and -C (context) flags that show N lines before/after each match. This is essential for understanding function calls, variable usage, and code structure without needing to read entire files.

The Go implementation in agent-bak-bak already implements this feature correctly, passing the flags through to ripgrep and formatting the output with proper separators.
</context>

## Requirements

<functional-requirements>
1. Add -A parameter: Show N lines after each match
2. Add -B parameter: Show N lines before each match
3. Add -C parameter: Show N lines before AND after each match (shorthand)
4. Only apply context lines in "content" output_mode (ignored for "files_with_matches" and "count")
5. Format output with "--" separators between context groups (ripgrep default)
6. Preserve line numbers in context output when -n is enabled
7. Context lines should be clearly distinguishable from match lines
</functional-requirements>

<technical-requirements>
1. Add three new parameters to Grep tool schema:
   - `-A`: number (lines after)
   - `-B`: number (lines before)
   - `-C`: number (context lines, takes precedence over -A/-B)
2. Pass flags directly to ripgrep command when output_mode is "content"
3. Ripgrep handles context line formatting automatically
4. No changes needed to parsing logic - ripgrep outputs formatted context
5. Ensure context parameters are ignored for non-content output modes
</technical-requirements>

## Implementation Guide

<reference-implementation>
The Go implementation at `/Users/williamcory/agent-bak-bak/tool/grep.go` shows the correct approach:

```go
// Lines 159-168 from grep.go
if c, ok := params["-C"].(float64); ok && c > 0 {
    args = append(args, "-C", fmt.Sprintf("%d", int(c)))
} else {
    if a, ok := params["-A"].(float64); ok && a > 0 {
        args = append(args, "-A", fmt.Sprintf("%d", int(a)))
    }
    if b, ok := params["-B"].(float64); ok && b > 0 {
        args = append(args, "-B", fmt.Sprintf("%d", int(b)))
    }
}
```

Key points:
- -C takes precedence (if specified, ignore -A/-B)
- Only apply in content mode
- Pass directly to ripgrep - no custom parsing needed
- Ripgrep outputs "--" separators between context groups automatically
</reference-implementation>

<files-to-check>
Since this is a Python FastAPI backend using MCP servers:
1. Check if MCP filesystem server already supports grep with context
2. If not, may need to:
   - Add custom grep tool in `agent/agent.py` using @agent.tool_plain decorator
   - Or extend MCP filesystem server configuration
   - Or verify current grep implementation location
3. Reference: `agent/agent.py` - Look for tool definitions and MCP server setup
4. Tests: `tests/e2e/test_search_tools.py` - Add context line tests
</files-to-check>

<example-usage>
```python
# Search with 2 lines of context before and after
grep(
    pattern="def calculate",
    path="/src",
    output_mode="content",
    context_lines=2  # Shows 2 lines before and after
)

# Or using separate flags
grep(
    pattern="import.*numpy",
    path="/src",
    output_mode="content",
    after_context=3,   # 3 lines after
    before_context=1   # 1 line before
)
```

Output format:
```
/src/math.py:
  10: import sys
  11: import numpy as np
  12: import pandas as pd
--
  45: def calculate_mean(data):
  46:     """Calculate mean of dataset."""
  47:     return numpy.mean(data)
  48:
  49: def calculate_std(data):
```
</example-usage>

## Acceptance Criteria

<criteria>
- [ ] Grep tool accepts -A, -B, and -C parameters (integer values)
- [ ] -C parameter takes precedence over -A and -B when specified
- [ ] Context lines only shown in "content" output_mode
- [ ] Context parameters ignored in "files_with_matches" and "count" modes
- [ ] Line numbers preserved in context output (when -n is true)
- [ ] Context groups separated by "--" (ripgrep default)
- [ ] Tool documentation updated with context parameter descriptions
- [ ] E2E tests added for context line functionality
- [ ] No breaking changes to existing grep behavior
</criteria>

## Test Cases

<test-scenarios>
1. Basic context: Search with -C 2 shows 2 lines before/after matches
2. Asymmetric context: -A 3 -B 1 shows different before/after counts
3. Mode validation: Context params have no effect in files_with_matches mode
4. Line numbers: -n flag works correctly with context lines
5. Multiple matches: Context groups separated by "--"
6. Edge cases: Context at file boundaries doesn't error
7. Large context: -C 10 doesn't cause performance issues
8. Precedence: -C overrides -A/-B when both specified
</test-scenarios>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/e2e/test_search_tools.py -v` to ensure tests pass
3. Test manually with various context combinations
4. Verify grep tool documentation is updated
5. Rename this file from `25-search-context-lines.md` to `25-search-context-lines.complete.md`
</completion>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find where grep tool is currently implemented (MCP vs custom tool)
- [ ] Spawn subagent to verify the implementation compiles/runs
- [ ] Spawn subagent to run related tests (tests/e2e/test_search_tools.py)
- [ ] Spawn subagent to test actual grep calls with context flags
- [ ] Spawn subagent to check for regressions in existing grep functionality
</execution-strategy>
