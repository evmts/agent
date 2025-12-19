/**
 * Core module - encapsulates all core logic.
 */

// Models
export * from './models';

// State
export {
  // Runtime-only state (in-memory)
  activeTasks,
  sessionSnapshots,
  // Database-backed operations
  getSession as getSessionState,
  getAllSessions,
  saveSession,
  deleteSessionFromDB,
  getSessionMessages,
  appendSessionMessage,
  setSessionMessages,
  getSnapshotHistory as getSnapshotHistoryFromDB,
  setSnapshotHistory,
  appendSnapshotHistory as appendSnapshotHistoryToDB,
  getSubtasks,
  appendSubtask,
  clearSubtasks,
  getFileTracker,
  updateFileTracker,
  clearFileTrackers,
  clearSessionState,
  type MessageWithParts,
  type FileTimeTracker,
} from './state';

// Events
export {
  EventTypes,
  SSEEventBus,
  NullEventBus,
  getEventBus,
  setEventBus,
  type Event,
  type EventBus,
  type EventType,
} from './events';

// Exceptions
export {
  CoreError,
  NotFoundError,
  InvalidOperationError,
  PermissionDeniedError,
  ValidationError,
  TimeoutError,
} from './exceptions';

// Snapshots
export {
  initSnapshot,
  trackSnapshot,
  computeDiff,
  getChangedFiles,
  restoreSnapshot,
  getSnapshotHistory,
  appendSnapshotHistory,
  cleanupSnapshots,
  getSessionSnapshot,
  revertFiles,
  getFileAtSnapshot,
  undoLastOperation,
  type FileDiff,
  type SnapshotInfo,
} from './snapshots';

// Sessions
export {
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
  updateSessionSummary,
  undoTurns,
} from './sessions';
