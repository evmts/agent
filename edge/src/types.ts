/**
 * Cloudflare Workers environment bindings and configuration.
 * Provides access to Durable Objects, secrets, and feature flags.
 */
export interface Env {
  // Durable Objects
  DATA_SYNC: DurableObjectNamespace;

  // Environment variables
  ORIGIN_HOST: string;
  ELECTRIC_URL: string;
  JWT_SECRET: string;

  /**
   * Shared secret used to authenticate cache invalidation requests from K8s.
   * Must match the PUSH_SECRET configured in the Kubernetes deployment.
   */
  PUSH_SECRET: string;

  /**
   * Feature flag to enable push-based cache invalidation.
   * When "true", the edge will trust cached data indefinitely until an
   * invalidation message is received from K8s. When false or unset, falls
   * back to 5-second TTL polling.
   *
   * @default undefined (falls back to TTL polling)
   */
  ENABLE_PUSH_INVALIDATION?: string;
}

export interface User {
  id: number;
  username: string;
  displayName: string | null;
  avatarUrl: string | null;
  bio: string | null;
  createdAt: string;
}

export interface Repository {
  id: number;
  userId: number;
  name: string;
  description: string | null;
  isPublic: boolean;
  defaultBranch: string;
  createdAt: string;
  updatedAt: string;
  // Joined fields
  username?: string;
}

export interface Issue {
  id: number;
  repositoryId: number;
  authorId: number;
  issueNumber: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  createdAt: string;
  updatedAt: string;
  closedAt: string | null;
  // Joined fields
  authorUsername?: string;
}

export interface Comment {
  id: number;
  issueId: number;
  authorId: number;
  body: string;
  createdAt: string;
  // Joined fields
  authorUsername?: string;
}

export interface PullRequest {
  id: number;
  issueId: number;
  headRepoId: number | null;
  headBranch: string;
  baseRepoId: number;
  baseBranch: string;
  status: 'checking' | 'mergeable' | 'conflict' | 'merged';
  hasMerged: boolean;
  createdAt: string;
  updatedAt: string;
  // From joined issue
  title?: string;
  body?: string;
  state?: string;
  authorUsername?: string;
  issueNumber?: number;
}

export interface Review {
  id: number;
  pullRequestId: number;
  reviewerId: number;
  type: 'comment' | 'approve' | 'request_changes';
  content: string | null;
  createdAt: string;
  // Joined fields
  reviewerUsername?: string;
}

export interface JWTPayload {
  userId: number;
  username: string;
  isAdmin: boolean;
  exp: number;
}

export interface RouteMatch {
  type: 'edge' | 'origin';
  handler?: string;
  params?: Record<string, string>;
}

/**
 * Cache invalidation message sent from K8s to edge Durable Objects.
 * Used to notify edge caches when data changes in the origin database
 * or git repositories, enabling instant cache invalidation without polling.
 */
export interface InvalidationMessage {
  /**
   * Type of invalidation event.
   * - 'sql': Database table changed (e.g., issue created, PR merged)
   * - 'git': Repository content changed (e.g., push, commit)
   */
  type: 'sql' | 'git';

  /**
   * Database table name that changed (only for type: 'sql').
   * Used to clear Electric SQL shape sync metadata for that table.
   *
   * @example 'issues', 'pull_requests', 'users'
   */
  table?: string;

  /**
   * Repository identifier in "owner/repo" format (only for type: 'git').
   * Used to identify which repository's cache to invalidate.
   *
   * @example 'torvalds/linux', 'facebook/react'
   */
  repoKey?: string;

  /**
   * New merkle root hash for the repository (only for type: 'git').
   * Cached tree and file data with mismatched merkle roots will be
   * considered stale and refetched from origin.
   *
   * @example 'a1b2c3d4e5f6...'
   */
  merkleRoot?: string;

  /**
   * Unix timestamp (milliseconds) when the invalidation event occurred.
   * Used for debugging and monitoring invalidation latency.
   */
  timestamp: number;
}

/**
 * Metadata for tracking Electric SQL shape stream synchronization state.
 * Stored in Durable Object SQLite to enable incremental syncing and
 * resumable streams across DO evictions.
 */
export interface StreamState {
  /**
   * Unique identifier for the shape (table + where clause).
   * @example 'issues:repository_id = 123'
   */
  shapeName: string;

  /**
   * Opaque handle identifying the shape stream on Electric SQL server.
   * Used to resume syncing from the correct shape after DO restart.
   */
  shapeHandle: string;

  /**
   * Last message offset processed from the shape stream.
   * Used to resume syncing without reprocessing old messages.
   */
  lastOffset: string;

  /**
   * ISO 8601 timestamp of the last successful sync.
   * Used for TTL-based cache expiration when push invalidation is disabled.
   */
  lastSyncedAt: string;

  /**
   * Whether a sync is currently in progress for this shape.
   * Used to prevent concurrent syncing of the same shape.
   */
  isStreaming: boolean;
}

/**
 * Cached git tree data with merkle root validation.
 * Stores directory listings and file metadata. Cache entries are validated
 * against the current merkle root before serving to ensure consistency.
 */
export interface GitCacheEntry {
  /**
   * Unique cache key identifying the tree entry.
   * Format: "owner/repo:ref:path"
   * @example 'torvalds/linux:main:drivers/usb'
   */
  cacheKey: string;

  /**
   * Merkle root hash that this cache entry was created under.
   * If the current merkle root differs, this entry is considered stale.
   */
  merkleRoot: string;

  /**
   * JSON-serialized tree data (array of file/directory objects).
   * Null if the tree could not be fetched or is empty.
   */
  treeData: string | null;

  /**
   * ISO 8601 timestamp when this entry was cached.
   * Used for debugging and cache analytics.
   */
  cachedAt: string;
}
