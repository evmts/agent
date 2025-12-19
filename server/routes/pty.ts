/**
 * PTY WebSocket routes for terminal connections.
 */

import { Hono } from 'hono';
import { getPtyManager, } from '../../ai/tools/pty-manager';

const app = new Hono();

// Store active WebSocket connections per PTY session
const wsConnections = new Map<string, Set<WebSocket>>();

// Store PTY output readers
const outputReaders = new Map<string, { stop: () => void }>();

/**
 * Create a new PTY session.
 */
app.post('/', async (c) => {
  const body = await c.req.json<{
    cmd?: string;
    workdir?: string;
    shell?: string;
  }>();

  const manager = getPtyManager();

  try {
    const session = await manager.createSession({
      cmd: body.cmd ?? process.env.SHELL ?? '/bin/bash',
      workdir: body.workdir ?? process.cwd(),
      shell: body.shell,
      login: true,
    });

    return c.json({
      id: session.id,
      command: session.command,
      workdir: session.workdir,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to create PTY session';
    return c.json({ error: message }, 500);
  }
});

/**
 * List all PTY sessions.
 */
app.get('/', (c) => {
  const manager = getPtyManager();
  const sessions = manager.listSessions();
  return c.json({ sessions });
});

/**
 * Get PTY session info.
 */
app.get('/:id', (c) => {
  const id = c.req.param('id');
  const manager = getPtyManager();

  try {
    const status = manager.getProcessStatus(id);
    const sessions = manager.listSessions();
    const session = sessions.find((s) => s.id === id);

    if (!session) {
      return c.json({ error: 'Session not found' }, 404);
    }

    return c.json({
      ...session,
      ...status,
    });
  } catch (_error) {
    return c.json({ error: 'Session not found' }, 404);
  }
});

/**
 * Close a PTY session.
 */
app.delete('/:id', async (c) => {
  const id = c.req.param('id');
  const manager = getPtyManager();

  try {
    // Stop output reader if exists
    const reader = outputReaders.get(id);
    if (reader) {
      reader.stop();
      outputReaders.delete(id);
    }

    // Close all WebSocket connections
    const connections = wsConnections.get(id);
    if (connections) {
      for (const ws of connections) {
        ws.close();
      }
      wsConnections.delete(id);
    }

    await manager.closeSession(id);
    return c.json({ success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to close session';
    return c.json({ error: message }, 500);
  }
});

/**
 * Resize a PTY session.
 */
app.post('/:id/resize', async (c) => {
  const _id = c.req.param('id');
  const body = await c.req.json<{ cols: number; rows: number }>();

  // PTY resize is handled by the WebSocket message, but we expose this for direct API use
  // Note: The current PTYManager doesn't support resize, so this is a placeholder
  // You would need to use a proper PTY library like node-pty for resize support

  return c.json({ success: true, cols: body.cols, rows: body.rows });
});

export default app;

/**
 * WebSocket handler for PTY connections.
 * This should be used with Bun.serve's websocket option.
 */
export function createPtyWebSocketHandler() {
  return {
    open(ws: WebSocket & { data?: { ptyId: string } }) {
      const ptyId = ws.data?.ptyId;
      if (!ptyId) {
        ws.close(1008, 'Missing PTY ID');
        return;
      }

      console.log(`PTY WebSocket opened for session: ${ptyId}`);

      // Track connection
      if (!wsConnections.has(ptyId)) {
        wsConnections.set(ptyId, new Set());
      }
      wsConnections.get(ptyId)?.add(ws);

      // Start reading output from PTY
      startOutputReader(ptyId);
    },

    async message(ws: WebSocket & { data?: { ptyId: string } }, message: string | Buffer) {
      const ptyId = ws.data?.ptyId;
      if (!ptyId) return;

      const manager = getPtyManager();

      try {
        // Check if it's a JSON control message
        if (typeof message === 'string' && message.startsWith('{')) {
          try {
            const parsed = JSON.parse(message);
            if (parsed.type === 'resize') {
              // Handle resize - would need node-pty for proper support
              console.log(`PTY ${ptyId} resize:`, parsed.cols, parsed.rows);
              return;
            }
          } catch {
            // Not JSON, treat as input
          }
        }

        // Write input to PTY
        const input = typeof message === 'string' ? message : message.toString();
        await manager.writeInput(ptyId, input);
      } catch (error) {
        console.error(`Error writing to PTY ${ptyId}:`, error);
      }
    },

    close(ws: WebSocket & { data?: { ptyId: string } }) {
      const ptyId = ws.data?.ptyId;
      if (!ptyId) return;

      console.log(`PTY WebSocket closed for session: ${ptyId}`);

      // Remove from tracking
      const connections = wsConnections.get(ptyId);
      if (connections) {
        connections.delete(ws);
        if (connections.size === 0) {
          wsConnections.delete(ptyId);
          // Stop output reader if no more connections
          const reader = outputReaders.get(ptyId);
          if (reader) {
            reader.stop();
            outputReaders.delete(ptyId);
          }
        }
      }
    },
  };
}

/**
 * Start reading output from a PTY session and broadcasting to connected WebSockets.
 */
function startOutputReader(ptyId: string) {
  if (outputReaders.has(ptyId)) return;

  const manager = getPtyManager();
  let running = true;

  const read = async () => {
    while (running) {
      try {
        const output = await manager.readOutput(ptyId, 50, 65536);

        if (output) {
          const connections = wsConnections.get(ptyId);
          if (connections) {
            connections.forEach((ws) => {
              if (ws.readyState === WebSocket.OPEN) {
                ws.send(output);
              }
            });
          }
        }

        // Check if process has exited
        const status = manager.getProcessStatus(ptyId);
        if (!status.running) {
          // Send remaining output and close
          const remaining = await manager.readOutput(ptyId, 100, 65536);
          if (remaining) {
            const connections = wsConnections.get(ptyId);
            if (connections) {
              connections.forEach((ws) => {
                if (ws.readyState === WebSocket.OPEN) {
                  ws.send(remaining);
                }
              });
            }
          }
          break;
        }

        // Small delay to prevent busy loop
        await new Promise((resolve) => setTimeout(resolve, 10));
      } catch (_error) {
        // Session might have been closed
        break;
      }
    }

    outputReaders.delete(ptyId);
  };

  outputReaders.set(ptyId, {
    stop: () => {
      running = false;
    },
  });

  read();
}

/**
 * Check if a request is a PTY WebSocket upgrade.
 */
export function isPtyWebSocketRequest(req: Request): { ptyId: string } | null {
  const url = new URL(req.url);
  const match = url.pathname.match(/^\/pty\/([^/]+)\/ws$/);

  if (match?.[1] && req.headers.get('upgrade')?.toLowerCase() === 'websocket') {
    return { ptyId: match[1] };
  }

  return null;
}
