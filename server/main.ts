/**
 * API Server entry point.
 *
 * Starts the Hono server using Bun.serve() with WebSocket support.
 */

import app from './index';
import { isPtyWebSocketRequest, createPtyWebSocketHandler } from './routes/pty';

const port = Number(process.env.PORT) || 4000;
const hostname = process.env.HOST || '0.0.0.0';

console.log(`Starting API server on ${hostname}:${port}`);

const ptyWsHandler = createPtyWebSocketHandler();

const server = Bun.serve({
  fetch(req, server) {
    // Check for PTY WebSocket upgrade
    const ptyWs = isPtyWebSocketRequest(req);
    if (ptyWs) {
      const upgraded = server.upgrade(req, {
        data: { ptyId: ptyWs.ptyId },
      });
      if (upgraded) {
        return undefined;
      }
      return new Response('WebSocket upgrade failed', { status: 500 });
    }

    // Handle regular HTTP requests with Hono
    return app.fetch(req);
  },
  websocket: {
    open(ws) {
      ptyWsHandler.open(ws as any);
    },
    message(ws, message) {
      ptyWsHandler.message(ws as any, message as any);
    },
    close(ws) {
      ptyWsHandler.close(ws as any);
    },
  },
  port,
  hostname,
});

console.log(`API server running at http://${hostname}:${port}`);
