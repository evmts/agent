/**
 * Route registration.
 *
 * Only keeps routes that don't have Zig parity:
 * - workflows (missing dispatch, rerun, definitions in Zig)
 * - runners (missing job/run status updates in Zig)
 */

import { Hono } from 'hono';
import runners from './runners';
import workflows from './workflows';

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// Workflow system routes (Zig missing: dispatch, rerun, definitions)
app.route('/runners', runners);
app.route('/', workflows); // Mounts at /:user/:repo/workflows/*

export default app;
