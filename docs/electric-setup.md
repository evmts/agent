# ElectricSQL Real-Time Sync Setup

## Overview

Plue uses ElectricSQL to provide real-time synchronization of agent messages and parts across all connected clients. This enables collaborative viewing of AI agent work in progress.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│   Clients   │◄────────┤ Hono API     │◄────────┤  ElectricSQL │
│  (Browser)  │  Shapes │  /shape      │  Proxy  │   Service    │
└─────────────┘         └──────────────┘         └──────────────┘
                              │                          │
                              │                          │
                              └──────────┬───────────────┘
                                         │
                                  ┌──────▼──────┐
                                  │  PostgreSQL │
                                  │  (logical   │
                                  │  replication)│
                                  └─────────────┘
```

## Prerequisites

### PostgreSQL Configuration

ElectricSQL requires PostgreSQL with logical replication enabled. This is already configured in `docker-compose.yaml`:

```yaml
postgres:
  command:
    - -c
    - wal_level=logical
```

### Environment Variables

Ensure these variables are set in your `.env` file:

```bash
# Database (Electric requires specific format)
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric

# ElectricSQL service URL
ELECTRIC_URL=http://localhost:3000

# Client-side URLs (for browser access)
PUBLIC_CLIENT_API_URL=http://localhost:4000
PUBLIC_CLIENT_ELECTRIC_URL=http://localhost:3000
```

## Server-Side Configuration

### 1. Electric Proxy Endpoint

The Hono API server proxies requests to Electric's shape API. This is configured in `/Users/williamcory/plue/server/index.ts`:

```typescript
// ElectricSQL Shape API proxy
app.get('/shape', async (c) => {
  const request = c.req.raw;
  const originUrl = new URL(`${ELECTRIC_URL}/v1/shape`);

  // Forward query parameters to Electric
  const url = new URL(request.url);
  url.searchParams.forEach((value, key) => {
    originUrl.searchParams.set(key, value);
  });

  return proxy(originUrl.toString(), {
    ...request,
    headers: {
      ...request.headers,
    },
  });
});
```

### 2. CORS Configuration

The server is configured to expose Electric-specific headers:

```typescript
app.use('*', cors({
  origin: '*',
  exposeHeaders: [
    'electric-offset',
    'electric-handle',
    'electric-schema',
    'electric-cursor',
    'electric-up-to-date',
  ],
}));
```

### 3. Shape Configuration Utilities

Helper functions in `/Users/williamcory/plue/server/electric.ts` define shapes for each table:

```typescript
// Get messages for a session
messagesShapeConfig(sessionId: string)

// Get parts for a session (primary streaming shape)
partsShapeConfig(sessionId: string)

// Get sessions (optionally filtered)
sessionsShapeConfig(where?: string)
```

## Client-Side Integration

### 1. Shape Hooks (Type Definitions)

The file `/Users/williamcory/plue/ui/lib/electric.ts` provides TypeScript type definitions and shape configurations for client-side components.

**IMPORTANT**: The hooks are currently type-only stubs. To use them in your React/Astro components, you'll need to:

1. Create a client-side wrapper component
2. Import `@electric-sql/react` directly in that component
3. Use the provided `*ShapeConfig()` functions with the `useShape()` hook from `@electric-sql/react`

Example client component (`ui/components/SessionViewer.tsx`):

```typescript
import { useShape } from '@electric-sql/react';
import { messagesShapeConfig, partsShapeConfig } from '../lib/electric';
import type { MessageRow, PartRow } from '../lib/electric';

export function SessionViewer({ sessionId }: { sessionId: string }) {
  const { data: messages } = useShape<MessageRow>(messagesShapeConfig(sessionId));
  const { data: parts } = useShape<PartRow>(partsShapeConfig(sessionId));

  // Group parts by message
  const messageMap = new Map<string, { message: MessageRow; parts: PartRow[] }>();

  messages.forEach(msg => {
    if (!messageMap.has(msg.id)) {
      messageMap.set(msg.id, { message: msg, parts: [] });
    }
  });

  parts.forEach(part => {
    const entry = messageMap.get(part.message_id);
    if (entry) {
      entry.parts.push(part);
    }
  });

  return (
    <div>
      {Array.from(messageMap.values()).map(({ message, parts }) => (
        <div key={message.id}>
          <strong>{message.role}:</strong>
          {parts.map(part => (
            <div key={part.id}>
              {part.type === 'text' && <p>{part.text}</p>}
              {part.type === 'tool' && <pre>{part.tool_name}</pre>}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}
```

### 2. Available Shape Configurations

The following shape configuration functions return shape parameters for use with `@electric-sql/react`:

#### Session Shapes
- `sessionsShapeConfig(where?)` - Shape config for sessions (optionally filtered)
  ```typescript
  const { data } = useShape<SessionRow>(sessionsShapeConfig());
  ```

#### Message Shapes
- `messagesShapeConfig(sessionId)` - Shape config for messages in a session
  ```typescript
  const { data } = useShape<MessageRow>(messagesShapeConfig(sessionId));
  ```

#### Part Shapes (Primary for Streaming)
- `partsShapeConfig(sessionId)` - Shape config for parts in a session
  ```typescript
  const { data } = useShape<PartRow>(partsShapeConfig(sessionId));
  ```

#### Other Shapes
- `snapshotHistoryShapeConfig(sessionId)` - Shape config for snapshot history
- `subtasksShapeConfig(sessionId)` - Shape config for subtasks

### 3. Implementing Abort Management

You can implement automatic shape cleanup using a custom hook pattern:

```typescript
import { useShape } from '@electric-sql/react';
import { useEffect, useRef } from 'react';

function useShapeWithAbort<T>(config: any, timeout: number = 1000) {
  const controllerRef = useRef<AbortController>();
  const mountsRef = useRef(0);

  useEffect(() => {
    mountsRef.current++;
    return () => {
      mountsRef.current--;
      if (mountsRef.current === 0) {
        setTimeout(() => {
          controllerRef.current?.abort();
        }, timeout);
      }
    };
  }, [timeout]);

  return useShape<T>({
    ...config,
    signal: controllerRef.current?.signal,
  });
}
```

## Data Flow

### Writing Data (Agent Execution)

1. Agent executes and calls `appendMessage()` or `savePart()`
2. Data is written to PostgreSQL via `db/agent-state.ts`
3. PostgreSQL logical replication captures the change
4. ElectricSQL broadcasts change to all subscribed clients
5. Client shapes update automatically via `useShape()` hooks

### Reading Data (Client)

1. Component subscribes using `useSessionRealtime(sessionId)`
2. Electric establishes shape subscription via `/shape` proxy
3. Electric sends initial snapshot of data
4. Electric streams incremental updates as they occur
5. React hooks trigger re-renders with new data

## Filtering and Security

### Session-Based Filtering

All shapes are filtered by `session_id` to ensure clients only receive data for their session:

```typescript
// Good: Only gets parts for this session
usePartsShape('session-123')

// Results in SQL: WHERE session_id = 'session-123'
```

### No Data Leakage

The schema enforces foreign key constraints with `ON DELETE CASCADE`, ensuring:
- Deleting a session removes all messages, parts, subtasks
- Clients can't access data from other sessions
- Shape filters prevent cross-session data access

## Testing Real-Time Sync

### Local Development

1. Start services:
   ```bash
   bun run dev:all
   # This starts: postgres, electric, astro dev, and API server
   ```

2. Open two browser tabs to the same session

3. Send a message in one tab

4. Both tabs should see the message and streaming parts in real-time

### Verification Checklist

- [ ] PostgreSQL has `wal_level=logical` (check docker-compose.yaml)
- [ ] Electric service is running on port 3000
- [ ] API server proxies `/shape` endpoint correctly
- [ ] Client can fetch initial shape snapshot
- [ ] Client receives real-time updates when parts are written
- [ ] Multiple clients see the same updates simultaneously
- [ ] Shape subscriptions abort after timeout when unmounted

## Troubleshooting

### Electric Connection Errors

If you see connection errors:

```bash
# Check Electric is running
curl http://localhost:3000/v1/health

# Check proxy endpoint
curl 'http://localhost:4000/shape?table=sessions'
```

### Shape Not Updating

If shapes don't update in real-time:

1. Verify logical replication is enabled:
   ```sql
   SHOW wal_level;  -- Should return 'logical'
   ```

2. Check Electric logs:
   ```bash
   docker compose logs electric -f
   ```

3. Verify data is being written to PostgreSQL:
   ```sql
   SELECT * FROM parts WHERE session_id = 'your-session-id' ORDER BY sort_order;
   ```

### CORS Issues

If you see CORS errors in browser console:

1. Check API server CORS config includes Electric headers
2. Verify `PUBLIC_CLIENT_API_URL` matches your API origin
3. Ensure Electric proxy is forwarding headers correctly

## Production Considerations

### Electric URL Configuration

For production, set environment variables:

```bash
# Server-side (internal service URL)
ELECTRIC_URL=http://electric:3000

# Client-side (browser-accessible URL)
PUBLIC_CLIENT_ELECTRIC_URL=https://your-domain.com/electric
```

### Scaling

- ElectricSQL handles multiple clients efficiently
- PostgreSQL logical replication has minimal overhead
- Consider connection pooling for high-traffic scenarios
- Monitor Electric memory usage for large shape subscriptions

### Security

Current setup has no authentication. For production:

1. Add authentication to `/shape` endpoint
2. Validate session access based on user permissions
3. Use JWTs or session cookies to verify access
4. Filter shapes based on authenticated user context

## Advanced Usage

### Custom Shapes

Define custom shapes in `server/electric.ts`:

```typescript
export function customShapeConfig(params: any): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'your_table',
      where: `your_column = '${params.value}'`,
      columns: 'id,name,created_at', // Optional: limit columns
    },
  };
}
```

### Preloading for SSR

Preload shapes during SSR for instant hydration:

```astro
---
// pages/session/[id].astro
import { preloadShape } from '@electric-sql/react';
import { messagesShapeConfig, partsShapeConfig } from '../lib/electric';
import SessionViewer from '../components/SessionViewer';

const sessionId = Astro.params.id;

// Preload shapes for instant hydration
await preloadShape(messagesShapeConfig(sessionId));
await preloadShape(partsShapeConfig(sessionId));
---

<html>
  <body>
    <SessionViewer sessionId={sessionId} client:load />
  </body>
</html>
```

### Live SSE Mode

For ultra-low latency, use experimental live SSE:

```typescript
export function partsShapeConfig(sessionId: string): ShapeOptions<PartRow> {
  return {
    // ... other config
    // @ts-ignore - experimental feature
    experimentalLiveSse: true,
  };
}
```

## References

- [ElectricSQL Documentation](https://electric-sql.com/docs)
- [Electric React Hooks](https://electric-sql.com/docs/api/clients/react)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
