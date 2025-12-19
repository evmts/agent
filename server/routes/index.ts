/**
 * Route registration.
 */

import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// Mount routes
app.route('/sessions', sessions);
app.route('/session', messages);
app.route('/pty', pty);

export default app;
