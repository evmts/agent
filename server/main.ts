/**
 * API Server entry point.
 *
 * NOTE: Most functionality has moved to Zig server (server-zig).
 * This TypeScript server only handles:
 * - workflows (dispatch, rerun, definitions)
 * - runners (job/run status updates)
 *
 * SSH server, PTY, and repo watching are now handled by Zig.
 */

import app from './index';
import { startSessionCleanup } from './lib/session';

const port = Number(process.env.PORT) || 4000;
const hostname = process.env.HOST || '0.0.0.0';

console.log(`Starting API server on ${hostname}:${port}`);

// Start session cleanup background job
startSessionCleanup();

const _server = Bun.serve({
  fetch(req) {
    return app.fetch(req);
  },
  port,
  hostname,
});

console.log(`API server running at http://${hostname}:${port}`);

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down server...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Shutting down server...');
  process.exit(0);
});