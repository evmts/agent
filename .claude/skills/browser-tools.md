# Browser Tools

This skill covers browser automation via the Swift app integration, including accessibility snapshots, element interaction, and navigation.

## Overview

The browser tools connect to a Swift macOS app that provides browser automation capabilities via an HTTP API. The agent uses these tools to interact with web pages through an accessibility-based element reference system.

## Key Files

| File | Purpose |
|------|---------|
| `agent/browser_client.py` | HTTP client for browser API |
| `agent/agent.py:273-408` | Browser tool wrappers |

## Architecture

```
Agent Tools
    │
    └── BrowserClient (HTTP)
            │
            └── Swift App (localhost:48484)
                    │
                    └── Browser (macOS accessibility API)
```

## Constants

```python
# agent/browser_client.py
DEFAULT_PORT = 48484
PORT_FILE_PATH = Path.home() / ".plue" / "browser-api.port"
REQUEST_TIMEOUT_SECONDS = 30.0
BASE_URL_TEMPLATE = "http://127.0.0.1:{port}"
```

## Port Discovery

The client discovers the browser API port in this order:

1. **Environment variable**: `BROWSER_API_PORT`
2. **Port file**: `~/.plue/browser-api.port`
3. **Default**: `48484`

## BrowserClient API

### Creating the Client

```python
from agent.browser_client import get_browser_client

# Singleton instance
client = get_browser_client()

# Or with explicit port
from agent.browser_client import BrowserClient
client = BrowserClient(port=48484)
```

### Operations

| Method | Description | Returns |
|--------|-------------|---------|
| `status()` | Check connection | `{success, connected}` |
| `snapshot(include_hidden, max_depth)` | Get accessibility tree | `{success, text_tree, url, title, element_count}` |
| `click(ref)` | Click element | `{success, error?}` |
| `type_text(ref, text, clear)` | Type into element | `{success, error?}` |
| `scroll(direction, amount)` | Scroll page | `{success}` |
| `extract_text(ref)` | Get element text | `{success, text}` |
| `screenshot()` | Capture page | `{success, image_base64}` |
| `navigate(url)` | Go to URL | `{success}` |

## Element Reference System

The accessibility snapshot returns a text tree with element references:

```
Page Title - example.com
├─ button "Login" [e1]
├─ input "Search" [e2]
├─ link "Home" [e3]
│  └─ text "Home"
├─ div "Content"
│  ├─ heading "Welcome" [e4]
│  └─ paragraph [e5]
```

References like `e1`, `e2` are used to target elements in subsequent operations.

## Agent Tool Wrappers

The browser client is wrapped as agent tools with error handling:

### browser_snapshot

```python
@agent.tool_plain
async def browser_snapshot(
    include_hidden: bool = False,
    max_depth: int = 50,
) -> str:
    """Take accessibility snapshot of browser page.

    The snapshot shows the page structure with clickable/interactive elements
    labeled with refs like 'e1', 'e2', etc. Use these refs with other browser tools.

    Args:
        include_hidden: Include hidden elements in snapshot
        max_depth: Maximum depth of element tree to traverse
    """
    try:
        client = get_browser_client()
        result = await client.snapshot(include_hidden, max_depth)
        if result.get("success"):
            return result.get("text_tree", "Empty snapshot")
        return f"Error: {result.get('error', 'Unknown error')}"
    except httpx.ConnectError:
        return "Browser not connected. Ensure the Plue app is running with a browser tab open."
    except httpx.TimeoutException:
        return "Browser operation timed out."
```

### browser_click

```python
@agent.tool_plain
async def browser_click(ref: str) -> str:
    """Click an element by its ref (e.g., 'e1', 'e23').

    Use browser_snapshot first to see available elements and their refs.

    Args:
        ref: Element reference from snapshot (e.g., 'e1')
    """
```

### browser_type

```python
@agent.tool_plain
async def browser_type(ref: str, text: str, clear: bool = False) -> str:
    """Type text into an input element.

    Args:
        ref: Element reference from snapshot (e.g., 'e5')
        text: Text to type into the element
        clear: Whether to clear existing content first
    """
```

### browser_scroll

```python
@agent.tool_plain
async def browser_scroll(direction: str = "down", amount: int = 300) -> str:
    """Scroll the browser page.

    Args:
        direction: Scroll direction - 'up', 'down', 'left', or 'right'
        amount: Scroll amount in pixels
    """
```

### browser_extract

```python
@agent.tool_plain
async def browser_extract(ref: str) -> str:
    """Extract text content from an element.

    Args:
        ref: Element reference from snapshot (e.g., 'e10')
    """
```

### browser_screenshot

```python
@agent.tool_plain
async def browser_screenshot() -> str:
    """Take a screenshot of the browser page.

    Returns base64-encoded PNG image data.
    """
```

### browser_navigate

```python
@agent.tool_plain
async def browser_navigate(url: str) -> str:
    """Navigate the browser to a URL.

    Args:
        url: URL to navigate to (e.g., 'https://example.com')
    """
```

## Error Handling

All browser tools handle these error conditions:

```python
try:
    result = await client.operation()
    if result.get("success"):
        return format_result(result)
    return f"Error: {result.get('error', 'Unknown error')}"
except httpx.ConnectError:
    return "Browser not connected. Ensure the Plue app is running with a browser tab open."
except httpx.TimeoutException:
    return "Browser operation timed out."
```

## Workflow Example

Typical browser automation workflow:

```python
# 1. Navigate to page
await browser_navigate("https://example.com/login")

# 2. Take snapshot to see elements
snapshot = await browser_snapshot()
# Returns tree with elements like:
# input "Username" [e1]
# input "Password" [e2]
# button "Login" [e3]

# 3. Fill in form
await browser_type("e1", "user@example.com")
await browser_type("e2", "password123")

# 4. Click login
await browser_click("e3")

# 5. Take another snapshot to verify result
result = await browser_snapshot()
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BROWSER_API_PORT` | Port for browser API | `48484` |

### Port File

The Swift app writes its port to `~/.plue/browser-api.port` when starting.

## Requirements

1. **Plue Swift App**: Must be running with browser extension
2. **macOS**: Uses macOS accessibility APIs
3. **Browser Tab**: Must have an active browser tab open

## Best Practices

1. **Always snapshot first**: Get element refs before interacting
2. **Handle connection errors**: Check if Plue app is running
3. **Use refs correctly**: Refs like `e1` must match snapshot
4. **Wait after navigation**: Page may need time to load
5. **Clear input fields**: Use `clear=True` when replacing text

## Troubleshooting

### "Browser not connected"
- Ensure Plue app is running
- Check browser has an active tab
- Verify port in `~/.plue/browser-api.port`

### "Operation timed out"
- Page may be slow to respond
- Try increasing timeout
- Check browser isn't frozen

### "Element not found"
- Take fresh snapshot
- Ref may have changed after page update
- Element may be hidden or off-screen

## Related Skills

- [tools-development.md](./tools-development.md) - Tool patterns
- [agent-system.md](./agent-system.md) - Tool registration
