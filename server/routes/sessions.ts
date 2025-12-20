/**
 * Session routes - CRUD operations for sessions.
 */

import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
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
import {
  getSessionChanges,
  getSessionConflicts,
  getSessionOperations,
  getSessionCurrentChange,
  restoreSessionOperation,
  undoLastOperation,
  computeDiff,
  getSessionFileAtChange,
  getSessionFilesAtChange,
} from '../../core/snapshots';
import { NotFoundError, InvalidOperationError } from '../../core/exceptions';
import { getServerEventBus } from '../event-bus';
import {
  createSessionSchema,
  updateSessionSchema,
  forkSessionSchema,
  revertSessionSchema,
  undoTurnsSchema,
} from '../lib/validation';

const app = new Hono();

// Apply authentication to all session routes
app.use('*', requireAuth, requireActiveAccount);

// List all sessions
app.get('/', async (c) => {
  const sessions = await listSessions();
  return c.json({ sessions });
});

// Create a new session
app.post('/', zValidator('json', createSessionSchema), async (c) => {
  const body = c.req.valid('json');
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
app.patch('/:sessionId', zValidator('json', updateSessionSchema), async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = c.req.valid('json');
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
app.post('/:sessionId/fork', zValidator('json', forkSessionSchema), async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = c.req.valid('json');
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
app.post('/:sessionId/revert', zValidator('json', revertSessionSchema), async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = c.req.valid('json');
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
app.post('/:sessionId/undo', zValidator('json', undoTurnsSchema), async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = c.req.valid('json');
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

// =============================================================================
// JJ-Native Session Endpoints
// =============================================================================

// Get changes (snapshots) for a session
app.get('/:sessionId/changes', async (c) => {
  const sessionId = c.req.param('sessionId');
  const limit = parseInt(c.req.query('limit') || '50', 10);

  try {
    getSession(sessionId); // Verify session exists
    const changes = await getSessionChanges(sessionId, limit);
    const currentChangeId = await getSessionCurrentChange(sessionId);

    return c.json({
      changes,
      currentChangeId,
      total: changes.length,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get a specific change's details
app.get('/:sessionId/changes/:changeId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const changeId = c.req.param('changeId');

  try {
    getSession(sessionId); // Verify session exists
    const changes = await getSessionChanges(sessionId, 100);
    const change = changes.find(ch => ch.changeId === changeId || ch.changeId.startsWith(changeId));

    if (!change) {
      return c.json({ error: 'Change not found' }, 404);
    }

    return c.json({ change });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get diff between two changes in a session
app.get('/:sessionId/changes/:fromChangeId/compare/:toChangeId', async (c) => {
  const sessionId = c.req.param('sessionId');
  const fromChangeId = c.req.param('fromChangeId');
  const toChangeId = c.req.param('toChangeId');

  try {
    getSession(sessionId); // Verify session exists
    const diffs = await computeDiff(sessionId, fromChangeId, toChangeId);

    return c.json({ diffs });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get files at a specific change
app.get('/:sessionId/changes/:changeId/files', async (c) => {
  const sessionId = c.req.param('sessionId');
  const changeId = c.req.param('changeId');

  try {
    getSession(sessionId); // Verify session exists
    const files = await getSessionFilesAtChange(sessionId, changeId);

    return c.json({ files });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get file content at a specific change
app.get('/:sessionId/changes/:changeId/file/*', async (c) => {
  const sessionId = c.req.param('sessionId');
  const changeId = c.req.param('changeId');
  const filePath = c.req.path.split('/file/')[1];

  if (!filePath) {
    return c.json({ error: 'File path required' }, 400);
  }

  try {
    getSession(sessionId); // Verify session exists
    const content = await getSessionFileAtChange(sessionId, changeId, filePath);

    if (content === null) {
      return c.json({ error: 'File not found at this change' }, 404);
    }

    return c.json({ content, filePath, changeId });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get conflicts for a session
app.get('/:sessionId/conflicts', async (c) => {
  const sessionId = c.req.param('sessionId');
  const changeId = c.req.query('changeId');

  try {
    getSession(sessionId); // Verify session exists
    const conflicts = await getSessionConflicts(sessionId, changeId);
    const currentChangeId = await getSessionCurrentChange(sessionId);

    return c.json({
      conflicts,
      hasConflicts: conflicts.length > 0,
      currentChangeId,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Get operation log for a session
app.get('/:sessionId/operations', async (c) => {
  const sessionId = c.req.param('sessionId');
  const limit = parseInt(c.req.query('limit') || '20', 10);

  try {
    getSession(sessionId); // Verify session exists
    const operations = await getSessionOperations(sessionId, limit);

    return c.json({
      operations,
      total: operations.length,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Undo last jj operation
app.post('/:sessionId/operations/undo', async (c) => {
  const sessionId = c.req.param('sessionId');

  try {
    getSession(sessionId); // Verify session exists
    await undoLastOperation(sessionId);

    return c.json({ success: true });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

// Restore to a specific operation
app.post('/:sessionId/operations/:operationId/restore', async (c) => {
  const sessionId = c.req.param('sessionId');
  const operationId = c.req.param('operationId');

  try {
    getSession(sessionId); // Verify session exists
    await restoreSessionOperation(sessionId, operationId);

    return c.json({ success: true, restoredTo: operationId });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

export default app;