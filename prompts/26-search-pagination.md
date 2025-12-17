# Search Pagination

<metadata>
  <priority>medium</priority>
  <category>tool-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>agent/tools/, core/</affects>
</metadata>

## Objective

Add `head_limit` and `offset` parameters to grep/search tools for paginated results, allowing users to navigate through large search result sets efficiently without overwhelming output.

<context>
Search operations often return hundreds or thousands of results, making it difficult to process and analyze the output. Pagination parameters allow users to retrieve results in manageable chunks, similar to how the Read tool supports offset/limit for large files. This is essential for:
- Interactive exploration of search results
- Performance optimization when dealing with large result sets
- Progressive result loading in UI contexts
- Consistent API design across file and search operations
</context>

## Requirements

<functional-requirements>
1. Add `head_limit` parameter to Grep tool:
   - Limits output to first N lines/entries (equivalent to `| head -N`)
   - Works across all output modes: content, files_with_matches, count
   - Default: 0 (unlimited, shows all results)
   - When specified, shows appropriate truncation message per mode

2. Add `offset` parameter to Grep tool:
   - Skips first N lines/entries before applying head_limit (equivalent to `| tail -n +N | head -N`)
   - Works across all output modes
   - Default: 0 (start from beginning)
   - Useful for implementing pagination (offset=10, head_limit=10 for page 2)

3. Truncation messages:
   - Content mode: "(Output truncated to first N lines)"
   - Files mode: "(Results truncated to first N files)"
   - Count mode: "(Results truncated to first N files)"

4. Maintain ripgrep result sorting:
   - Files sorted by modification time (most recent first)
   - Pagination applied after sorting
</functional-requirements>

<technical-requirements>
1. Update Grep tool schema in Python backend:
   - Add `head_limit: Optional[int]` parameter with description
   - Add `offset: Optional[int]` parameter with description
   - Default both to 0 (no pagination)

2. Implement pagination logic:
   - Parse ripgrep output based on mode
   - Sort results appropriately (by mtime for files)
   - Apply offset: `results[offset:]`
   - Apply head_limit: `results[:head_limit]` after offset
   - Track truncation state for messaging

3. Format output with truncation indicators:
   - Append truncation message when results exceed head_limit
   - Include metadata about total results vs. displayed results
   - Preserve existing output formatting

4. Ensure backward compatibility:
   - When head_limit=0 and offset=0, behave exactly as before
   - No breaking changes to existing tool signatures
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/grep.py` (or equivalent) - Add pagination parameters and logic
- `agent/tools/schemas.py` - Update Grep tool schema with new parameters
- Tool registration code - Ensure new parameters are exposed in API
</files-to-modify>

<reference-implementation>
Based on `/Users/williamcory/agent-bak-bak/tool/grep.go`:

```python
# Schema updates
{
    "head_limit": {
        "type": "number",
        "description": 'Limit output to first N lines/entries, equivalent to "| head -N". Works across all output modes: content (limits output lines), files_with_matches (limits file paths), count (limits count entries). Defaults to 0 (unlimited).'
    },
    "offset": {
        "type": "number",
        "description": 'Skip first N lines/entries before applying head_limit, equivalent to "| tail -n +N | head -N". Works across all output modes. Defaults to 0.'
    }
}

# Implementation pattern
def format_content_output(pattern, output, head_limit, offset):
    lines = output.strip().split('\n')

    # Apply offset
    if offset > 0:
        lines = lines[offset:]

    # Apply head limit
    truncated = False
    if head_limit > 0 and len(lines) > head_limit:
        lines = lines[:head_limit]
        truncated = True

    # Format output
    result = '\n'.join(lines)
    if truncated:
        result += f'\n\n(Output truncated to first {head_limit} lines)'

    return result
```

Example usage:
```python
# Get first 10 results
grep(pattern="error", head_limit=10)

# Get second page of results (items 11-20)
grep(pattern="error", offset=10, head_limit=10)

# Get results 51-100
grep(pattern="error", offset=50, head_limit=50)
```
</reference-implementation>

## Test Cases

<test-scenarios>
1. **Basic head_limit**:
   - Search with 100 results, head_limit=10
   - Verify only 10 results returned
   - Verify truncation message present

2. **Offset without head_limit**:
   - Search with 50 results, offset=20
   - Verify results 21-50 returned (30 items)
   - Verify no truncation message

3. **Combined offset and head_limit**:
   - Search with 100 results, offset=25, head_limit=10
   - Verify results 26-35 returned (10 items)
   - Verify truncation message appropriate

4. **Offset beyond results**:
   - Search with 10 results, offset=20
   - Verify empty result set
   - Verify appropriate messaging

5. **All output modes**:
   - Test content mode with pagination
   - Test files_with_matches mode with pagination
   - Test count mode with pagination
   - Verify sorting maintained in each mode

6. **Backward compatibility**:
   - Search with no pagination params
   - Verify identical behavior to current implementation
   - Verify all results returned

7. **Edge cases**:
   - head_limit=0 (should show all)
   - offset=0 (should start from beginning)
   - head_limit greater than result count
   - Negative values (should error or default to 0)
</test-scenarios>

## Acceptance Criteria

<criteria>
- [ ] Grep tool accepts head_limit parameter (type: int, optional)
- [ ] Grep tool accepts offset parameter (type: int, optional)
- [ ] Pagination works in content output mode
- [ ] Pagination works in files_with_matches output mode
- [ ] Pagination works in count output mode
- [ ] Results maintain proper sorting (by mtime for files)
- [ ] Truncation messages appear when results are limited
- [ ] Backward compatibility: no params = all results (existing behavior)
- [ ] Offset can skip N results before head_limit applies
- [ ] Combined offset+head_limit enables true pagination
- [ ] Edge cases handled (offset beyond results, limit=0, etc.)
- [ ] All test scenarios pass
- [ ] No performance regression for non-paginated searches
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
2. Run full test suite to ensure no regressions
3. Test pagination with real-world search scenarios
4. Verify performance is acceptable for large result sets
5. Document the new parameters in tool descriptions/help
6. Rename this file from `26-search-pagination.md` to `26-search-pagination.complete.md`
</completion>
