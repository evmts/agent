/**
 * Route registration.
 */

import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';
import issues from './issues';
import runners from './runners';
import workflows from './workflows';

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

// Workflow system routes
app.route('/runners', runners);
app.route('/', workflows); // Mounts at /:user/:repo/workflows/*

export default app;
