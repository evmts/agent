/**
 * API Server entry point.
 *
 * Starts the Hono server using Bun.serve() with WebSocket support.
 */

import app from './index';
import { isPtyWebSocketRequest, createPtyWebSocketHandler } from './routes/pty';
import { startSessionCleanup, getSession } from './lib/session';
import { startSSHServer } from './ssh/server';
import { repoWatcherService } from './lib/repo-watcher';

const SESSION_COOKIE_NAME = 'plue_session';

/**
 * Extract session cookie from request headers.
 */
function getSessionCookie(req: Request): string | null {
  const cookieHeader = req.headers.get('cookie');
  if (!cookieHeader) return null;

  const cookies = cookieHeader.split(';').map(c => c.trim());
  for (const cookie of cookies) {
    const [name, value] = cookie.split('=');
    if (name === SESSION_COOKIE_NAME) {
      return value;
    }
  }
  return null;
}

/**
 * Validate WebSocket authentication.
 * Returns user ID if authenticated, null otherwise.
 */
async function validateWebSocketAuth(req: Request): Promise<number | null> {
  const sessionKey = getSessionCookie(req);
  if (!sessionKey) return null;

  const sessionData = await getSession(sessionKey);
  if (!sessionData) return null;

  return sessionData.userId;
}

const port = Number(process.env.PORT) || 4000;
const hostname = process.env.HOST || '0.0.0.0';

console.log(`Starting API server on ${hostname}:${port}`);

// Start session cleanup background job
startSessionCleanup();

// Start repo watchers for jj sync
repoWatcherService.watchAllRepos().then(() => {
  console.log('[jj-sync] Repository watchers initialized');
}).catch((err) => {
  console.error('[jj-sync] Failed to initialize repo watchers:', err);
});

const ptyWsHandler = createPtyWebSocketHandler();

const _server = Bun.serve<{ ptyId: string; userId: number }>({
  async fetch(req, server) {
    // Check for PTY WebSocket upgrade
    const ptyWs = isPtyWebSocketRequest(req);
    if (ptyWs) {
      // Validate authentication before upgrading WebSocket
      const userId = await validateWebSocketAuth(req);
      if (!userId) {
        return new Response('Authentication required', { status: 401 });
      }

      const upgraded = server.upgrade(req, {
        data: { ptyId: ptyWs.ptyId, userId },
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

// Start SSH server for git operations
const sshPort = Number(process.env.SSH_PORT) || 2222;
startSSHServer(sshPort);

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down server...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Shutting down server...');
  process.exit(0);
});