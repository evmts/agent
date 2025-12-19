/**
 * Server routes for pull request handling
 */

import { Hono } from 'hono';

const app = new Hono();

// Placeholder routes - actual PR handling is done through Astro API routes
app.get('/health', (c) => {
  return c.json({ status: 'ok' });
});

export default app;
