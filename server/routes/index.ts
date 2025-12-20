/**
 * Route registration.
 */

import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';
import issues from './issues';

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// Mount routes
app.route('/sessions', sessions);
app.route('/session', messages);
app.route('/pty', pty);
app.route('/repos', issues);

export default app;
