/**
 * Jujutsu (JJ) Workspace binding for Node.js
 * Provides native access to jj-lib functionality
 */

/**
 * Native bookmark representation
 */
export interface NativeBookmark {
  name: string;
  targetId?: string;
}

/**
 * Native change representation
 */
export interface NativeChange {
  changeId: string;
  id: string;
  description: string;
  authorName: string;
  authorEmail: string;
  authorTimestamp: number;
  isEmpty: boolean;
}

/**
 * Represents a Jujutsu workspace instance
 */
export interface JjWorkspaceInstance {
  /**
   * List bookmarks in the workspace
   */
  listBookmarks(): NativeBookmark[];

  /**
   * List changes in the workspace
   * @param limit - Maximum number of changes to return
   * @param bookmark - Optional bookmark filter
   */
  listChanges(limit: number, bookmark: string | null): NativeChange[];

  /**
   * List files at a specific change
   * @param changeId - The change ID
   */
  listFiles(changeId: string): string[];

  /**
   * Get content of a file at a specific change
   * @param changeId - The change ID
   * @param path - Path to the file
   */
  getFileContent(changeId: string, path: string): string;
}

/**
 * JjWorkspace class for working with Jujutsu repositories
 */
export declare const JjWorkspace: {
  /**
   * Open a workspace at the given path
   * @param path - Path to the workspace directory
   */
  open(path: string): JjWorkspaceInstance;

  /**
   * Initialize a colocated jj workspace in an existing git repo
   * @param path - Path to the git repository
   */
  initColocated(path: string): void;
};

/**
 * Check if a path is a JJ workspace
 * @param path - Path to check
 */
export declare function isJjWorkspace(path: string): boolean;

/**
 * Check if a path is a Git repository
 * @param path - Path to check
 */
export declare function isGitRepo(path: string): boolean;
