# Web Fetch Size Limit

<metadata>
  <priority>high</priority>
  <category>security-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>agent/tools/, core/, tests/</affects>
</metadata>

## Objective

Implement a 5MB size limit for web fetch operations to prevent memory exhaustion and denial-of-service issues when fetching large files or malicious content.

<context>
Web fetch operations can consume excessive memory if they download very large files (videos, datasets, archives, etc.) or encounter malicious servers that stream endless data. The Go implementation in agent-bak-bak already includes this protection with a MaxResponseSize constant of 5MB. This implementation needs to be ported to the Python backend to ensure consistent behavior and prevent resource exhaustion.

Current security gap:
- No size limit on HTTP response bodies
- Potential for memory exhaustion attacks
- No protection against accidentally fetching large files
- Inconsistent behavior between Go and Python implementations
</context>

## Requirements

<functional-requirements>
1. Set maximum response size of 5MB (5 * 1024 * 1024 bytes) for all web fetch operations
2. Check Content-Length header if present and reject requests before downloading
3. Use streaming read with size limit to prevent full download of oversized content
4. Return clear error message when size limit is exceeded: "response too large (exceeds 5MB limit)"
5. Apply limit consistently across all fetch formats (text, markdown, html)
6. Ensure limit applies to both Anthropic's built-in web fetch and any custom implementation
</functional-requirements>

<technical-requirements>
1. Define MAX_RESPONSE_SIZE constant (5 * 1024 * 1024) in appropriate module
2. Check resp.headers.get('content-length') before reading body
3. Use streaming read with size enforcement (e.g., aiohttp ClientSession with max_size)
4. Add size validation after read to catch cases where Content-Length wasn't set
5. Update web fetch error handling to include size limit violations
6. Add configuration option to allow adjusting limit if needed (optional)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/builtin_tools.py` or equivalent - Add web fetch size limit
- `core/constants.py` or create - Define MAX_RESPONSE_SIZE constant
- `config/tools_config.py` - Add optional max_fetch_size configuration
- `tests/test_webfetch.py` - Add tests for size limit enforcement
</files-to-modify>

<reference-implementation>
From /Users/williamcory/agent-bak-bak/tool/webfetch.go:

```go
const (
    MaxResponseSize   = 5 * 1024 * 1024 // 5MB
    DefaultWebTimeout = 30 * time.Second
    MaxWebTimeout     = 120 * time.Second
)

// Check content length
if resp.ContentLength > MaxResponseSize {
    return ToolResult{}, fmt.Errorf("response too large (exceeds 5MB limit)")
}

// Read response body with size limit
body, err := io.ReadAll(io.LimitReader(resp.Body, MaxResponseSize+1))
if err != nil {
    return ToolResult{}, fmt.Errorf("failed to read response: %v", err)
}

if len(body) > MaxResponseSize {
    return ToolResult{}, fmt.Errorf("response too large (exceeds 5MB limit)")
}
```

Python equivalent approach:
```python
MAX_RESPONSE_SIZE = 5 * 1024 * 1024  # 5MB

# Check content-length header before download
content_length = response.headers.get('content-length')
if content_length and int(content_length) > MAX_RESPONSE_SIZE:
    raise ValueError("response too large (exceeds 5MB limit)")

# Read with size limit
data = await response.read()
if len(data) > MAX_RESPONSE_SIZE:
    raise ValueError("response too large (exceeds 5MB limit)")
```
</reference-implementation>

<example-error-message>
```
Error: Failed to fetch https://example.com/large-file.zip
Reason: response too large (exceeds 5MB limit)

The requested URL returned a response larger than 5MB. Web fetch operations
are limited to prevent memory issues. Consider:
- Downloading the file directly instead of fetching via web fetch
- Using a different tool for large file operations
- Accessing a summary or API endpoint instead of raw data
```
</example-error-message>

## Acceptance Criteria

<criteria>
- [ ] MAX_RESPONSE_SIZE constant defined and set to 5MB
- [ ] Content-Length header checked before downloading (if present)
- [ ] Streaming read enforces size limit during download
- [ ] Post-read validation catches cases without Content-Length
- [ ] Clear error message shown when limit exceeded
- [ ] All fetch formats (text, markdown, html) respect limit
- [ ] Tests verify both Content-Length rejection and streaming limit
- [ ] Tests verify error message format
- [ ] Documentation updated to mention 5MB limit
- [ ] No performance regression for small fetches
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

## Testing Strategy

<test-cases>
1. **Test size limit via Content-Length header**
   - Mock response with Content-Length: 10485760 (10MB)
   - Verify rejection before download
   - Verify error message format

2. **Test size limit via streaming read**
   - Mock response without Content-Length header
   - Stream data exceeding 5MB
   - Verify download stops at limit
   - Verify error message format

3. **Test successful fetch under limit**
   - Fetch content under 5MB
   - Verify successful completion
   - Verify no errors

4. **Test edge case: exactly 5MB**
   - Fetch exactly 5242880 bytes
   - Verify successful completion

5. **Test edge case: 5MB + 1 byte**
   - Fetch 5242881 bytes
   - Verify rejection with error

6. **Test all format types**
   - Test text, markdown, and html formats
   - Verify limit applies to all
</test-cases>

## Security Considerations

<security-notes>
- Size limit prevents memory exhaustion attacks
- Protects against malicious servers streaming infinite data
- Prevents accidental download of large files (videos, datasets)
- Consistent with industry best practices (GitHub API: 5MB, many CDNs: 1-10MB)
- Consider logging when limit is hit for monitoring
- May want to make limit configurable for enterprise deployments
- Ensure limit is documented in API/tool documentation
</security-notes>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_webfetch.py -v` to ensure all tests pass
3. Run `pytest tests/` to check for regressions
4. Test manually with a URL known to exceed 5MB
5. Verify error message is clear and actionable
6. Update CLAUDE.md if new constants or patterns were introduced
7. Rename this file from `28-web-fetch-size-limit.md` to `28-web-fetch-size-limit.complete.md`
</completion>
