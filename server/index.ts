/**
 * Server module - Hono app with Bun.serve().
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import routes from './routes';

export { ServerEventBus, getServerEventBus, setServerEventBus } from './event-bus';

// Create Hono app
const app = new Hono();

// Middleware
app.use('*', logger());
app.use('*', cors());

// Mount routes
app.route('/', routes);

// Error handling
app.onError((err, c) => {
  console.error('Server error:', err);
  return c.json(
    {
      error: err.message,
      type: err.name,
    },
    500
  );
});

// 404 handler
app.notFound((c) => {
  return c.json({ error: 'Not found' }, 404);
});

export { app };
export default app;
