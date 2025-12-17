# Tool Output Truncation

<metadata>
  <priority>high</priority>
  <category>reliability</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>agent/agent.py, core/, server/</affects>
</metadata>

## Objective

Implement output truncation limits for agent tools to prevent context overflow and improve response reliability when tools produce large outputs.

<context>
The Go-based agent implementation had output limits to prevent context window overflow:
- Bash tool: 30,000 character limit
- Read tool: 2,000 characters per line limit

Without these limits, long command outputs or large files can exhaust the context window, causing failures or degraded performance. The Python implementation needs similar safeguards.
</context>

## Requirements

<functional-requirements>
1. Bash/shell command output truncation:
   - Limit output to 30,000 characters maximum
   - Append clear truncation message: "\n... (output truncated)"
   - Truncate combined stdout/stderr output

2. Read tool line length truncation:
   - Limit individual lines to 2,000 characters
   - Truncate long lines with indicator
   - Preserve line structure and numbering

3. Configurable limits:
   - Define constants at module level (NO MAGIC NUMBERS)
   - Use SCREAMING_CASE naming convention
   - Allow override via environment variables (optional enhancement)

4. Metadata reporting:
   - Add "truncated": true/false to tool result metadata
   - Report original length before truncation (when truncated)
   - Preserve error information when truncation occurs
</functional-requirements>

<technical-requirements>
1. Define constants in appropriate modules:
   ```python
   MAX_BASH_OUTPUT_LENGTH = 30000
   MAX_LINE_LENGTH = 2000
   DEFAULT_READ_LIMIT = 2000
   ```

2. Implement truncation logic:
   - Check output length before returning from tool execution
   - Preserve structure (line numbers, formatting) when possible
   - Ensure truncation message is clearly visible

3. Update tool descriptions:
   - Document truncation limits in tool docstrings
   - Add usage notes about output limits
   - Guide users to use pagination/filtering for large outputs

4. Add metadata fields:
   - "truncated": bool - whether output was truncated
   - "original_length": int - original output length (when truncated)
   - "max_length": int - configured maximum length
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/agent.py` - Add truncation to bash tool and any custom tools
- Tool result metadata handling - Add truncation metadata
- Tool descriptions/docstrings - Document output limits
- Configuration constants - Define MAX_BASH_OUTPUT_LENGTH, MAX_LINE_LENGTH
</files-to-modify>

<reference-implementation>
From `/Users/williamcory/agent-bak-bak/tool/bash.go`:

```go
const (
    MaxOutputLength = 30000
    DefaultTimeout  = 2 * time.Minute
    MaxTimeout      = 10 * time.Minute
)

// In executeBash():
// Truncate if too long
if len(output) > MaxOutputLength {
    output = output[:MaxOutputLength] + "\n... (output truncated)"
}
```

From `/Users/williamcory/agent-bak-bak/tool/read.go`:

```go
const (
    DefaultReadLimit = 2000
    MaxLineLength    = 2000
)

// In executeRead():
// Truncate long lines
if len(line) > MaxLineLength {
    line = line[:MaxLineLength] + "..."
}
```
</reference-implementation>

<example-usage>
Before truncation:
```
$ cat large_file.log
[10,000 lines of output...]
```

After truncation:
```
$ cat large_file.log
[First 30,000 characters of output]
... (output truncated)

Metadata: {
  "truncated": true,
  "original_length": 150000,
  "max_length": 30000
}
```
</example-usage>

## Acceptance Criteria

<criteria>
- [ ] Bash tool output truncated at 30,000 characters
- [ ] Truncation message clearly indicates output was cut
- [ ] Read tool lines truncated at 2,000 characters per line
- [ ] Constants defined at module level (no magic numbers)
- [ ] Tool descriptions updated with truncation limits
- [ ] Metadata includes truncation status and original length
- [ ] No errors when processing outputs at/near limits
- [ ] Truncation preserves readability and structure
</criteria>

## Testing Strategy

<testing>
1. Unit tests for truncation logic:
   - Test exact boundary conditions (30k, 30k+1 chars)
   - Verify truncation message appended correctly
   - Ensure metadata accuracy

2. Integration tests:
   - Run bash commands with large output (>30k chars)
   - Read files with very long lines (>2k chars)
   - Verify agent continues functioning correctly

3. Edge cases:
   - Empty output
   - Output exactly at limit
   - Unicode characters near truncation boundary
   - Mixed stdout/stderr with truncation
</testing>

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
2. Run `pytest` to ensure all tests pass
3. Test manually with large outputs
4. Verify MCP tool integration still works correctly
5. Rename this file from `21-output-truncation.md` to `21-output-truncation.complete.md`
</completion>

## Hindsight

<hindsight>
**Implementation Completed: 2025-12-17**

### What Worked Well

1. **MCP Server Modification**: Modifying the mcp_server_shell Python package directly was straightforward and effective. The CommandResult Pydantic model made it easy to add truncation metadata fields (truncated, original_length, max_length).

2. **Custom Read Tool**: Creating a custom `read_file_safe` tool alongside the existing MCP filesystem tools provided a good balance. Users can choose between:
   - MCP `read_text_file` (no line truncation, full content)
   - Custom `read_file_safe` (line truncation for safety)

3. **Truncation Logic**: The `_truncate_long_lines` helper function correctly handles newline characters by checking line length without the newline, preventing off-by-one errors.

4. **Comprehensive Testing**: Created 15 tests covering:
   - Line truncation boundary conditions
   - Bash output constants
   - File read operations with truncation
   - Metadata validation

5. **No Magic Numbers**: All limits defined as module-level constants in SCREAMING_CASE as per style guide.

### Challenges & Solutions

1. **External MCP Servers**: The filesystem MCP server is Node.js-based and external, so we couldn't directly modify it. Solution: Created a parallel custom tool that provides truncation functionality.

2. **Pydantic AI Agent API**: Initially tried to access `agent._function_tools` but the correct attribute is `agent._function_toolset.tools`. Had to explore the API to find the right way to access registered tools in tests.

3. **Agent Creation Regression**: Initially broke `create_agent()` by passing `None` for empty tool lists. Pydantic AI expects either omitting the parameter or passing an actual list. Fixed by conditionally including kwargs only when lists are non-empty.

4. **Line Length Calculation**: First implementation counted newline characters in line length, causing boundary tests to fail. Fixed by checking `line.rstrip('\r\n')` length before truncation decision.

### Key Learnings

1. **MCP Architecture**: In this Python implementation, tools are provided by external MCP servers (shell, filesystem) that run as separate processes. Direct modification requires editing the MCP server packages themselves.

2. **Tool Design Pattern**: The pattern of providing both "safe" (truncated) and "full" (untruncated) versions of tools gives users flexibility while maintaining safety defaults.

3. **Metadata Importance**: Including truncation metadata (original_length, max_length, truncated flag) in tool results helps users understand when and why output was truncated.

4. **Test-Driven Development**: Writing comprehensive tests before running them caught multiple issues early (boundary conditions, attribute access, regression in agent creation).

### Files Modified

1. `/Users/williamcory/agent/.venv/lib/python3.12/site-packages/mcp_server_shell/server.py`
   - Added MAX_BASH_OUTPUT_LENGTH and TRUNCATION_MESSAGE constants
   - Extended CommandResult model with truncation metadata
   - Implemented truncation logic in execute_command()
   - Updated tool description to document limits

2. `/Users/williamcory/agent/agent/agent.py`
   - Added MAX_BASH_OUTPUT_LENGTH, MAX_LINE_LENGTH, DEFAULT_READ_LIMIT constants
   - Implemented `_truncate_long_lines()` helper function
   - Added `read_file_safe` custom tool with line truncation
   - Updated SYSTEM_INSTRUCTIONS to document output limits
   - Fixed create_agent() to avoid passing None for empty tool lists

3. `/Users/williamcory/agent/tests/test_agent/test_truncation.py` (new file)
   - 15 comprehensive tests for truncation functionality
   - Tests for line truncation, bash output, file reading, and metadata

### Acceptance Criteria Status

- [x] Bash tool output truncated at 30,000 characters
- [x] Truncation message clearly indicates output was cut
- [x] Read tool lines truncated at 2,000 characters per line
- [x] Constants defined at module level (no magic numbers)
- [x] Tool descriptions updated with truncation limits
- [x] Metadata includes truncation status and original length
- [x] No errors when processing outputs at/near limits
- [x] Truncation preserves readability and structure

### Test Results

All 180 tests pass:
- 7 line truncation tests
- 2 bash output truncation tests
- 4 read_file_safe tests
- 2 metadata tests
- 165 existing tests (no regressions)

### Recommendations for Future Work

1. Consider adding environment variables to configure truncation limits (MAX_BASH_OUTPUT_LENGTH, MAX_LINE_LENGTH)
2. Monitor real-world usage to determine if limits need adjustment
3. Consider adding similar truncation to other tools that might return large outputs
4. Explore if pydantic_ai provides middleware/hooks for MCP tool result processing
</hindsight>
