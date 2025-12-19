/**
 * Session routes - CRUD operations for sessions.
 */

import { Hono } from 'hono';
import {
  createSession,
  getSession,
  listSessions,
  updateSession,
  deleteSession,
  abortSession,
  getSessionDiff,
  forkSession,
  revertSession,
  unrevertSession,
  undoTurns,
} from '../../core/sessions';
import { NotFoundError, InvalidOperationError } from '../../core/exceptions';
import { getServerEventBus } from '../event-bus';

const app = new Hono();

// List all sessions
app.get('/', async (c) => {
  const sessions = await listSessions();
  return c.json({ sessions });
});

// Create a new session
app.post('/', async (c) => {
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  const session = await createSession(
    {
      directory: body.directory ?? process.cwd(),
      title: body.title,
      parentID: body.parentID,
      bypassMode: body.bypassMode,
      model: body.model,
      reasoningEffort: body.reasoningEffort,
      plugins: body.plugins,
    },
    eventBus
  );

  return c.json({ session }, 201);
});

// Get a session by ID
app.get('/:sessionId', async (c) => {
  const sessionId = c.req.param('sessionId');

  try {
    const session = getSession(sessionId);
    return c.json({ session });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Update a session
app.patch('/:sessionId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  try {
    const session = await updateSession(
      sessionId,
      {
        title: body.title,
        archived: body.archived,
        model: body.model,
        reasoningEffort: body.reasoningEffort,
      },
      eventBus
    );
    return c.json({ session });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Delete a session
app.delete('/:sessionId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const eventBus = getServerEventBus();

  try {
    await deleteSession(sessionId, eventBus);
    return c.json({ success: true });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Abort a session's active task
app.post('/:sessionId/abort', async (c) => {
  const sessionId = c.req.param('sessionId');

  try {
    const aborted = abortSession(sessionId);
    return c.json({ success: true, aborted });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get session diff
app.get('/:sessionId/diff', async (c) => {
  const sessionId = c.req.param('sessionId');
  const messageId = c.req.query('messageId');

  try {
    const diffs = await getSessionDiff(sessionId, messageId);
    return c.json({ diffs });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Fork a session
app.post('/:sessionId/fork', async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  try {
    const session = await forkSession(
      sessionId,
      eventBus,
      body.messageId,
      body.title
    );
    return c.json({ session }, 201);
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Revert a session
app.post('/:sessionId/revert', async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  try {
    const session = await revertSession(
      sessionId,
      body.messageId,
      eventBus,
      body.partId
    );
    return c.json({ session });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof InvalidOperationError) {
      return c.json({ error: error.message }, 400);
    }
    throw error;
  }
});

// Unrevert a session
app.post('/:sessionId/unrevert', async (c) => {
  const sessionId = c.req.param('sessionId');
  const eventBus = getServerEventBus();

  try {
    const session = await unrevertSession(sessionId, eventBus);
    return c.json({ session });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Undo turns
app.post('/:sessionId/undo', async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  try {
    const [turnsUndone, messagesRemoved, filesReverted, snapshotRestored] =
      await undoTurns(sessionId, eventBus, body.count ?? 1);

    return c.json({
      turnsUndone,
      messagesRemoved,
      filesReverted,
      snapshotRestored,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    if (error instanceof InvalidOperationError) {
      return c.json({ error: error.message }, 400);
    }
    throw error;
  }
});

export default app;
