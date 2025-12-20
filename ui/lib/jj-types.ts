/**
 * JJ-Native Type Definitions
 *
 * These types represent jj (Jujutsu) version control concepts.
 * Key differences from git:
 * - Change IDs are stable (survive rebases), commit IDs may change
 * - Conflicts are first-class citizens, stored in commits
 * - Bookmarks replace branches (movable labels)
 * - Operations are tracked for undo/redo
 */

// =============================================================================
// Core Change Types
// =============================================================================

/**
 * A Change represents a captured state in jj.
 * The changeId is stable and survives rebases, unlike git commit SHAs.
 */
export interface Change {
  /** Stable 8-12 char identifier (survives rebases) */
  changeId: string;
  /** Full commit hash (may change on rebase) */
  commitId: string;
  /** Parent change IDs */
  parentChangeIds: string[];
  /** Change description/message */
  description: string;
  /** Author information */
  author: {
    name: string;
    email: string;
  };
  /** Unix timestamp in milliseconds */
  timestamp: number;
  /** Whether the change has any file modifications */
  isEmpty: boolean;
  /** Whether the change contains unresolved conflicts */
  hasConflicts: boolean;
}

/**
 * Detailed change information including file changes
 */
export interface ChangeDetail extends Change {
  /** Files modified in this change */
  files: ChangeFile[];
  /** Total lines added */
  additions: number;
  /** Total lines deleted */
  deletions: number;
}

/**
 * A file changed in a change
 */
export interface ChangeFile {
  path: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  oldPath?: string;
  additions: number;
  deletions: number;
  isBinary: boolean;
  hasConflict: boolean;
}

/**
 * Status of a change
 */
export type ChangeStatus = 'clean' | 'conflicted' | 'empty';

// =============================================================================
// Bookmark Types (replace Branches)
// =============================================================================

/**
 * A Bookmark is a movable label pointing to a change.
 * Unlike git branches, bookmarks are just names - they don't affect history.
 */
export interface Bookmark {
  id: number;
  repositoryId: number;
  /** Bookmark name (e.g., 'main', 'feature-x') */
  name: string;
  /** The change ID this bookmark points to */
  targetChangeId: string;
  /** User who last moved this bookmark */
  pusherId: number | null;
  /** Whether this is the default bookmark for the repo */
  isDefault: boolean;
  createdAt: Date;
  updatedAt: Date;

  // Joined fields
  pusherUsername?: string;
}

/**
 * Protected bookmark rule
 */
export interface ProtectedBookmark {
  id: number;
  repositoryId: number;
  /** Bookmark name or glob pattern */
  ruleName: string;
  priority: number;

  /** Require using landing queue to update */
  requireLandingQueue: boolean;

  /** Direct push protection */
  canPush: boolean;
  enableWhitelist: boolean;
  whitelistUserIds: number[];

  /** Approval requirements */
  enableApprovals: boolean;
  requiredApprovals: number;
  approvalsWhitelistUserIds: number[];

  /** Status checks */
  enableStatusCheck: boolean;
  statusCheckContexts: string[];

  createdAt: Date;
  updatedAt: Date;
}

// =============================================================================
// Conflict Types
// =============================================================================

/**
 * A conflict in a change.
 * Unlike git, jj stores conflicts in commits - they don't block operations.
 */
export interface Conflict {
  id: number;
  repositoryId: number | null;
  sessionId: string | null;
  /** The change containing this conflict */
  changeId: string;
  /** Path to the conflicted file */
  filePath: string;
  /** Type of conflict */
  conflictType: ConflictType;
  /** Whether the conflict has been resolved */
  resolved: boolean;
  /** User who resolved the conflict */
  resolvedBy: number | null;
  /** How the conflict was resolved */
  resolutionMethod: ResolutionMethod | null;
  resolvedAt: Date | null;
  createdAt: Date;
}

export type ConflictType = 'content' | 'delete' | 'add' | 'modify_delete';

export type ResolutionMethod = 'manual' | 'ours' | 'theirs' | 'auto';

/**
 * Conflict with file content for resolution UI
 */
export interface ConflictDetail extends Conflict {
  /** Our version of the file */
  oursContent?: string;
  /** Their version of the file */
  theirsContent?: string;
  /** Base version (common ancestor) */
  baseContent?: string;
}

// =============================================================================
// Operation Types (jj op log)
// =============================================================================

/**
 * A jj operation - every action is tracked for undo/redo.
 */
export interface Operation {
  id: number;
  repositoryId: number | null;
  sessionId: string | null;
  /** jj operation ID */
  operationId: string;
  /** Type of operation */
  type: OperationType;
  /** Human-readable description */
  description: string;
  /** Unix timestamp in milliseconds */
  timestamp: number;
  /** Whether this operation has been undone */
  isUndone: boolean;
  /** Additional metadata */
  metadata?: Record<string, unknown>;
}

export type OperationType =
  | 'snapshot'
  | 'commit'
  | 'describe'
  | 'new'
  | 'edit'
  | 'abandon'
  | 'restore'
  | 'rebase'
  | 'squash'
  | 'split'
  | 'bookmark'
  | 'undo';

// =============================================================================
// Landing Queue Types (replace Pull Requests)
// =============================================================================

/**
 * A request to land a change onto a bookmark.
 * Replaces the PR workflow with jj's conflict-aware landing.
 */
export interface LandingRequest {
  id: number;
  repositoryId: number;
  /** The change to land */
  changeId: string;
  /** Target bookmark to land onto */
  targetBookmark: string;
  /** Title for the landing request */
  title: string | null;
  /** Description/body */
  description: string | null;
  /** User who created the request */
  authorId: number;
  /** Current status */
  status: LandingStatus;
  /** Whether there are conflicts with target */
  hasConflicts: boolean;
  /** Files with conflicts */
  conflictedFiles: string[] | null;
  /** When the change was landed */
  landedAt: Date | null;
  /** User who executed the landing */
  landedBy: number | null;
  /** Resulting change ID after landing */
  landedChangeId: string | null;
  createdAt: Date;
  updatedAt: Date;

  // Joined fields
  author?: {
    id: number;
    username: string;
    displayName: string | null;
  };
  change?: Change;
}

export type LandingStatus =
  | 'pending'    // Waiting to be processed
  | 'checking'   // Checking for conflicts
  | 'ready'      // Ready to land (no conflicts)
  | 'conflicted' // Has conflicts that need resolution
  | 'landed'     // Successfully landed
  | 'cancelled'; // Cancelled by user

/**
 * Review on a landing request
 */
export interface LandingReview {
  id: number;
  landingId: number;
  reviewerId: number;
  type: ReviewType;
  content: string | null;
  changeId: string | null;
  official: boolean;
  stale: boolean;
  dismissed: boolean;
  createdAt: Date;
  updatedAt: Date;

  // Joined
  reviewer?: {
    id: number;
    username: string;
    displayName: string | null;
  };
}

export type ReviewType = 'pending' | 'comment' | 'approve' | 'request_changes';

// =============================================================================
// Comparison Types
// =============================================================================

/**
 * Comparison between two changes
 */
export interface ChangeComparison {
  /** Base change ID */
  fromChangeId: string;
  /** Head change ID */
  toChangeId: string;
  /** Common ancestor change ID */
  commonAncestor: string | null;
  /** Changes between from and to */
  changes: Change[];
  /** Files changed */
  files: ChangeFile[];
  /** Total additions */
  totalAdditions: number;
  /** Total deletions */
  totalDeletions: number;
  /** Whether there would be conflicts if merged */
  wouldConflict: boolean;
  /** Files that would conflict */
  potentialConflicts: string[];
}

// =============================================================================
// Tree Types (same as git, changes are minimal)
// =============================================================================

export interface TreeEntry {
  mode: string;
  type: 'blob' | 'tree';
  /** In jj, this is still a content hash */
  hash: string;
  name: string;
}

// =============================================================================
// Diff Types
// =============================================================================

export interface DiffHunk {
  oldStart: number;
  oldLines: number;
  newStart: number;
  newLines: number;
  content: string;
}

export interface FileDiff {
  path: string;
  oldPath?: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  additions: number;
  deletions: number;
  isBinary: boolean;
  hunks: DiffHunk[];
  /** Whether this file has a conflict */
  hasConflict: boolean;
}
