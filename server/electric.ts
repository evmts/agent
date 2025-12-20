/**
 * ElectricSQL shape configuration utilities.
 *
 * Provides helper functions for defining shapes that sync agent state
 * in real-time to connected clients.
 */

// Base Electric URL from environment
const ELECTRIC_URL = process.env.ELECTRIC_URL || 'http://localhost:3000';

export interface ShapeConfig {
  url: string;
  params: {
    table: string;
    where?: string;
    columns?: string;
  };
}

/**
 * Create a shape config for syncing sessions.
 * Optionally filter by project_id or other criteria.
 */
export function sessionsShapeConfig(where?: string): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'sessions',
      ...(where ? { where } : {}),
    },
  };
}

/**
 * Create a shape config for syncing messages for a specific session.
 */
export function messagesShapeConfig(sessionId: string): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'messages',
      where: `session_id = '${sessionId}'`,
    },
  };
}

/**
 * Create a shape config for syncing parts for a specific session.
 * This is the primary shape for real-time streaming updates.
 */
export function partsShapeConfig(sessionId: string): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'parts',
      where: `session_id = '${sessionId}'`,
    },
  };
}

/**
 * Create a shape config for syncing snapshot history for a session.
 */
export function snapshotHistoryShapeConfig(sessionId: string): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'snapshot_history',
      where: `session_id = '${sessionId}'`,
    },
  };
}

/**
 * Create a shape config for syncing subtasks for a session.
 */
export function subtasksShapeConfig(sessionId: string): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'subtasks',
      where: `session_id = '${sessionId}'`,
    },
  };
}

/**
 * Create a shape config for syncing changes for a specific repository.
 */
export function changesShapeConfig(repositoryId: number): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'changes',
      where: `repository_id = '${repositoryId}'`,
    },
  };
}

/**
 * Create a shape config for syncing bookmarks for a specific repository.
 */
export function bookmarksShapeConfig(repositoryId: number): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'bookmarks',
      where: `repository_id = '${repositoryId}'`,
    },
  };
}

/**
 * Create a shape config for syncing jj operations for a specific repository.
 */
export function jjOperationsShapeConfig(repositoryId: number): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'jj_operations',
      where: `repository_id = '${repositoryId}'`,
    },
  };
}

/**
 * Create a shape config for syncing conflicts for a specific repository.
 */
export function conflictsShapeConfig(repositoryId: number): ShapeConfig {
  return {
    url: `${ELECTRIC_URL}/v1/shape`,
    params: {
      table: 'conflicts',
      where: `repository_id = '${repositoryId}'`,
    },
  };
}

/**
 * Helper to build a complete Electric shape URL from a config.
 */
export function buildShapeUrl(config: ShapeConfig): string {
  const url = new URL(config.url);
  Object.entries(config.params).forEach(([key, value]) => {
    if (value !== undefined) {
      url.searchParams.set(key, value);
    }
  });
  return url.toString();
}
