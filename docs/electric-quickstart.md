# ElectricSQL Quick Start Guide

## TL;DR

ElectricSQL is configured for real-time sync of agent messages and parts. The server proxy is ready, but you need to create client components to use the shapes.

## What's Done

- Server-side Electric proxy at `/shape`
- Shape configuration utilities
- TypeScript type definitions
- Comprehensive documentation

## What You Need to Do

### 1. Create a Client Component

```typescript
// ui/components/LiveAgentView.tsx
import { useShape } from '@electric-sql/react';
import { partsShapeConfig, type PartRow } from '../lib/electric';

export function LiveAgentView({ sessionId }: { sessionId: string }) {
  const { data: parts, isLoading } = useShape<PartRow>(
    partsShapeConfig(sessionId)
  );

  if (isLoading) return <div>Loading...</div>;

  return (
    <div>
      {parts.map(part => (
        <div key={part.id}>
          {part.type === 'text' && <p>{part.text}</p>}
        </div>
      ))}
    </div>
  );
}
```

### 2. Use in Astro Page

```astro
---
// ui/pages/session/[id].astro
import LiveAgentView from '../../components/LiveAgentView';
---

<html>
  <body>
    <LiveAgentView sessionId={Astro.params.id} client:load />
  </body>
</html>
```

### 3. Start Services

```bash
bun run dev:all
```

This starts:
- PostgreSQL (port 54321)
- ElectricSQL (port 3000)
- API server (port 4000)
- Astro dev server (port 5173)

### 4. Test It

1. Open http://localhost:5173/session/your-session-id
2. Open same URL in another tab
3. Send a message
4. Both tabs update in real-time

## Available Shape Configs

```typescript
import {
  sessionsShapeConfig,      // All sessions
  messagesShapeConfig,       // Messages in a session
  partsShapeConfig,          // Parts in a session (for streaming)
  snapshotHistoryShapeConfig,
  subtasksShapeConfig,
} from '../lib/electric';

import type {
  SessionRow,
  MessageRow,
  PartRow,
  // ... etc
} from '../lib/electric';
```

## Key Files

- `/Users/williamcory/plue/server/index.ts` - Electric proxy endpoint
- `/Users/williamcory/plue/server/electric.ts` - Shape utilities
- `/Users/williamcory/plue/ui/lib/electric.ts` - Client types & configs
- `/Users/williamcory/plue/docs/electric-setup.md` - Full documentation

## Common Patterns

### Subscribe to a session

```typescript
const { data: messages } = useShape<MessageRow>(
  messagesShapeConfig(sessionId)
);
```

### Group parts by message

```typescript
const { data: messages } = useShape<MessageRow>(messagesShapeConfig(sessionId));
const { data: parts } = useShape<PartRow>(partsShapeConfig(sessionId));

const messageMap = new Map();
messages.forEach(msg => messageMap.set(msg.id, { message: msg, parts: [] }));
parts.forEach(part => messageMap.get(part.message_id)?.parts.push(part));
```

### Filter sessions by project

```typescript
const { data: sessions } = useShape<SessionRow>(
  sessionsShapeConfig(`project_id = 'my-project'`)
);
```

## Troubleshooting

### "Cannot find module '@electric-sql/react'"

Make sure you're importing in a client component with `client:load` directive.

### "Shape endpoint returns 404"

Check API server is running:
```bash
curl http://localhost:4000/health
```

### "No real-time updates"

1. Check Electric is running: `curl http://localhost:3000/v1/health`
2. Check PostgreSQL: `docker compose ps postgres`
3. Check Electric logs: `docker compose logs electric -f`

## Next Steps

1. Read [electric-setup.md](./electric-setup.md) for complete guide
2. Read [electric-implementation-summary.md](./electric-implementation-summary.md) for details
3. Create your first real-time component
4. Test with multiple browser tabs

## Production Checklist

- [ ] Add authentication to `/shape` endpoint
- [ ] Validate session ownership
- [ ] Set production environment variables
- [ ] Test with realistic data volumes
- [ ] Monitor Electric memory usage
- [ ] Set up error handling for connection failures
