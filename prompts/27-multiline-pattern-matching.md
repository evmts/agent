# Multiline Pattern Matching

<metadata>
  <priority>medium</priority>
  <category>tool-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>agent/agent.py, agent/tools/ (if new tool module created)</affects>
</metadata>

## Objective

Add multiline pattern matching capability to grep/search functionality for patterns that span multiple lines, such as matching function definitions with their bodies, multi-line comments, or code blocks.

<context>
The current MCP filesystem server's search_files tool uses ripgrep under the hood, which supports multiline matching via the `-U` (multiline) flag and `--multiline-dotall` option. However, this functionality is not exposed to the agent. Patterns like `struct \{[\s\S]*?field` or multi-line regex patterns that need to match across line boundaries currently don't work. This is essential for complex code analysis tasks like finding entire function definitions, multi-line comments, or configuration blocks.

Reference implementations from OpenCode TypeScript codebase show ripgrep being invoked with JSON output format and various flags. The Python agent currently relies on the MCP filesystem server, which may need extension or replacement with a custom grep tool that supports multiline mode.
</context>

## Requirements

<functional-requirements>
1. Add a `multiline` boolean parameter to grep/search operations
2. When `multiline: true`:
   - Enable ripgrep's `-U` (multiline) flag
   - Enable `--multiline-dotall` so `.` matches newlines
   - Allow patterns to span across line boundaries
3. Maintain backward compatibility - default behavior (single-line matching) unchanged
4. Provide clear error messages when multiline patterns are invalid
5. Support common multiline use cases:
   - Function/method definitions with bodies
   - Multi-line comments and docstrings
   - Configuration blocks (JSON, YAML, etc.)
   - Code blocks between braces/brackets
</functional-requirements>

<technical-requirements>
1. Evaluate whether to:
   - Option A: Extend MCP filesystem server's search_files tool (if possible)
   - Option B: Create custom `grep` tool using @agent.tool_plain decorator
   - Option C: Use shell tool to invoke ripgrep directly with multiline flags
2. If creating custom tool, implement in `agent/agent.py` or new `agent/tools/grep.py`
3. Add `multiline: bool = False` parameter to tool definition
4. When multiline=True, add ripgrep flags: `-U --multiline-dotall`
5. Consider performance implications - multiline searches are slower
6. Add appropriate tool description explaining multiline usage
7. Include examples in tool docstring for common multiline patterns
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/agent.py` - Add custom grep tool with multiline support OR extend existing tool usage
- `agent/tools/grep.py` (optional) - New module for grep tool if separating concerns
- `agent/registry.py` (if needed) - Add grep tool to agent permissions/registry
- `tests/test_agent/test_tools/test_grep.py` (new) - Unit tests for multiline grep
</files-to-modify>

<example-implementation>
```python
# In agent/agent.py or agent/tools/grep.py

@agent.tool_plain
async def grep(
    pattern: str,
    path: str | None = None,
    glob: str | None = None,
    multiline: bool = False,
    case_insensitive: bool = False,
    max_count: int | None = None,
) -> str:
    """Search for patterns in files using ripgrep.

    Args:
        pattern: Regular expression pattern to search for
        path: Directory to search in (defaults to working directory)
        glob: File pattern to filter (e.g., "*.py", "*.{ts,tsx}")
        multiline: Enable multiline mode where . matches newlines and patterns can span lines
        case_insensitive: Case-insensitive search
        max_count: Maximum number of matches per file

    Examples:
        # Single-line search (default)
        grep(pattern="def authenticate", glob="*.py")

        # Multi-line search for function with body
        grep(pattern=r"def authenticate\(.*?\):[\\s\\S]*?return", multiline=True, glob="*.py")

        # Find multi-line comments
        grep(pattern=r'"""[\\s\\S]*?"""', multiline=True, glob="*.py")

    Returns:
        Search results formatted as file paths and matching lines
    """
    import subprocess
    import json

    # Get ripgrep path (could use Bun.which or system ripgrep)
    rg_path = "rg"  # Assume ripgrep is in PATH

    args = [rg_path, "--json", "--hidden", "--glob=!.git/*"]

    if multiline:
        args.extend(["-U", "--multiline-dotall"])

    if case_insensitive:
        args.append("-i")

    if glob:
        args.append(f"--glob={glob}")

    if max_count:
        args.append(f"--max-count={max_count}")

    args.append(pattern)

    if path:
        args.append(path)

    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 1:
            return "No matches found"

        if result.returncode != 0:
            return f"Error: {result.stderr}"

        # Parse JSON output from ripgrep
        lines = result.stdout.strip().split("\n")
        matches = []

        for line in lines:
            if not line:
                continue
            data = json.loads(line)
            if data.get("type") == "match":
                match_data = data["data"]
                matches.append({
                    "path": match_data["path"]["text"],
                    "line_num": match_data["line_number"],
                    "text": match_data["lines"]["text"],
                })

        if not matches:
            return "No matches found"

        # Format output
        output_lines = [f"Found {len(matches)} matches"]
        current_file = ""

        for match in matches:
            if current_file != match["path"]:
                if current_file:
                    output_lines.append("")
                current_file = match["path"]
                output_lines.append(f"{match['path']}:")

            output_lines.append(f"  Line {match['line_num']}: {match['text']}")

        return "\n".join(output_lines)

    except subprocess.TimeoutExpired:
        return "Search timed out (30s limit)"
    except Exception as e:
        return f"Error: {str(e)}"
```
</example-implementation>

<example-usage>
```
User: "Find all async function definitions in Python files"

Assistant uses:
grep(
    pattern=r"async def \w+\([^)]*\):[\s\S]*?(?=\nasync def|\nclass|\ndef|\Z)",
    multiline=True,
    glob="*.py"
)

---

User: "Find all multi-line docstrings that mention 'authentication'"

Assistant uses:
grep(
    pattern=r'"""[\s\S]*?authentication[\s\S]*?"""',
    multiline=True,
    glob="*.py",
    case_insensitive=True
)
```
</example-usage>

## Acceptance Criteria

<criteria>
- [ ] Grep tool supports `multiline` boolean parameter
- [ ] When multiline=True, patterns can match across line boundaries
- [ ] When multiline=False (default), behavior is unchanged from current
- [ ] Tool properly invokes ripgrep with `-U --multiline-dotall` flags
- [ ] Error handling for invalid patterns and timeouts
- [ ] Tool docstring includes multiline usage examples
- [ ] Unit tests cover both single-line and multiline scenarios
- [ ] Performance is acceptable (searches complete within timeout)
- [ ] Works with common multiline patterns (functions, comments, blocks)
</criteria>

## Testing Strategy

<testing>
1. Create test fixtures with multi-line code patterns:
   - Python functions with bodies
   - Multi-line docstrings
   - Nested code blocks
   - Multi-line comments

2. Test cases:
   - Single-line pattern with multiline=False (default behavior)
   - Multi-line pattern with multiline=True (new functionality)
   - Pattern that would fail without multiline mode
   - Case-insensitive multiline search
   - Multiline search with glob filtering
   - Timeout handling for complex patterns
   - Invalid pattern error handling

3. Integration test:
   - Run agent with multiline grep request
   - Verify correct results returned
   - Check performance is acceptable
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
2. Run unit tests: `pytest tests/test_agent/test_tools/test_grep.py -v`
3. Run integration test with actual multiline search scenarios
4. Test performance with complex patterns on large codebases
5. Update agent documentation with multiline grep examples
6. Rename this file from `27-multiline-pattern-matching.md` to `27-multiline-pattern-matching.complete.md`
</completion>

## References

<references>
- OpenCode TypeScript implementation: `/Users/williamcory/agent-bak-bak/opencode/packages/opencode/src/tool/grep.ts`
- Ripgrep JSON output: `/Users/williamcory/agent-bak-bak/opencode/packages/opencode/src/file/ripgrep.ts`
- Current agent tools: `/Users/williamcory/agent/agent/agent.py` (lines 236-390)
- MCP filesystem server: `@modelcontextprotocol/server-filesystem` (provides search_files)
- Ripgrep documentation: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#multiline-search
</references>

## Performance Considerations

<performance>
Multiline searches are inherently slower than single-line searches because:
1. Ripgrep must read entire file contents into memory
2. Pattern matching across line boundaries is more complex
3. Backtracking in regex can be expensive for complex patterns

Mitigations:
- Set reasonable timeout (30s recommended)
- Use `max_count` parameter to limit results
- Combine with `glob` parameter to narrow file search scope
- Consider adding file size limits for multiline searches
- Document performance implications in tool description
</performance>

## Known Limitations

<limitations>
1. Multiline mode is memory-intensive for large files
2. Complex regex patterns may cause performance issues
3. Very greedy patterns (e.g., `.*` across many lines) can be slow
4. Not all regex engines support identical multiline semantics
5. Results display may be verbose for large matching blocks
</limitations>

## Future Enhancements

<future>
1. Add context lines parameter (`-A`, `-B`, `-C` flags in ripgrep)
2. Support for fixed-string multiline matching (faster than regex)
3. Streaming results for very large result sets
4. Syntax highlighting for multiline matches
5. Support for lookahead/lookbehind in multiline patterns
6. AST-based code search for language-specific queries
</future>
