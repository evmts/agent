---
name: test-debugging
description: Debug Playwright E2E test failures. Use when tests fail, are flaky, or run slowly. Automatically invoked for questions about test failures, test results, e2e tests, or Playwright issues.
---

# Test Debugging

Debug Playwright E2E test failures using the playwright-mcp server.

## Quick Start

```
# Get overall status
playwright-mcp: test_summary()

# See what failed
playwright-mcp: list_failures(limit=20)

# Group failures by error pattern
playwright-mcp: failure_patterns()
```

## Available Tools

| Tool | Purpose |
|------|---------|
| `test_summary` | Overall pass/fail counts, duration |
| `list_failures` | Failed tests with error messages |
| `test_details` | Full details for a specific test |
| `failure_patterns` | Group failures by error type |
| `flaky_tests` | Tests that passed on retry |
| `slow_tests` | Performance bottlenecks |
| `test_artifacts` | Traces, screenshots, videos |
| `list_test_files` | All test files with counts |
| `view_attachment` | View console/network logs |

## Debugging Workflows

### 1. Investigate Test Failure

```
1. playwright-mcp: test_summary()
2. playwright-mcp: list_failures()
3. playwright-mcp: test_details(testTitle="the failing test")
4. playwright-mcp: view_attachment(attachmentPath="...")
```

### 2. Find Common Issues

```
playwright-mcp: failure_patterns()
```

This groups failures by error message pattern, helping identify:
- Common root causes
- Systematic issues
- Infrastructure problems

### 3. Identify Flaky Tests

```
playwright-mcp: flaky_tests()
```

Flaky tests (passed on retry) may indicate:
- Race conditions
- Timing issues
- Unstable selectors
- Network dependencies

### 4. Performance Analysis

```
playwright-mcp: slow_tests(threshold=5000, limit=10)
```

Shows tests taking longer than threshold, useful for:
- Identifying performance bottlenecks
- Finding tests that need optimization
- Detecting infrastructure issues

## Common Failure Patterns

### Pattern: Selector Not Found

**Error:** `locator.click: Target closed` or `Timeout exceeded`

**Causes:**
- Element not rendered
- Wrong selector
- Page navigation issue
- Slow page load

**Debug:**
```
playwright-mcp: test_details(testTitle="failing test")
# Check for screenshots and traces in artifacts
```

### Pattern: Network Error

**Error:** `net::ERR_CONNECTION_REFUSED` or similar

**Causes:**
- Server not running
- Wrong URL
- CORS issues
- Certificate problems

**Debug:**
```
playwright-mcp: view_attachment(attachmentPath=".../network-errors.json")
```

### Pattern: Assertion Failed

**Error:** `expect(received).toBe(expected)`

**Causes:**
- Wrong expected value
- State not updated
- Race condition
- Data dependency

### Pattern: Timeout

**Error:** `Test timeout of 30000ms exceeded`

**Causes:**
- Slow server response
- Infinite loop
- Deadlock
- Heavy computation

## Test Files

View all test files:

```
playwright-mcp: list_test_files()
```

E2E tests are in:
- `e2e/cases/*.spec.ts` - Test specifications
- `e2e/fixtures.ts` - Shared fixtures
- `e2e/global-setup.ts` - Global setup
- `e2e/global-teardown.ts` - Global teardown

## Artifacts

Test artifacts are stored in `test-results/`:
- **Screenshots:** Captured on failure
- **Videos:** Full test recording
- **Traces:** Playwright trace viewer files
- **Logs:** Console and network logs

View artifacts:
```
playwright-mcp: test_artifacts(testTitle="optional filter")
playwright-mcp: view_attachment(attachmentPath="...")
```

## Running Tests

```bash
# Run all tests
bun playwright test

# Run specific test file
bun playwright test e2e/cases/auth.spec.ts

# Run tests matching pattern
bun playwright test -g "should login"

# Run with UI mode (debugging)
bun playwright test --ui

# Run with trace on
bun playwright test --trace on
```

## Debug Report Template

```markdown
## Test Failure Report

**Test:** [full test name]
**File:** [file:line]
**Status:** FAILED

### Error
```
[error message]
```

### Root Cause
[What caused the failure]

### Evidence
- Screenshot: [path if available]
- Trace: [path if available]
- Network logs: [relevant info]

### Fix
[What needs to change]

### Notes
[Additional context]
```

## Tips

1. **Check failure patterns first** - identifies common issues
2. **Use trace files** - Playwright traces show step-by-step execution
3. **Check flaky tests** - they indicate real issues
4. **Review slow tests** - they might be symptoms of problems
5. **Run with --ui for debugging** - interactive debugging mode
