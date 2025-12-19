# Duplicate Tool Call Detection

## Overview

Plue's agent system includes automatic duplicate detection to prevent redundant tool calls. When an agent tries to read the same file twice, run identical grep queries, or perform other duplicate operations, the system returns cached results instead of re-executing the tool.

## How It Works

### Architecture

1. **ToolCallTracker**: A session-aware tracker that maintains history of recent tool calls
2. **Tool Wrapping**: Each tool is wrapped with duplicate detection logic before being passed to the AI SDK
3. **Cache & Return**: When a duplicate is detected, the previous result is returned with a cache note

### Per-Session Tracking

Each session maintains its own independent history:
- Different sessions can read the same file without triggering duplicate detection
- History is bounded (default: last 50 calls) to prevent memory leaks
- Entries expire after a configurable TTL (default: 5 minutes)

### Tool-Specific Similarity Rules

Different tools have different definitions of "duplicate":

| Tool | Duplicate If... | Notes |
|------|----------------|-------|
| `readFile` | Same `filePath` | Ignores offset/limit - reading any part of the same file is duplicate |
| `grep` | Same `pattern`, `path`, `glob`, `multiline`, `caseInsensitive` | Context lines don't affect similarity |
| `writeFile` | Same `filePath` AND same `content` | Writing different content to same file is NOT duplicate |
| `multiedit` | Same `edits` array | Compares full edit objects |
| `webFetch` | Same `url` | URL must match exactly |
| `unifiedExec` | Never | Commands have side effects, never cached |
| `writeStdin` | Never | Interactive operations, never cached |
| `closePtySession` | Never | Stateful operation, never cached |
| `listPtySessions` | Never | Query operation that should always be fresh |

### Generic Fallback

For tools without custom similarity rules, a generic algorithm is used:
- Compares all argument properties
- Considers calls similar if more than 50% of properties match
- OR if critical identifiers (id, name, path) match exactly

## Usage

### Automatic (Default)

Duplicate detection is enabled by default for all agent calls:

```typescript
import { streamAgent } from './ai/agent';

// Duplicate detection is ON by default
for await (const event of streamAgent(messages, {
  sessionId: 'user-session-123',
})) {
  // Handle events...
}
```

### Disable for Specific Calls

```typescript
// Disable duplicate detection
for await (const event of streamAgent(messages, {
  sessionId: 'user-session-123',
  enableDuplicateDetection: false,
})) {
  // Handle events...
}
```

### Persisted Stream (Database-Backed)

The `persistedStreamAgent` automatically uses the session ID for duplicate detection:

```typescript
import { persistedStreamAgent } from './ai/agent';

for await (const event of persistedStreamAgent(
  sessionId,
  messageId,
  messages,
  options
)) {
  // Duplicate detection is automatically enabled using sessionId
}
```

## Identifying Cached Results

When a tool result comes from cache, it includes:
1. A `cached: true` flag in the StreamEvent
2. A timestamp note in the result: `[Cached result from 10:23:45 AM]`

```typescript
for await (const event of streamAgent(messages, options)) {
  if (event.type === 'tool_result') {
    if (event.cached) {
      console.log('This result came from cache!');
    }
  }
}
```

## Memory Management

### Bounded History

Each session stores a maximum of 50 tool calls (configurable). When this limit is exceeded, the oldest calls are removed.

### Time-Based Expiration

Tool calls older than 5 minutes (configurable) are automatically removed during cleanup operations.

### Manual Cleanup

```typescript
import { getToolCallTracker } from './ai/tools';

const tracker = getToolCallTracker();

// Clear specific session
tracker.clearSession('user-session-123');

// Clear all sessions
tracker.clearAll();

// Get statistics
const stats = tracker.getStats();
console.log(`Tracking ${stats.totalSessions} sessions, ${stats.totalCalls} calls`);
```

## Testing

### Unit Tests

Run the tracker unit tests:

```bash
bun test ai/tools/tracker.test.ts
```

### Integration Tests

Run the agent integration tests:

```bash
bun test ai/agent-duplicate-detection.test.ts
```

### Manual Testing

Create a simple test agent that reads the same file twice:

```typescript
import { runAgent } from './ai/agent';

for await (const event of runAgent('Read /Users/williamcory/plue/README.md twice', {
  sessionId: 'test',
})) {
  if (event.type === 'tool_result') {
    console.log('Cached:', event.cached);
  }
}
```

## Configuration

### Custom Tracker

For testing or special use cases, you can provide a custom tracker:

```typescript
import { ToolCallTracker, setToolCallTracker } from './ai/tools';

// Create custom tracker with different limits
const customTracker = new ToolCallTracker(
  100, // maxHistoryPerSession
  10 * 60 * 1000 // maxAgeMs (10 minutes)
);

setToolCallTracker(customTracker);
```

### Custom Similarity Checkers

To add custom similarity logic for new tools, edit `ai/tools/tracker.ts`:

```typescript
const similarityCheckers: Record<string, SimilarityChecker> = {
  // ... existing checkers ...

  myNewTool: (current, previous) => {
    // Custom logic
    return current.criticalParam === previous.criticalParam;
  },
};
```

## Benefits

1. **Token Savings**: Avoid sending duplicate results to the LLM
2. **Performance**: Skip expensive operations like file reads and web fetches
3. **User Experience**: Faster agent responses for redundant operations
4. **Observability**: Cached results are clearly marked in the stream

## Limitations

1. **Same Session Only**: Duplicate detection doesn't work across sessions
2. **Fresh Start**: History clears when the server restarts (in-memory only)
3. **File Changes**: Won't detect if a file was modified between duplicate reads
4. **Complex Patterns**: Generic fallback may have false positives for complex args

## Future Improvements

- [ ] Persist tracker state to database for cross-restart persistence
- [ ] Add file modification time checking for read operations
- [ ] Cross-session caching for immutable resources (e.g., web fetches)
- [ ] Configurable similarity thresholds per tool
- [ ] Metrics and observability dashboard
