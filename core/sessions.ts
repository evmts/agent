/**
 * Session operations.
 *
 * Provides functions for managing sessions including CRUD operations,
 * forking, reverting, and diff computation.
 */

import type {
  Session,
  SessionSummary,
  CreateSessionOptions,
  UpdateSessionOptions,
} from './models';
import type { EventBus } from './events';
import type { FileDiff } from './snapshots';
import {
  initSnapshot,
  computeDiff,
  getChangedFiles,
  restoreSnapshot,
  getSnapshotHistory,
} from './snapshots';
import {
  getSession as getSessionFromDB,
  getAllSessions,
  saveSession,
  getSessionMessages,
  setSessionMessages,
  getSnapshotHistory as getSnapshotHistoryFromDB,
  setSnapshotHistory,
  activeTasks,
  clearSessionState,
} from './state';
import { NotFoundError, InvalidOperationError } from './exceptions';

// =============================================================================
// Constants
// =============================================================================

const DEFAULT_PROJECT_ID = 'default';
const DEFAULT_VERSION = '1.0.0';
const DEFAULT_SESSION_TITLE = 'New Session';
const DEFAULT_MODEL = 'claude-sonnet-4-20250514';

// =============================================================================
// Utilities
// =============================================================================

function generateId(prefix: string): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = prefix;
  for (let i = 0; i < 12; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

// =============================================================================
// Session CRUD
// =============================================================================

/**
 * Create a new session.
 */
export async function createSession(
  options: CreateSessionOptions,
  eventBus: EventBus
): Promise<Session> {
  const now = Date.now();
  const session: Session = {
    id: generateId('ses_'),
    projectID: DEFAULT_PROJECT_ID,
    directory: options.directory,
    title: options.title ?? DEFAULT_SESSION_TITLE,
    version: DEFAULT_VERSION,
    time: { created: now, updated: now },
    parentID: options.parentID,
    tokenCount: 0,
    bypassMode: options.bypassMode ?? false,
    model: options.model ?? DEFAULT_MODEL,
    reasoningEffort: options.reasoningEffort ?? 'medium',
    plugins: options.plugins ?? [],
  };

  await saveSession(session);

  // Initialize snapshot tracking
  await initSnapshot(session.id, options.directory);

  if (session.bypassMode) {
    console.warn(
      `Session created in BYPASS MODE: ${session.id} - All permission checks disabled`
    );
  }

  await eventBus.publish({
    type: 'session.created',
    properties: { info: session },
  });

  return session;
}

/**
 * Get a session by ID.
 */
export async function getSession(sessionId: string): Promise<Session> {
  const session = await getSessionFromDB(sessionId);
  if (!session) {
    throw new NotFoundError('Session', sessionId);
  }
  return session;
}

/**
 * List all sessions sorted by most recently updated.
 */
export async function listSessions(): Promise<Session[]> {
  return getAllSessions();
}

/**
 * Update a session.
 */
export async function updateSession(
  sessionId: string,
  options: UpdateSessionOptions,
  eventBus: EventBus
): Promise<Session> {
  const session = await getSession(sessionId);

  if (options.title !== undefined) {
    session.title = options.title;
  }
  if (options.archived !== undefined) {
    session.time.archived = options.archived ? Date.now() : undefined;
  }
  if (options.model !== undefined) {
    session.model = options.model;
  }
  if (options.reasoningEffort !== undefined) {
    session.reasoningEffort = options.reasoningEffort;
  }
  session.time.updated = Date.now();

  await saveSession(session);

  await eventBus.publish({
    type: 'session.updated',
    properties: { info: session },
  });

  return session;
}

/**
 * Delete a session.
 */
export async function deleteSession(
  sessionId: string,
  eventBus: EventBus
): Promise<boolean> {
  const session = await getSessionFromDB(sessionId);
  if (!session) {
    throw new NotFoundError('Session', sessionId);
  }

  // Cancel any active task
  const task = activeTasks.get(sessionId);
  if (task) {
    task.abort();
    activeTasks.delete(sessionId);
  }

  // Clean up all session state
  await clearSessionState(sessionId);

  await eventBus.publish({
    type: 'session.deleted',
    properties: { info: session },
  });

  return true;
}

// =============================================================================
// Session Actions
// =============================================================================

/**
 * Abort an active session task.
 */
export async function abortSession(sessionId: string): Promise<boolean> {
  const session = await getSessionFromDB(sessionId);
  if (!session) {
    throw new NotFoundError('Session', sessionId);
  }

  const task = activeTasks.get(sessionId);
  if (task) {
    task.abort();
    activeTasks.delete(sessionId);
    return true;
  }

  return false;
}

/**
 * Get file diffs for a session.
 */
export async function getSessionDiff(
  sessionId: string,
  messageId?: string
): Promise<FileDiff[]> {
  const session = await getSessionFromDB(sessionId);
  if (!session) {
    throw new NotFoundError('Session', sessionId);
  }

  const history = await getSnapshotHistoryFromDB(sessionId);

  if (history.length < 2) {
    return [];
  }

  // Determine target index based on messageId
  if (messageId) {
    const messages = await getSessionMessages(sessionId);
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i];
      const fromHash = history[0];
      const toHash = history[i];
      if (msg?.info.id === messageId && i < history.length && fromHash && toHash) {
        return computeDiff(sessionId, fromHash, toHash);
      }
    }
  }

  // Default: diff from session start to current
  const fromHash = history[0];
  const toHash = history[history.length - 1];
  if (!fromHash || !toHash) {
    return [];
  }
  return computeDiff(sessionId, fromHash, toHash);
}

/**
 * Fork a session at a specific message.
 */
export async function forkSession(
  sessionId: string,
  eventBus: EventBus,
  messageId?: string,
  title?: string
): Promise<Session> {
  const parent = await getSession(sessionId);
  const now = Date.now();

  const newSession: Session = {
    id: generateId('ses_'),
    projectID: parent.projectID,
    directory: parent.directory,
    title: title ?? `${parent.title} (fork)`,
    version: parent.version,
    time: { created: now, updated: now },
    parentID: sessionId,
    forkPoint: messageId,
    tokenCount: 0,
    bypassMode: parent.bypassMode,
    plugins: [...parent.plugins],
  };

  await saveSession(newSession);

  // Copy messages up to the fork point
  const parentMessages = await getSessionMessages(sessionId);
  const messagesToCopy = [];
  for (const msg of parentMessages) {
    messagesToCopy.push(msg);
    if (messageId && msg.info.id === messageId) {
      break;
    }
  }
  await setSessionMessages(newSession.id, [...messagesToCopy]);

  // Initialize snapshot at fork point
  await initSnapshot(newSession.id, parent.directory);

  await eventBus.publish({
    type: 'session.created',
    properties: { info: newSession },
  });

  return newSession;
}

/**
 * Revert session to a specific message, restoring files to that state.
 */
export async function revertSession(
  sessionId: string,
  messageId: string,
  eventBus: EventBus,
  partId?: string
): Promise<Session> {
  const session = await getSession(sessionId);
  const history = await getSnapshotHistoryFromDB(sessionId);
  const messages = await getSessionMessages(sessionId);

  // Find the snapshot hash corresponding to the target message
  let targetIndex: number | null = null;
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (msg?.info.id === messageId) {
      targetIndex = i;
      break;
    }
  }

  let targetHash: string | null = null;
  if (targetIndex !== null && targetIndex < history.length) {
    targetHash = history[targetIndex] ?? null;
  }

  // Restore files if we have a valid snapshot
  if (targetHash) {
    try {
      await restoreSnapshot(sessionId, targetHash);
    } catch (error) {
      throw new InvalidOperationError(
        `Failed to restore snapshot: ${error}`
      );
    }
  }

  session.revert = {
    messageID: messageId,
    partID: partId,
    snapshot: targetHash ?? undefined,
  };
  session.time.updated = Date.now();
  await saveSession(session);

  await eventBus.publish({
    type: 'session.updated',
    properties: { info: session },
  });

  return session;
}

/**
 * Undo revert on a session.
 */
export async function unrevertSession(
  sessionId: string,
  eventBus: EventBus
): Promise<Session> {
  const session = await getSession(sessionId);
  session.revert = undefined;
  session.time.updated = Date.now();
  await saveSession(session);

  await eventBus.publish({
    type: 'session.updated',
    properties: { info: session },
  });

  return session;
}

/**
 * Update a session's summary.
 */
export async function updateSessionSummary(
  sessionId: string,
  summary: SessionSummary
): Promise<void> {
  const session = await getSessionFromDB(sessionId);
  if (session) {
    session.summary = summary;
    session.time.updated = Date.now();
    await saveSession(session);
  }
}

/**
 * Undo the last N turns in a session.
 *
 * A turn consists of a user message followed by all assistant messages
 * until the next user message.
 *
 * @returns Tuple of (turnsUndone, messagesRemoved, filesReverted, snapshotRestored)
 */
export async function undoTurns(
  sessionId: string,
  eventBus: EventBus,
  count: number = 1
): Promise<[number, number, string[], string | null]> {
  const session = await getSession(sessionId);
  const messages = await getSessionMessages(sessionId);
  const history = await getSnapshotHistoryFromDB(sessionId);

  if (messages.length === 0) {
    return [0, 0, [], null];
  }

  // Find turn boundaries (user messages are turn starts)
  const turnStarts: number[] = [];
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (msg?.info.role === 'user') {
      turnStarts.push(i);
    }
  }

  // Can't undo if we only have one turn or less
  if (turnStarts.length < 2) {
    return [0, 0, [], null];
  }

  // Calculate actual number of turns we can undo
  const undoCount = Math.min(count, turnStarts.length - 1);

  // Find the message index to revert to
  const undoPoint = turnStarts[turnStarts.length - undoCount];
  if (undoPoint === undefined) {
    return [0, 0, [], null];
  }

  // Get snapshot to restore
  let snapshotHash: string | null = null;
  let filesReverted: string[] = [];

  const turnIndex = turnStarts.length - undoCount - 1;
  const snapshotIndex = turnIndex + 1;

  if (snapshotIndex < history.length) {
    snapshotHash = history[snapshotIndex] ?? null;

    if (snapshotHash) {
      try {
        await restoreSnapshot(sessionId, snapshotHash);

        // Get list of files that were changed
        const lastHash = history[history.length - 1];
        if (undoPoint < history.length - 1 && lastHash) {
          filesReverted = await getChangedFiles(
            sessionId,
            snapshotHash,
            lastHash
          );
        }
      } catch (error) {
        throw new InvalidOperationError(
          `Failed to restore snapshot: ${error}`
        );
      }
    }
  }

  // Calculate how many messages we're removing
  const messagesRemoved = messages.length - undoPoint;

  // Truncate messages at undo point
  await setSessionMessages(sessionId, messages.slice(0, undoPoint));

  // Truncate snapshot history to match
  await setSnapshotHistory(sessionId, history.slice(0, snapshotIndex + 1));

  // Update session timestamp
  session.time.updated = Date.now();
  await saveSession(session);

  await eventBus.publish({
    type: 'session.updated',
    properties: { info: session },
  });

  return [undoCount, messagesRemoved, filesReverted, snapshotHash];
}