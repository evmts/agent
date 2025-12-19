/**
 * JJ-based Snapshot System
 *
 * This module provides a lightweight state capture mechanism using jj (Jujutsu).
 * Unlike the Python implementation that manually manages Git tree objects,
 * this leverages jj's native capabilities:
 *
 * - Working copy changes are automatically tracked
 * - Each snapshot is a jj commit with a stable change ID
 * - Operation log provides built-in undo/redo
 * - Colocates with existing git repos seamlessly
 *
 * Key Concepts:
 * - Snapshot: A captured filesystem state (jj commit)
 * - ChangeId: Stable identifier that survives rebases (preferred over CommitId)
 * - Operation: An atomic jj operation that can be undone
 */

import { JjWorkspace, isJjWorkspace, type JjCommitInfo } from '../index.js';

// ============================================================================
// Types
// ============================================================================

export interface FileDiff {
  path: string;
  changeType: 'added' | 'modified' | 'deleted';
  beforeContent?: string;
  afterContent?: string;
  addedLines: number;
  deletedLines: number;
}

export interface SnapshotInfo {
  /** Stable change ID (survives rebases) */
  changeId: string;
  /** Commit ID (may change on rebase) */
  commitId: string;
  /** Snapshot description/message */
  description: string;
  /** When the snapshot was created */
  timestamp: number;
  /** Whether the snapshot has any changes */
  isEmpty: boolean;
}

export interface SessionState {
  /** Current session ID */
  sessionId: string;
  /** Ordered list of snapshot change IDs */
  history: string[];
  /** The initial snapshot when session started */
  initialSnapshot: string;
}

// ============================================================================
// Snapshot Manager
// ============================================================================

/**
 * Manages snapshots for a single directory using jj.
 *
 * Each Snapshot instance is tied to a workspace directory and provides
 * operations for capturing, comparing, and restoring filesystem states.
 */
export class Snapshot {
  private workspace: JjWorkspace;
  private workspacePath: string;
  private initialized: boolean = false;

  private constructor(workspace: JjWorkspace, path: string) {
    this.workspace = workspace;
    this.workspacePath = path;
    this.initialized = true;
  }

  /**
   * Initialize a new snapshot system for a directory.
   * If the directory already has a jj workspace, opens it.
   * Otherwise, initializes a new jj workspace (colocated with git if present).
   */
  static init(directory: string): Snapshot {
    let workspace: JjWorkspace;

    if (isJjWorkspace(directory)) {
      // Open existing jj workspace
      workspace = JjWorkspace.open(directory);
    } else {
      // Check if it's a git repo - if so, colocate
      const hasGit = Bun.file(`${directory}/.git`).size > 0;

      if (hasGit) {
        workspace = JjWorkspace.initColocated(directory);
      } else {
        workspace = JjWorkspace.init(directory);
      }
    }

    return new Snapshot(workspace, directory);
  }

  /**
   * Open an existing snapshot system for a directory.
   * Throws if the directory is not a jj workspace.
   */
  static open(directory: string): Snapshot {
    if (!isJjWorkspace(directory)) {
      throw new Error(`Not a jj workspace: ${directory}`);
    }
    const workspace = JjWorkspace.open(directory);
    return new Snapshot(workspace, directory);
  }

  // ==========================================================================
  // Core Snapshot Operations
  // ==========================================================================

  /**
   * Capture the current filesystem state as a snapshot.
   *
   * This creates a new jj commit with all current changes.
   * Returns the stable change ID for the snapshot.
   */
  async track(description: string = ''): Promise<string> {
    // In jj, we create a new commit to capture the current state
    // The working copy changes are automatically tracked
    const msg = description || 'snapshot';
    const result = await Bun.$`jj commit -m ${msg}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to create snapshot: ${result.stderr.toString()}`);
    }

    // Reload workspace to get fresh state
    this.workspace = JjWorkspace.open(this.workspacePath);

    // The snapshot is the parent of the current working copy
    const parentResult = await Bun.$`jj log -r @- --no-graph -T 'change_id'`.cwd(this.workspacePath).quiet();
    return parentResult.stdout.toString().trim();
  }

  /**
   * Get the current working copy state without committing.
   * Returns the change ID of the current (uncommitted) state.
   */
  async current(): Promise<string> {
    const result = await Bun.$`jj log -r @ --no-graph -T 'change_id'`.cwd(this.workspacePath).quiet();
    return result.stdout.toString().trim();
  }

  /**
   * Get list of files that changed between two snapshots.
   * If toChangeId is not provided, compares against working copy.
   */
  async patch(fromChangeId: string, toChangeId?: string): Promise<string[]> {
    const toRef = toChangeId || '@';
    const result = await Bun.$`jj diff --from ${fromChangeId} --to ${toRef} --summary`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to get patch: ${result.stderr.toString()}`);
    }

    // Parse jj diff --summary output: "M path/to/file" format
    const lines = result.stdout.toString().trim().split('\n').filter(Boolean);
    return lines.map(line => line.substring(2).trim()); // Remove "M " prefix
  }

  /**
   * Get detailed diff between two snapshots.
   * If toChangeId is not provided, compares against working copy.
   */
  async diff(fromChangeId: string, toChangeId?: string): Promise<FileDiff[]> {
    const toRef = toChangeId || '@';

    // Get summary first for change types
    const summaryResult = await Bun.$`jj diff --from ${fromChangeId} --to ${toRef} --summary`.cwd(this.workspacePath).quiet();

    if (summaryResult.exitCode !== 0) {
      throw new Error(`Failed to get diff summary: ${summaryResult.stderr.toString()}`);
    }

    const diffs: FileDiff[] = [];
    const lines = summaryResult.stdout.toString().trim().split('\n').filter(Boolean);

    for (const line of lines) {
      const changeCode = line[0];
      const path = line.substring(2).trim();

      let changeType: 'added' | 'modified' | 'deleted';
      switch (changeCode) {
        case 'A': changeType = 'added'; break;
        case 'D': changeType = 'deleted'; break;
        case 'M':
        default: changeType = 'modified'; break;
      }

      // Get the actual diff for line counts
      const diffResult = await Bun.$`jj diff --from ${fromChangeId} --to ${toRef} ${path} --stat`.cwd(this.workspacePath).quiet();

      let addedLines = 0;
      let deletedLines = 0;

      // Parse stat output for line counts
      const statOutput = diffResult.stdout.toString();
      const statMatch = statOutput.match(/(\d+) insertion.*?(\d+) deletion/);
      if (statMatch) {
        addedLines = parseInt(statMatch[1], 10);
        deletedLines = parseInt(statMatch[2], 10);
      }

      diffs.push({
        path,
        changeType,
        addedLines,
        deletedLines,
      });
    }

    return diffs;
  }

  /**
   * Restore specific files from a snapshot.
   * Only restores the specified files, leaving others untouched.
   */
  async revert(changeId: string, files: string[]): Promise<void> {
    if (files.length === 0) return;

    const result = await Bun.$`jj restore --from ${changeId} ${files}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to revert files: ${result.stderr.toString()}`);
    }
  }

  /**
   * Fully restore the working copy to a snapshot state.
   * This discards all current changes and resets to the snapshot.
   */
  async restore(changeId: string): Promise<void> {
    const result = await Bun.$`jj restore --from ${changeId}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to restore snapshot: ${result.stderr.toString()}`);
    }
  }

  /**
   * Get file contents at a specific snapshot.
   */
  async getFileAt(changeId: string, filePath: string): Promise<string | null> {
    const result = await Bun.$`jj file show -r ${changeId} ${filePath}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      return null; // File doesn't exist at that snapshot
    }

    return result.stdout.toString();
  }

  /**
   * List all files at a specific snapshot.
   */
  async listFilesAt(changeId: string): Promise<string[]> {
    const result = await Bun.$`jj file list -r ${changeId}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to list files: ${result.stderr.toString()}`);
    }

    return result.stdout.toString().trim().split('\n').filter(Boolean);
  }

  /**
   * Check if a file exists at a specific snapshot.
   */
  async fileExistsAt(changeId: string, filePath: string): Promise<boolean> {
    const files = await this.listFilesAt(changeId);
    return files.includes(filePath);
  }

  // ==========================================================================
  // Snapshot Information
  // ==========================================================================

  /**
   * Get information about a snapshot by its change ID.
   */
  async getSnapshot(changeId: string): Promise<SnapshotInfo> {
    const result = await Bun.$`jj log -r ${changeId} --no-graph -T 'commit_id ++ "\n" ++ description ++ "\n" ++ committer.timestamp() ++ "\n" ++ empty'`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Snapshot not found: ${changeId}`);
    }

    const lines = result.stdout.toString().trim().split('\n');

    return {
      changeId,
      commitId: lines[0] || '',
      description: lines[1] || '',
      timestamp: parseInt(lines[2], 10) || Date.now(),
      isEmpty: lines[3] === 'true',
    };
  }

  /**
   * List recent snapshots.
   */
  async listSnapshots(limit: number = 50): Promise<SnapshotInfo[]> {
    const result = await Bun.$`jj log --no-graph -n ${limit} -T 'change_id ++ "|" ++ commit_id ++ "|" ++ description.first_line() ++ "|" ++ committer.timestamp() ++ "|" ++ empty ++ "\n"'`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to list snapshots: ${result.stderr.toString()}`);
    }

    const lines = result.stdout.toString().trim().split('\n').filter(Boolean);

    return lines.map(line => {
      const [changeId, commitId, description, timestamp, isEmpty] = line.split('|');
      return {
        changeId,
        commitId,
        description,
        timestamp: parseInt(timestamp, 10) || Date.now(),
        isEmpty: isEmpty === 'true',
      };
    });
  }

  // ==========================================================================
  // Operation Log (Undo/Redo)
  // ==========================================================================

  /**
   * Undo the last jj operation.
   * This leverages jj's built-in operation log.
   */
  async undo(): Promise<void> {
    const result = await Bun.$`jj undo`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to undo: ${result.stderr.toString()}`);
    }

    // Reload workspace
    this.workspace = JjWorkspace.open(this.workspacePath);
  }

  /**
   * Get the operation log.
   */
  async getOperationLog(limit: number = 20): Promise<Array<{ id: string; description: string; timestamp: number }>> {
    const result = await Bun.$`jj op log --no-graph -n ${limit} -T 'self.id() ++ "|" ++ description ++ "|" ++ self.time().end() ++ "\n"'`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to get operation log: ${result.stderr.toString()}`);
    }

    const lines = result.stdout.toString().trim().split('\n').filter(Boolean);

    return lines.map(line => {
      const [id, description, timestamp] = line.split('|');
      return {
        id,
        description,
        timestamp: parseInt(timestamp, 10) || Date.now(),
      };
    });
  }

  /**
   * Restore to a specific operation.
   */
  async restoreOperation(operationId: string): Promise<void> {
    const result = await Bun.$`jj op restore ${operationId}`.cwd(this.workspacePath).quiet();

    if (result.exitCode !== 0) {
      throw new Error(`Failed to restore operation: ${result.stderr.toString()}`);
    }

    this.workspace = JjWorkspace.open(this.workspacePath);
  }

  // ==========================================================================
  // Accessors
  // ==========================================================================

  get root(): string {
    return this.workspace.root;
  }

  get isInitialized(): boolean {
    return this.initialized;
  }
}

// ============================================================================
// Session Manager
// ============================================================================

/**
 * Manages snapshot sessions across multiple directories.
 * Provides per-session state tracking similar to the Python implementation.
 */
export class SnapshotSessionManager {
  private sessions: Map<string, { snapshot: Snapshot; state: SessionState }> = new Map();

  /**
   * Initialize a new session for a directory.
   * Returns the initial snapshot change ID.
   */
  async initSession(sessionId: string, directory: string): Promise<string> {
    const snapshot = Snapshot.init(directory);

    // Capture initial state
    const initialSnapshot = await snapshot.track(`Session ${sessionId} started`);

    const state: SessionState = {
      sessionId,
      history: [initialSnapshot],
      initialSnapshot,
    };

    this.sessions.set(sessionId, { snapshot, state });

    return initialSnapshot;
  }

  /**
   * Get the snapshot instance for a session.
   */
  getSession(sessionId: string): Snapshot | null {
    return this.sessions.get(sessionId)?.snapshot || null;
  }

  /**
   * Track a new snapshot in a session.
   */
  async trackSnapshot(sessionId: string, description: string = ''): Promise<string | null> {
    const session = this.sessions.get(sessionId);
    if (!session) return null;

    const changeId = await session.snapshot.track(description);
    session.state.history.push(changeId);

    return changeId;
  }

  /**
   * Get the snapshot history for a session.
   */
  getHistory(sessionId: string): string[] {
    return this.sessions.get(sessionId)?.state.history || [];
  }

  /**
   * Compute diff between two snapshots in a session.
   */
  async computeDiff(sessionId: string, fromChangeId: string, toChangeId?: string): Promise<FileDiff[]> {
    const session = this.sessions.get(sessionId);
    if (!session) return [];

    return session.snapshot.diff(fromChangeId, toChangeId);
  }

  /**
   * Restore a session to a previous snapshot.
   */
  async restoreSnapshot(sessionId: string, changeId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    await session.snapshot.restore(changeId);
  }

  /**
   * Clean up a session.
   */
  cleanupSession(sessionId: string): void {
    this.sessions.delete(sessionId);
  }

  /**
   * Get all active session IDs.
   */
  getActiveSessions(): string[] {
    return Array.from(this.sessions.keys());
  }
}

// ============================================================================
// Default Export
// ============================================================================

export default Snapshot;
