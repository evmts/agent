/**
 * ElectricSQL client-side integration.
 *
 * Provides React hooks and utilities for subscribing to real-time
 * agent state updates using ElectricSQL shapes.
 *
 * NOTE: This file uses @electric-sql/client and @electric-sql/react which are
 * client-side only packages. Import this only in client-side components.
 */

// API URL from environment or default
const API_URL = import.meta.env.PUBLIC_CLIENT_API_URL || 'http://localhost:4000';

// Base row type
type Row = Record<string, unknown>;

// Type-only imports to avoid importing React at build time
type ShapeOptions<T extends Row = Row> = {
  url: string;
  params: Record<string, string>;
  parser?: Record<string, (value: string) => unknown>;
  signal?: AbortSignal;
};

/**
 * Custom hook that automatically aborts shape subscriptions after a timeout
 * when all components using the shape unmount. This prevents unnecessary
 * long-lived connections.
 *
 * This is a placeholder type - actual implementation requires @electric-sql/react
 */
export function useShapeWithAbort<T extends Row = Row>(
  _rawShapeConfig: ShapeOptions<T>,
  _timeout: number
): { data: T[]; isLoading: boolean } {
  // This function should only be called in client-side components
  // The actual implementation would use @electric-sql/react's useShape
  const errorMessage =
    'useShapeWithAbort must be imported from a client component with @electric-sql/react available.\n\n' +
    'This error occurs because ElectricSQL is not configured or the function is being called outside of a client component.\n' +
    'To fix this:\n' +
    '1. Install @electric-sql/react if not already installed: bun add @electric-sql/react\n' +
    '2. Ensure this function is only used in client-side components (not in .astro files)\n' +
    '3. Verify ElectricSQL sync service is running if you need real-time features\n';
  throw new Error(errorMessage);
}

// =============================================================================
// Session Shapes
// =============================================================================

export interface SessionRow {
  id: string;
  project_id: string;
  directory: string;
  title: string;
  version: string;
  time_created: number;
  time_updated: number;
  time_archived?: number | null;
  parent_id?: string | null;
  fork_point?: string | null;
  summary?: unknown | null;
  revert?: unknown | null;
  compaction?: unknown | null;
  token_count: number;
  bypass_mode: boolean;
  model?: string | null;
  reasoning_effort?: string | null;
  ghost_commit?: unknown | null;
  plugins: unknown[];
}

export function sessionsShapeConfig(where?: string): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'sessions',
      ...(where ? { where } : {}),
    },
    signal: new AbortController().signal, // Dummy signal for consistent hashing
  };
}

export function useSessionsShape(where?: string): { data: SessionRow[]; isLoading: boolean } {
  throw new Error(
    'useSessionsShape must be imported from a client component.\n' +
    'ElectricSQL is not configured. See useShapeWithAbort error for setup instructions.'
  );
}

export async function preloadSessions(_where?: string): Promise<void> {
  throw new Error(
    'preloadSessions must be imported from a client component.\n' +
    'ElectricSQL is not configured. See useShapeWithAbort error for setup instructions.'
  );
}

export function useSession(_sessionId: string): SessionRow | undefined {
  throw new Error(
    'useSession must be imported from a client component.\n' +
    'ElectricSQL is not configured. See useShapeWithAbort error for setup instructions.'
  );
}

// =============================================================================
// Message Shapes
// =============================================================================

export interface MessageRow {
  id: string;
  session_id: string;
  role: 'user' | 'assistant';
  time_created: number;
  time_completed?: number | null;
  // User message fields
  agent?: string | null;
  model_provider_id?: string | null;
  model_model_id?: string | null;
  system_prompt?: string | null;
  tools?: unknown | null;
  // Assistant message fields
  parent_id?: string | null;
  mode?: string | null;
  path_cwd?: string | null;
  path_root?: string | null;
  cost?: number | null;
  tokens_input?: number | null;
  tokens_output?: number | null;
  tokens_reasoning?: number | null;
  tokens_cache_read?: number | null;
  tokens_cache_write?: number | null;
  finish?: string | null;
  is_summary?: boolean | null;
  error?: unknown | null;
  created_at: Date;
}

export function messagesShapeConfig(sessionId: string): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'messages',
      where: `session_id = '${sessionId}'`,
    },
    parser: {
      timestamptz: (value: string) => new Date(value),
    },
    signal: new AbortController().signal,
  };
}

export function useMessagesShape(_sessionId: string): { data: MessageRow[]; isLoading: boolean } {
  throw new Error('useMessagesShape must be imported from a client component');
}

export async function preloadMessages(_sessionId: string): Promise<void> {
  throw new Error('preloadMessages must be imported from a client component');
}

// =============================================================================
// Part Shapes (Primary real-time streaming shape)
// =============================================================================

export interface PartRow {
  id: string;
  session_id: string;
  message_id: string;
  type: 'text' | 'reasoning' | 'tool' | 'file';
  // Text/Reasoning fields
  text?: string | null;
  // Tool fields
  tool_name?: string | null;
  tool_state?: unknown | null;
  // File fields
  mime?: string | null;
  url?: string | null;
  filename?: string | null;
  // Time tracking
  time_start?: number | null;
  time_end?: number | null;
  sort_order: number;
}

export function partsShapeConfig(sessionId: string): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'parts',
      where: `session_id = '${sessionId}'`,
    },
    signal: new AbortController().signal,
  };
}

/**
 * Subscribe to parts for a session. This is the primary hook for
 * real-time streaming updates during agent execution.
 */
export function usePartsShape(_sessionId: string): { data: PartRow[]; isLoading: boolean } {
  throw new Error('usePartsShape must be imported from a client component');
}

export async function preloadParts(_sessionId: string): Promise<void> {
  throw new Error('preloadParts must be imported from a client component');
}

/**
 * Get all parts for a specific message from the parts shape.
 */
export function useMessageParts(_sessionId: string, _messageId: string): PartRow[] {
  throw new Error('useMessageParts must be imported from a client component');
}

// =============================================================================
// Snapshot History Shapes
// =============================================================================

export interface SnapshotHistoryRow {
  id: number;
  session_id: string;
  change_id: string;
  sort_order: number;
  created_at: Date;
}

export function snapshotHistoryShapeConfig(sessionId: string): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'snapshot_history',
      where: `session_id = '${sessionId}'`,
    },
    parser: {
      timestamptz: (value: string) => new Date(value),
    },
    signal: new AbortController().signal,
  };
}

export function useSnapshotHistoryShape(_sessionId: string): { data: SnapshotHistoryRow[]; isLoading: boolean } {
  throw new Error('useSnapshotHistoryShape must be imported from a client component');
}

// =============================================================================
// Subtask Shapes
// =============================================================================

export interface SubtaskRow {
  id: number;
  session_id: string;
  result: unknown; // JSONB
  created_at: Date;
}

export function subtasksShapeConfig(sessionId: string): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'subtasks',
      where: `session_id = '${sessionId}'`,
    },
    parser: {
      timestamptz: (value: string) => new Date(value),
    },
    signal: new AbortController().signal,
  };
}

export function useSubtasksShape(_sessionId: string): { data: SubtaskRow[]; isLoading: boolean } {
  throw new Error('useSubtasksShape must be imported from a client component');
}

// =============================================================================
// Combined Session View
// =============================================================================

/**
 * Hook that provides a complete real-time view of a session including
 * messages and parts. Use this for building live agent UIs.
 */
export function useSessionRealtime(_sessionId: string): {
  session: SessionRow | undefined;
  messages: Array<{ message: MessageRow; parts: PartRow[] }>;
  isLoading: boolean;
} {
  throw new Error('useSessionRealtime must be imported from a client component');
}

// =============================================================================
// JJ Change Shapes
// =============================================================================

export interface ChangeRow {
  change_id: string;
  repository_id: number;
  session_id: string | null;
  commit_id: string;
  description: string;
  author_name: string;
  author_email: string;
  timestamp: number;
  is_empty: boolean;
  has_conflicts: boolean;
  created_at: Date;
}

export interface BookmarkRow {
  id: number;
  repository_id: number;
  name: string;
  target_change_id: string;
  pusher_id: number | null;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface ConflictRow {
  id: number;
  repository_id: number;
  session_id: string | null;
  change_id: string;
  file_path: string;
  conflict_type: string;
  resolved: boolean;
  resolved_by: number | null;
  resolution_method: string | null;
  resolved_at: Date | null;
  created_at: Date;
}

export interface JjOperationRow {
  id: number;
  repository_id: number;
  session_id: string | null;
  operation_id: string;
  operation_type: string;
  description: string;
  timestamp: number;
  is_undone: boolean;
}

export function changesShapeConfig(repositoryId: number): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'changes',
      where: `repository_id = '${repositoryId}'`,
    },
    signal: new AbortController().signal,
  };
}

export function useChangesShape(_repositoryId: number): { data: ChangeRow[]; isLoading: boolean } {
  throw new Error('useChangesShape must be imported from a client component');
}

export function bookmarksShapeConfig(repositoryId: number): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'bookmarks',
      where: `repository_id = '${repositoryId}'`,
    },
    signal: new AbortController().signal,
  };
}

export function useBookmarksShape(_repositoryId: number): { data: BookmarkRow[]; isLoading: boolean } {
  throw new Error('useBookmarksShape must be imported from a client component');
}

export function conflictsShapeConfig(repositoryId: number): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'conflicts',
      where: `repository_id = '${repositoryId}'`,
    },
    signal: new AbortController().signal,
  };
}

export function useConflictsShape(_repositoryId: number): { data: ConflictRow[]; isLoading: boolean } {
  throw new Error('useConflictsShape must be imported from a client component');
}

export function jjOperationsShapeConfig(repositoryId: number): ShapeOptions {
  return {
    url: `${API_URL}/shape`,
    params: {
      table: 'jj_operations',
      where: `repository_id = '${repositoryId}'`,
    },
    signal: new AbortController().signal,
  };
}

export function useJjOperationsShape(_repositoryId: number): { data: JjOperationRow[]; isLoading: boolean } {
  throw new Error('useJjOperationsShape must be imported from a client component');
}
