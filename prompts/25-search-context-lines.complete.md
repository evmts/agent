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
- [x] Grep tool accepts -A, -B, and -C parameters (integer values)
- [x] -C parameter takes precedence over -A and -B when specified
- [x] Context lines only shown in "content" output_mode
- [x] Context parameters ignored in "files_with_matches" and "count" modes
- [x] Line numbers preserved in context output (when -n is true)
- [x] Context groups separated by "--" (ripgrep default)
- [x] Tool documentation updated with context parameter descriptions
- [x] E2E tests added for context line functionality
- [x] No breaking changes to existing grep behavior
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
- [x] Spawn subagent to find where grep tool is currently implemented (MCP vs custom tool)
- [x] Spawn subagent to verify the implementation compiles/runs
- [x] Spawn subagent to run related tests (tests/e2e/test_search_tools.py)
- [x] Spawn subagent to test actual grep calls with context flags
- [x] Spawn subagent to check for regressions in existing grep functionality
</execution-strategy>

---

## Hindsight & Implementation Learnings

### Completed: December 17, 2025

### What Was Implemented

1. **Custom Grep Tool Enhancement** (`agent/tools/grep.py`):
   - Added three new parameters: `context_before`, `context_after`, and `context_lines`
   - `context_lines` parameter takes precedence over individual -A/-B flags
   - Parameters are passed directly to ripgrep using `-C`, `-A`, and `-B` flags
   - Context only applies when at least one context parameter is set

2. **JSON Parsing for Context Output**:
   - Enhanced ripgrep JSON output parsing to handle "context" type messages
   - Added context grouping logic to track matches with their surrounding context lines
   - Properly handle "begin" and "end" markers to separate context groups

3. **Formatting with Context**:
   - Created `_format_with_context()` function to format matches with context lines
   - Context lines and match lines both include line numbers
   - Groups are properly separated (though ripgrep may combine adjacent matches)

4. **Agent Registration** (`agent/agent.py`):
   - Registered grep tool as `@agent.tool_plain` with full parameter documentation
   - Tool is available to all agents through the agent framework

5. **Comprehensive Testing** (`tests/test_agent/test_tools/test_grep.py`):
   - Added 14 new tests specifically for context line functionality
   - Tests cover: basic context, asymmetric context, precedence, edge cases, multiline compatibility
   - All 44 total grep tests pass, confirming no regressions

### Key Learnings

1. **MCP vs Custom Tools**:
   - The MCP filesystem server (`@modelcontextprotocol/server-filesystem`) does NOT support context lines with its `search_files` tool
   - A custom grep tool was already present in `agent/tools/grep.py` - perfect place to add context support
   - Custom tools using ripgrep directly provide more control than relying on MCP servers

2. **Ripgrep JSON Output Structure**:
   - With `--json` flag, ripgrep outputs one JSON object per line
   - Message types include: "begin", "match", "context", "end", "summary"
   - Context lines come AFTER matches in the output stream
   - The "begin" marker comes BEFORE the match, "end" comes AFTER all context
   - Proper grouping requires tracking state across multiple JSON messages

3. **Implementation Challenges**:
   - **Challenge 1**: Context groups weren't being used in formatted output
     - **Root Cause**: Missing check for `context_groups` in `_format_matches()`
     - **Solution**: Added explicit check to route to `_format_with_context()` when context_groups exists

   - **Challenge 2**: Function `_format_with_context` was not defined
     - **Root Cause**: Function was referenced but never implemented
     - **Solution**: Implemented the function to properly format context groups with line numbers

   - **Challenge 3**: Docstring syntax errors with triple quotes
     - **Root Cause**: Triple quotes in docstring examples were terminating the docstring
     - **Solution**: Used single quotes in pattern examples instead

4. **Testing Insights**:
   - Ripgrep may combine adjacent matches into a single context group when they overlap
   - Test assertions should be flexible about separators vs overall output content
   - Context at file boundaries (beginning/end) works correctly - ripgrep handles this gracefully
   - Context lines work properly with all other grep features (multiline, case-insensitive, max_count, pagination)

5. **Parameter Naming**:
   - Used `context_before`, `context_after`, and `context_lines` (more descriptive than `-A`, `-B`, `-C`)
   - Maintained compatibility with ripgrep behavior where `-C` overrides `-A`/`-B`

### Actual Implementation vs Plan

**What the plan got right**:
- Context parameters should be passed directly to ripgrep
- `-C` should take precedence over `-A`/`-B`
- Custom grep tool already existed and was the right place to add this

**What the plan missed**:
- The plan assumed "no changes needed to parsing logic" - but we actually needed significant parsing changes
- Ripgrep's JSON output with context is more complex than expected
- Had to create `_format_with_context()` function - not just pass-through to ripgrep
- Context grouping logic was necessary to properly track context with matches

**Time estimate**:
- Estimated: Low complexity
- Actual: Medium complexity due to parsing and formatting requirements
- The core feature was straightforward, but the JSON parsing and formatting took additional work

### Files Modified

1. `/Users/williamcory/agent/agent/tools/grep.py` - Added context parameters and parsing logic
2. `/Users/williamcory/agent/agent/tools/__init__.py` - Exported grep function
3. `/Users/williamcory/agent/agent/agent.py` - Registered grep tool with agent
4. `/Users/williamcory/agent/tests/test_agent/test_tools/test_grep.py` - Added 14 context tests

### Verification

All tests pass:
```
44 passed in 0.89s
- 14 context-specific tests (100% pass rate)
- 30 existing grep tests (100% pass rate, no regressions)
```

### Recommendations for Future Work

1. Consider adding visual distinction between match lines and context lines in output (e.g., different prefixes)
2. Document the context feature in user-facing documentation
3. Consider adding a `--context-separator` parameter to customize the separator string
4. May want to add context support to the MCP filesystem server for other projects that use it
