/**
 * Snapshot operations for file state tracking.
 *
 * Provides functions for tracking file changes using the jj-based snapshot system.
 * This wraps the snapshot/src/snapshot.ts module for session-based management.
 */

import {
  sessionSnapshots,
  appendSnapshotHistory as appendSnapshotHistoryToDB,
  setSnapshotHistory,
} from './state';
import { NotFoundError, SnapshotUnavailableError } from './exceptions';

// Types (defined locally to avoid native dependency)
export interface FileDiff {
  path: string;
  changeType: 'added' | 'modified' | 'deleted';
  beforeContent?: string;
  afterContent?: string;
  addedLines: number;
  deletedLines: number;
}

export interface SnapshotInfo {
  changeId: string;
  commitId: string;
  description: string;
  timestamp: number;
  isEmpty: boolean;
}

// Module state
type SnapshotClass = typeof import('../snapshot/src/snapshot').Snapshot;
type SnapshotSessionManagerClass = typeof import('../snapshot/src/snapshot').SnapshotSessionManager;
type SnapshotSessionManagerInstance = InstanceType<SnapshotSessionManagerClass>;

let _Snapshot: SnapshotClass | null = null;
let SnapshotSessionManager: SnapshotSessionManagerClass | null = null;
let initialized = false;

// Global session manager instance
let sessionManager: SnapshotSessionManagerInstance | null = null;

/**
 * Initialize the native snapshot module lazily.
 * Throws if the native module is not available.
 */
async function initializeNative(): Promise<void> {
  if (initialized) return;

  try {
    const native = await import('../snapshot/src/snapshot');
    _Snapshot = native.Snapshot;
    SnapshotSessionManager = native.SnapshotSessionManager;
    sessionManager = new SnapshotSessionManager();
    console.log('[snapshots] Native jj module loaded successfully');

    initialized = true;
  } catch (error) {
    console.warn('[snapshots] Native jj module not available, falling back to no-op implementation');
    console.warn('[snapshots] Error:', error);
    // Initialize with no-op implementations
    initialized = true;
  }
}

/**
 * Initialize snapshot tracking for a session.
 *
 * @param sessionId - The session to initialize snapshots for
 * @param directory - The directory to track
 * @returns The initial snapshot change ID
 */
export async function initSnapshot(
  sessionId: string,
  directory: string
): Promise<string> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('initSnapshot');
  }

  try {
    const changeId = await sessionManager.initSession(sessionId, directory);
    await setSnapshotHistory(sessionId, [changeId]);
    return changeId;
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('initSnapshot', reason);
  }
}

/**
 * Capture the current file state for a session.
 *
 * @param sessionId - The session to track
 * @param description - Optional description for the snapshot
 * @returns The snapshot change ID
 * @throws NotFoundError if the session is not found
 */
export async function trackSnapshot(
  sessionId: string,
  description?: string
): Promise<string> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('trackSnapshot');
  }

  try {
    const changeId = await sessionManager.trackSnapshot(sessionId, description);
    if (!changeId) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await appendSnapshotHistoryToDB(sessionId, changeId);
    return changeId;
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('trackSnapshot', reason);
  }
}

/**
 * Compute file diffs between two snapshots.
 *
 * @param sessionId - The session to compute diffs for
 * @param fromChangeId - The starting snapshot change ID
 * @param toChangeId - The ending snapshot change ID (optional, defaults to working copy)
 * @returns List of file diffs
 */
export async function computeDiff(
  sessionId: string,
  fromChangeId: string,
  toChangeId?: string
): Promise<FileDiff[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('computeDiff');
  }

  try {
    return await sessionManager.computeDiff(sessionId, fromChangeId, toChangeId);
  } catch (error) {
    if (error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('computeDiff', reason);
  }
}

/**
 * Get list of files changed between two snapshots.
 *
 * @param sessionId - The session to check
 * @param fromChangeId - The starting snapshot change ID
 * @param toChangeId - The ending snapshot change ID (optional)
 * @returns List of changed file paths
 */
export async function getChangedFiles(
  sessionId: string,
  fromChangeId: string,
  toChangeId?: string
): Promise<string[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getChangedFiles');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.patch(fromChangeId, toChangeId);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getChangedFiles', reason);
  }
}

/**
 * Restore files to a previous snapshot state.
 *
 * @param sessionId - The session to restore
 * @param changeId - The snapshot change ID to restore to
 * @throws NotFoundError if the session is not found
 */
export async function restoreSnapshot(
  sessionId: string,
  changeId: string
): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('restoreSnapshot');
  }

  try {
    await sessionManager.restoreSnapshot(sessionId, changeId);
  } catch (error) {
    if (error instanceof Error && error.message.includes('not found')) {
      throw new NotFoundError('session snapshot', sessionId);
    }
    if (error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('restoreSnapshot', reason);
  }
}

/**
 * Get the snapshot history for a session.
 *
 * @param sessionId - The session to get history for
 * @returns Array of change IDs in order
 */
export async function getSnapshotHistory(sessionId: string): Promise<string[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSnapshotHistory');
  }

  try {
    return sessionManager.getHistory(sessionId);
  } catch (error) {
    if (error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSnapshotHistory', reason);
  }
}

/**
 * Append a snapshot change ID to the session's history.
 *
 * @param sessionId - The session to update
 * @param changeId - The change ID to append
 */
export async function appendSnapshotHistory(sessionId: string, changeId: string): Promise<void> {
  await appendSnapshotHistoryToDB(sessionId, changeId);
}

/**
 * Clean up snapshot resources for a session.
 *
 * @param sessionId - The session to clean up
 */
export async function cleanupSnapshots(sessionId: string): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    sessionSnapshots.delete(sessionId);
    return;
  }

  try {
    sessionManager.cleanupSession(sessionId);
    sessionSnapshots.delete(sessionId);
  } catch (error) {
    console.warn('[snapshots] Failed to cleanup snapshots:', error);
    sessionSnapshots.delete(sessionId);
  }
  // Database cleanup is handled by foreign key cascades when session is deleted
}

/**
 * Get the snapshot instance for a session.
 *
 * @param sessionId - The session to get snapshot for
 * @returns The Snapshot instance
 * @throws NotFoundError if the session is not found
 */
export async function getSessionSnapshot(sessionId: string): Promise<any> {
  await initializeNative();

  if (!sessionManager) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  const snapshot = sessionManager.getSession(sessionId);
  if (!snapshot) {
    throw new NotFoundError('session snapshot', sessionId);
  }

  return snapshot;
}

/**
 * Revert specific files from a snapshot.
 *
 * @param sessionId - The session to revert files in
 * @param changeId - The snapshot change ID to revert from
 * @param files - Array of file paths to revert
 */
export async function revertFiles(
  sessionId: string,
  changeId: string,
  files: string[]
): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('revertFiles');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await snapshot.revert(changeId, files);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('revertFiles', reason);
  }
}

/**
 * Get file contents at a specific snapshot.
 *
 * @param sessionId - The session to get file from
 * @param changeId - The snapshot change ID
 * @param filePath - The file path
 * @returns The file contents
 * @throws NotFoundError if the session is not found
 */
export async function getFileAtSnapshot(
  sessionId: string,
  changeId: string,
  filePath: string
): Promise<string | null> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getFileAtSnapshot');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return snapshot.getFileAt(changeId, filePath);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getFileAtSnapshot', reason);
  }
}

/**
 * Undo the last jj operation for a session.
 *
 * @param sessionId - The session to undo in
 */
export async function undoLastOperation(sessionId: string): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('undoLastOperation');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await snapshot.undo();
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('undoLastOperation', reason);
  }
}

// =============================================================================
// JJ-Native Session Operations
// =============================================================================

export interface SessionOperation {
  id: string;
  description: string;
  timestamp: number;
}

export interface SessionChange {
  changeId: string;
  commitId: string;
  description: string;
  timestamp: number;
  isEmpty: boolean;
}

export interface SessionConflict {
  filePath: string;
  changeId: string;
}

/**
 * Get the operation log for a session.
 *
 * @param sessionId - The session to get operations for
 * @param limit - Maximum number of operations to return
 * @returns Array of operations
 */
export async function getSessionOperations(
  sessionId: string,
  limit: number = 20
): Promise<SessionOperation[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionOperations');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.getOperationLog(limit);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionOperations', reason);
  }
}

/**
 * Restore a session to a specific operation.
 *
 * @param sessionId - The session to restore
 * @param operationId - The operation ID to restore to
 */
export async function restoreSessionOperation(
  sessionId: string,
  operationId: string
): Promise<void> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('restoreSessionOperation');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    await snapshot.restoreOperation(operationId);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('restoreSessionOperation', reason);
  }
}

/**
 * Get the list of changes (snapshots) for a session.
 *
 * @param sessionId - The session to get changes for
 * @param limit - Maximum number of changes to return
 * @returns Array of changes
 */
export async function getSessionChanges(
  sessionId: string,
  limit: number = 50
): Promise<SessionChange[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionChanges');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.listSnapshots(limit);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionChanges', reason);
  }
}

/**
 * Get the current working copy change ID for a session.
 *
 * @param sessionId - The session to get current change for
 * @returns The current change ID
 */
export async function getSessionCurrentChange(sessionId: string): Promise<string | null> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionCurrentChange');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.current();
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionCurrentChange', reason);
  }
}

/**
 * Get conflicts for a session's current working copy.
 *
 * @param sessionId - The session to check for conflicts
 * @param changeId - Optional specific change to check (defaults to @)
 * @returns Array of conflicted files
 */
export async function getSessionConflicts(
  sessionId: string,
  changeId?: string
): Promise<SessionConflict[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionConflicts');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    // Get current change ID if not specified
    const targetChangeId = changeId || await snapshot.current();

    // Check for conflict markers in the working copy
    // jj stores conflicts as first-class citizens, we need to run jj resolve --list
    // This is done through the snapshot's execJj method
    const _files = await snapshot.listFilesAt(targetChangeId);

    // For now, return empty - conflicts are surfaced via hasConflicts in SnapshotInfo
    // The model handles conflicts directly in jj
    return [];
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionConflicts', reason);
  }
}

/**
 * Check if a session has conflicts.
 *
 * @param sessionId - The session to check
 * @returns True if there are conflicts
 */
export async function sessionHasConflicts(sessionId: string): Promise<boolean> {
  await initializeNative();

  if (!sessionManager) {
    return false;
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      return false;
    }

    const info = await snapshot.getSnapshot(await snapshot.current());
    return !info.isEmpty && info.description.toLowerCase().includes('conflict');
  } catch (error) {
    return false;
  }
}

/**
 * Get file content at a specific change in a session.
 *
 * @param sessionId - The session
 * @param changeId - The change ID
 * @param filePath - The file path
 * @returns File content or null
 */
export async function getSessionFileAtChange(
  sessionId: string,
  changeId: string,
  filePath: string
): Promise<string | null> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionFileAtChange');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.getFileAt(changeId, filePath);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionFileAtChange', reason);
  }
}

/**
 * List files at a specific change in a session.
 *
 * @param sessionId - The session
 * @param changeId - The change ID
 * @returns Array of file paths
 */
export async function getSessionFilesAtChange(
  sessionId: string,
  changeId: string
): Promise<string[]> {
  await initializeNative();

  if (!sessionManager) {
    throw new SnapshotUnavailableError('getSessionFilesAtChange');
  }

  try {
    const snapshot = sessionManager.getSession(sessionId);
    if (!snapshot) {
      throw new NotFoundError('session snapshot', sessionId);
    }

    return await snapshot.listFilesAt(changeId);
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof SnapshotUnavailableError) {
      throw error;
    }
    const reason = error instanceof Error ? error.message : String(error);
    throw new SnapshotUnavailableError('getSessionFilesAtChange', reason);
  }
}