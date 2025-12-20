/**
 * JJ (Jujutsu) Operations Library
 *
 * Uses native jj-lib bindings for repository operations.
 * Key differences from git:
 * - Uses change IDs (stable) instead of commit SHAs
 * - Bookmarks instead of branches
 * - First-class conflict handling
 * - Operation log for undo/redo
 */

import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { JjWorkspace, isJjWorkspace } from "../../snapshot/index.mjs";
import type {
  Change,
  ChangeDetail,
  ChangeFile,
  Bookmark,
  Conflict,
  Operation,
  TreeEntry,
  FileDiff,
  DiffHunk,
  ChangeComparison,
  BlameLine,
} from "./jj-types";
import { initIssuesRepo } from "./git-issues";

const execAsync = promisify(exec);

const REPOS_DIR = `${process.cwd()}/repos`;

// =============================================================================
// Helpers
// =============================================================================

async function run(cmd: string, cwd?: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { cwd, maxBuffer: 10 * 1024 * 1024 });
    return stdout;
  } catch (error: unknown) {
    return (error as { stdout?: string })?.stdout || "";
  }
}

async function runJj(args: string[], cwd: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const { stdout, stderr } = await execAsync(`jj ${args.join(' ')}`, { cwd, maxBuffer: 10 * 1024 * 1024 });
    return { stdout, stderr, exitCode: 0 };
  } catch (error: unknown) {
    const err = error as { stdout?: string; stderr?: string; code?: number };
    return {
      stdout: err.stdout || "",
      stderr: err.stderr || "",
      exitCode: err.code || 1,
    };
  }
}

function getRepoPath(user: string, name: string): string {
  return `${REPOS_DIR}/${user}/${name}`;
}

// =============================================================================
// Repository Initialization
// =============================================================================

/**
 * Initialize a new repository with jj (colocated with git for compatibility)
 * Creates a proper jj workspace with both .jj and .git directories.
 */
export async function initRepo(user: string, name: string): Promise<void> {
  const repoPath = getRepoPath(user, name);

  // Create the repo directory
  await mkdir(repoPath, { recursive: true });

  // Use native jj-lib to initialize colocated workspace
  // This creates both .jj and .git directories
  try {
    JjWorkspace.initColocated(repoPath);

    // Configure git
    await run(`git config user.name "Plue"`, repoPath);
    await run(`git config user.email "plue@local"`, repoPath);

    // Add .jj to .gitignore (jj internal state should not be tracked)
    await writeFile(`${repoPath}/.gitignore`, `.jj/\n`);

    // Create initial content
    await writeFile(`${repoPath}/README.md`, `# ${name}\n\nA new repository.`);

    // Stage and commit with git
    await run(`git add .`, repoPath);
    await run(`git commit -m "Initial commit"`, repoPath);

    // Import git commit into jj
    const workspace = JjWorkspace.open(repoPath);
    // Note: jj auto-imports git changes when you open the workspace

  } catch (e) {
    // Fallback to pure git if native init fails (e.g., jj-lib not available)
    console.log('Native jj initColocated failed:', e);
    console.log('Creating git-only repo (jj features will use CLI fallback)');

    await mkdir(repoPath, { recursive: true });
    await run(`git init`, repoPath);
    await run(`git config user.name "Plue"`, repoPath);
    await run(`git config user.email "plue@local"`, repoPath);

    // Create initial content
    await writeFile(`${repoPath}/README.md`, `# ${name}\n\nA new repository.`);

    // Stage and commit with git
    await run(`git add .`, repoPath);
    await run(`git commit -m "Initial commit"`, repoPath);
  }

  // Initialize the issues repository
  await initIssuesRepo(user, name);
}

/**
 * Delete a repository
 */
export async function deleteRepo(user: string, name: string): Promise<void> {
  const repoPath = getRepoPath(user, name);
  await rm(repoPath, { recursive: true });
}

/**
 * Check if a repository exists
 */
export async function repoExists(user: string, name: string): Promise<boolean> {
  const repoPath = getRepoPath(user, name);
  return existsSync(`${repoPath}/HEAD`) || existsSync(`${repoPath}/.jj`);
}

/**
 * Check if jj is initialized in a repository
 */
export async function isJjRepo(user: string, name: string): Promise<boolean> {
  const repoPath = getRepoPath(user, name);
  return existsSync(`${repoPath}/.jj`);
}

// =============================================================================
// Bookmark Operations (replace Branches)
// =============================================================================

/**
 * List all bookmarks in a repository using native jj-lib bindings
 */
export async function listBookmarks(user: string, name: string): Promise<Bookmark[]> {
  const repoPath = getRepoPath(user, name);
  const isWorkspace = isJjWorkspace(repoPath);
  console.log(`[jj.ts listBookmarks] repoPath=${repoPath} isWorkspace=${isWorkspace} cwd=${process.cwd()}`);

  // Use native jj-lib bindings
  if (isWorkspace) {
    try {
      const workspace = JjWorkspace.open(repoPath);
      const nativeBookmarks = workspace.listBookmarks();
      console.log(`[jj.ts listBookmarks] native returned ${nativeBookmarks.length} bookmarks:`, nativeBookmarks.map(b => b.name));

      return nativeBookmarks.map((bm, index) => ({
        id: index + 1,
        repositoryId: 0, // Will be filled by caller
        name: bm.name,
        targetChangeId: bm.targetId || '',
        pusherId: null,
        isDefault: bm.name === 'main',
        createdAt: new Date(),
        updatedAt: new Date(),
      }));
    } catch (e) {
      console.error(`[jj.ts listBookmarks] native error:`, e);
      // Log error and fall through to CLI fallback
    }
  }

  // Fallback to CLI for non-jj workspaces (like bare git repos)
  const result = await runJj(
    ['bookmark', 'list', '--template', 'name ++ "|" ++ normal_target.change_id() ++ "\\n"'],
    repoPath
  );

  if (result.exitCode === 0 && result.stdout.trim()) {
    const lines = result.stdout.trim().split('\n').filter(Boolean);

    return lines.map((line, index) => {
      const [bookmarkName, changeId] = line.split('|');
      return {
        id: index + 1,
        repositoryId: 0,
        name: bookmarkName?.trim() || '',
        targetChangeId: changeId?.trim() || '',
        pusherId: null,
        isDefault: bookmarkName?.trim() === 'main',
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    });
  }

  return [];
}

/**
 * Create a new bookmark pointing to a change
 */
export async function createBookmark(
  user: string,
  repo: string,
  bookmarkName: string,
  changeId?: string
): Promise<void> {
  const repoPath = getRepoPath(user, repo);

  if (!isValidBookmarkName(bookmarkName)) {
    throw new Error("Invalid bookmark name");
  }

  const args = ['bookmark', 'create', bookmarkName];
  if (changeId) {
    args.push('-r', changeId);
  }

  const result = await runJj(args, repoPath);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr || "Failed to create bookmark");
  }
}

/**
 * Delete a bookmark
 */
export async function deleteBookmark(
  user: string,
  repo: string,
  bookmarkName: string
): Promise<void> {
  const repoPath = getRepoPath(user, repo);

  // Don't delete the default bookmark
  const defaultBookmark = await getDefaultBookmark(user, repo);
  if (bookmarkName === defaultBookmark) {
    throw new Error("Cannot delete default bookmark");
  }

  const result = await runJj(['bookmark', 'delete', bookmarkName], repoPath);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr || "Failed to delete bookmark");
  }
}

/**
 * Move a bookmark to point to a different change
 */
export async function moveBookmark(
  user: string,
  repo: string,
  bookmarkName: string,
  changeId: string
): Promise<void> {
  const repoPath = getRepoPath(user, repo);

  const result = await runJj(['bookmark', 'set', bookmarkName, '-r', changeId], repoPath);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr || "Failed to move bookmark");
  }
}

/**
 * Get the default bookmark for a repository
 */
export async function getDefaultBookmark(user: string, repo: string): Promise<string> {
  const bookmarks = await listBookmarks(user, repo);
  const defaultBookmark = bookmarks.find(b => b.isDefault);
  return defaultBookmark?.name || 'main';
}

function isValidBookmarkName(name: string): boolean {
  if (!name || name.length === 0) return false;
  if (name.startsWith(".") || name.endsWith(".")) return false;
  if (name.includes("..")) return false;
  if (name.includes(" ") || name.includes("\t")) return false;
  if (name.includes("@")) return false; // @ is special in jj
  return true;
}

// =============================================================================
// Change Operations
// =============================================================================

/**
 * List recent changes in a repository using native jj-lib bindings
 */
export async function listChanges(
  user: string,
  name: string,
  limit: number = 50,
  bookmark?: string
): Promise<Change[]> {
  const repoPath = getRepoPath(user, name);

  // Use native jj-lib bindings
  if (isJjWorkspace(repoPath)) {
    try {
      const workspace = JjWorkspace.open(repoPath);
      const nativeChanges = workspace.listChanges(limit, bookmark || null);

      return nativeChanges.map(c => ({
        changeId: c.changeId,
        commitId: c.id,
        description: c.description,
        author: {
          name: c.authorName,
          email: c.authorEmail,
        },
        timestamp: c.authorTimestamp * 1000,
        isEmpty: c.isEmpty,
        hasConflicts: false, // Not available in native bindings yet
      }));
    } catch (e) {
      console.error('Native jj-lib failed for listChanges:', e);
    }
  }

  // Fallback to CLI for non-jj workspaces
  const template = 'change_id ++ "|" ++ commit_id ++ "|" ++ description.first_line() ++ "|" ++ author.name() ++ "|" ++ author.email() ++ "|" ++ committer.timestamp() ++ "|" ++ empty ++ "|" ++ conflict ++ "\\n"';
  const revset = bookmark ? `ancestors(${bookmark})` : 'all()';

  const result = await runJj(
    ['log', '-r', revset, '--no-graph', '-n', limit.toString(), '-T', template],
    repoPath
  );

  if (result.exitCode === 0 && result.stdout.trim()) {
    return parseChangesOutput(result.stdout);
  }

  return [];
}

/**
 * Get details for a specific change
 */
export async function getChange(
  user: string,
  name: string,
  changeId: string
): Promise<ChangeDetail | null> {
  const repoPath = getRepoPath(user, name);

  const template = 'change_id ++ "|" ++ commit_id ++ "|" ++ description ++ "|" ++ author.name() ++ "|" ++ author.email() ++ "|" ++ committer.timestamp() ++ "|" ++ empty ++ "|" ++ conflict';

  const result = await runJj(['log', '-r', changeId, '--no-graph', '-T', template], repoPath);

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return null;
  }

  const parts = result.stdout.trim().split('|');

  const change: ChangeDetail = {
    changeId: parts[0] || '',
    commitId: parts[1] || '',
    description: parts[2] || '',
    author: {
      name: parts[3] || '',
      email: parts[4] || '',
    },
    timestamp: parseInt(parts[5] || '0', 10) * 1000,
    isEmpty: parts[6] === 'true',
    hasConflicts: parts[7] === 'true',
    parentChangeIds: [],
    files: [],
    additions: 0,
    deletions: 0,
  };

  // Get parent change IDs
  const parentsResult = await runJj(
    ['log', '-r', `parents(${changeId})`, '--no-graph', '-T', 'change_id ++ "\\n"'],
    repoPath
  );
  if (parentsResult.stdout.trim()) {
    change.parentChangeIds = parentsResult.stdout.trim().split('\n').filter(Boolean);
  }

  // Get file changes
  const diffResult = await runJj(['diff', '-r', changeId, '--summary'], repoPath);
  if (diffResult.stdout.trim()) {
    change.files = parseDiffSummary(diffResult.stdout);
    change.additions = change.files.reduce((sum, f) => sum + f.additions, 0);
    change.deletions = change.files.reduce((sum, f) => sum + f.deletions, 0);
  }

  return change;
}

/**
 * Get the current working copy change ID
 */
export async function getCurrentChange(user: string, name: string): Promise<string> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(['log', '-r', '@', '--no-graph', '-T', 'change_id'], repoPath);

  return result.stdout.trim();
}

// =============================================================================
// Tree and File Operations
// =============================================================================

/**
 * Get the file tree at a specific change using native jj-lib bindings
 */
export async function getTree(
  user: string,
  name: string,
  changeId: string,
  path: string = ""
): Promise<TreeEntry[]> {
  const repoPath = getRepoPath(user, name);
  let allFiles: string[] = [];

  // Use native jj-lib bindings
  if (isJjWorkspace(repoPath)) {
    try {
      const workspace = JjWorkspace.open(repoPath);
      allFiles = workspace.listFiles(changeId);
    } catch (e) {
      console.error('Native jj-lib failed for getTree:', e);
    }
  }

  // Fallback to CLI if native failed or not a jj workspace
  if (allFiles.length === 0) {
    const result = await runJj(['file', 'list', '-r', changeId], repoPath);
    if (result.exitCode === 0 && result.stdout.trim()) {
      allFiles = result.stdout.trim().split('\n').filter(Boolean);
    }
  }

  if (allFiles.length === 0) {
    return [];
  }

  // Filter and build tree entries for the given path
  const prefix = path ? `${path}/` : '';
  const entries = new Map<string, TreeEntry>();

  for (const file of allFiles) {
    if (!file.startsWith(prefix) && path !== '') continue;

    const relativePath = path ? file.slice(prefix.length) : file;
    const parts = relativePath.split('/');

    if (parts.length === 0) continue;

    const entryName = parts[0];
    if (!entryName) continue;

    const isDirectory = parts.length > 1;

    if (!entries.has(entryName)) {
      entries.set(entryName, {
        mode: isDirectory ? '040000' : '100644',
        type: isDirectory ? 'tree' : 'blob',
        hash: '', // jj doesn't expose hashes the same way
        name: entryName,
      });
    }
  }

  return Array.from(entries.values()).sort((a, b) => {
    // Directories first, then alphabetical
    if (a.type !== b.type) {
      return a.type === 'tree' ? -1 : 1;
    }
    return a.name.localeCompare(b.name);
  });
}

/**
 * Get file content at a specific change using native jj-lib bindings
 */
export async function getFileContent(
  user: string,
  name: string,
  changeId: string,
  path: string
): Promise<string | null> {
  const repoPath = getRepoPath(user, name);

  // Use native jj-lib bindings
  if (isJjWorkspace(repoPath)) {
    try {
      const workspace = JjWorkspace.open(repoPath);
      const content = workspace.getFileContent(changeId, path);
      return content;
    } catch (e) {
      console.error('Native jj-lib failed for getFileContent:', e);
    }
  }

  // Fallback to CLI for non-jj workspaces
  const result = await runJj(['file', 'show', '-r', changeId, path], repoPath);

  if (result.exitCode === 0 && result.stdout) {
    return result.stdout;
  }

  return null;
}

/**
 * Get file history - list of changes that modified a specific file
 */
export async function getFileHistory(
  user: string,
  name: string,
  path: string,
  bookmark?: string,
  limit: number = 50
): Promise<Change[]> {
  const repoPath = getRepoPath(user, name);

  // Template to extract change info
  const template = 'change_id ++ "|" ++ commit_id ++ "|" ++ description.first_line() ++ "|" ++ author.name() ++ "|" ++ author.email() ++ "|" ++ committer.timestamp() ++ "|" ++ empty ++ "|" ++ conflict ++ "\\n"';

  // Use revset with file path filter
  const revset = bookmark ? `ancestors(${bookmark}) & file(${path})` : `all() & file(${path})`;

  const result = await runJj(
    ['log', '-r', revset, '--no-graph', '-n', limit.toString(), '-T', template],
    repoPath
  );

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return [];
  }

  return parseChangesOutput(result.stdout);
}

/**
 * Get blame/annotate information for a file
 * Note: jj doesn't have a native blame command, so we simulate it by
 * getting the file history and attributing each line to the most recent change
 */
export async function getBlame(
  user: string,
  name: string,
  changeId: string,
  path: string
): Promise<BlameLine[]> {
  const repoPath = getRepoPath(user, name);

  // Get file content
  const content = await getFileContent(user, name, changeId, path);
  if (!content) return [];

  const lines = content.split('\n');

  // Get file history to have change information
  const history = await getFileHistory(user, name, path, changeId, 100);

  // For now, attribute all lines to the most recent change
  // A more sophisticated implementation would trace each line through the history
  const mostRecentChange = history[0];

  if (!mostRecentChange) {
    // No history - return lines without attribution
    return lines.map((line, index) => ({
      lineNumber: index + 1,
      content: line,
      changeId: changeId,
      author: { name: 'Unknown', email: '' },
      timestamp: Date.now(),
      description: 'No history',
    }));
  }

  // Attribute all lines to the most recent change
  return lines.map((line, index) => ({
    lineNumber: index + 1,
    content: line,
    changeId: mostRecentChange.changeId,
    author: mostRecentChange.author,
    timestamp: mostRecentChange.timestamp,
    description: mostRecentChange.description,
  }));
}

// =============================================================================
// Diff and Comparison Operations
// =============================================================================

/**
 * Compare two changes and get the diff
 */
export async function compareChanges(
  user: string,
  name: string,
  fromChangeId: string,
  toChangeId: string
): Promise<ChangeComparison> {
  const repoPath = getRepoPath(user, name);

  // Get the diff summary
  const diffResult = await runJj(['diff', '--from', fromChangeId, '--to', toChangeId, '--summary'], repoPath);

  const files = parseDiffSummary(diffResult.stdout);

  // Get changes between the two
  const changesResult = await runJj(
    ['log', '-r', `${fromChangeId}::${toChangeId}`, '--no-graph', '-T',
      'change_id ++ "|" ++ commit_id ++ "|" ++ description.first_line() ++ "|" ++ author.name() ++ "|" ++ author.email() ++ "|" ++ committer.timestamp() ++ "|" ++ empty ++ "|" ++ conflict ++ "\\n"'],
    repoPath
  );

  const changes = parseChangesOutput(changesResult.stdout);

  // Check for potential conflicts (simulate merge)
  let wouldConflict = false;
  let potentialConflicts: string[] = [];

  // Get common ancestor
  const ancestorResult = await runJj(
    ['log', '-r', `roots(${fromChangeId}::${toChangeId})`, '--no-graph', '-T', 'change_id'],
    repoPath
  );

  return {
    fromChangeId,
    toChangeId,
    commonAncestor: ancestorResult.stdout.trim() || null,
    changes,
    files,
    totalAdditions: files.reduce((sum, f) => sum + f.additions, 0),
    totalDeletions: files.reduce((sum, f) => sum + f.deletions, 0),
    wouldConflict,
    potentialConflicts,
  };
}

/**
 * Get the diff patch for a change
 */
export async function getDiff(
  user: string,
  name: string,
  changeId: string
): Promise<FileDiff[]> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(['diff', '-r', changeId, '--git'], repoPath);

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return [];
  }

  return parseGitDiff(result.stdout);
}

/**
 * Get the full diff content (unified diff format) for a change
 */
export async function getDiffContent(
  user: string,
  name: string,
  changeId: string
): Promise<string> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(['diff', '-r', changeId, '--git'], repoPath);

  if (result.exitCode !== 0) {
    return '';
  }

  return result.stdout;
}

// =============================================================================
// Conflict Operations
// =============================================================================

/**
 * Get conflicts for a change
 */
export async function getConflicts(
  user: string,
  name: string,
  changeId?: string
): Promise<Conflict[]> {
  const repoPath = getRepoPath(user, name);

  const rev = changeId || '@';
  const result = await runJj(['resolve', '--list', '-r', rev], repoPath);

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return [];
  }

  // Parse conflict list output
  const lines = result.stdout.trim().split('\n').filter(Boolean);

  return lines.map((line, index) => ({
    id: index + 1,
    repositoryId: null,
    sessionId: null,
    changeId: changeId || '',
    filePath: line.trim(),
    conflictType: 'content' as const,
    resolved: false,
    resolvedBy: null,
    resolutionMethod: null,
    resolvedAt: null,
    createdAt: new Date(),
  }));
}

/**
 * Check if a change has conflicts
 */
export async function hasConflicts(
  user: string,
  name: string,
  changeId?: string
): Promise<boolean> {
  const conflicts = await getConflicts(user, name, changeId);
  return conflicts.length > 0;
}

// =============================================================================
// Operation Log (Undo/Redo)
// =============================================================================

/**
 * Get the operation log
 */
export async function getOperationLog(
  user: string,
  name: string,
  limit: number = 20
): Promise<Operation[]> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(
    ['op', 'log', '--no-graph', '-n', limit.toString(), '-T',
      'self.id() ++ "|" ++ description ++ "|" ++ self.time().end() ++ "\\n"'],
    repoPath
  );

  if (result.exitCode !== 0 || !result.stdout.trim()) {
    return [];
  }

  const lines = result.stdout.trim().split('\n').filter(Boolean);

  return lines.map((line, index) => {
    const parts = line.split('|');
    return {
      id: index + 1,
      repositoryId: null,
      sessionId: null,
      operationId: parts[0] || '',
      type: parseOperationType(parts[1] || ''),
      description: parts[1] || '',
      timestamp: parseInt(parts[2] || '0', 10) * 1000,
      isUndone: false,
    };
  });
}

/**
 * Undo the last operation
 */
export async function undoOperation(user: string, name: string): Promise<void> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(['undo'], repoPath);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr || "Failed to undo operation");
  }
}

/**
 * Restore to a specific operation
 */
export async function restoreOperation(
  user: string,
  name: string,
  operationId: string
): Promise<void> {
  const repoPath = getRepoPath(user, name);

  const result = await runJj(['op', 'restore', operationId], repoPath);

  if (result.exitCode !== 0) {
    throw new Error(result.stderr || "Failed to restore operation");
  }
}

// =============================================================================
// Landing Operations (replace Merge)
// =============================================================================

/**
 * Check if a change can be landed onto a bookmark without conflicts
 */
export async function checkLandable(
  user: string,
  name: string,
  changeId: string,
  targetBookmark: string
): Promise<{ landable: boolean; conflictedFiles: string[] }> {
  const repoPath = getRepoPath(user, name);
  const tempDir = `/tmp/plue-jj-check-${Date.now()}`;

  try {
    // Clone to temp directory for testing
    await run(`git clone "${repoPath}" "${tempDir}"`);
    await runJj(['git', 'init', '--colocate'], tempDir);

    // Try to rebase the change onto the target
    const result = await runJj(['rebase', '-r', changeId, '-d', targetBookmark], tempDir);

    if (result.exitCode !== 0) {
      // Parse conflict files from error
      return {
        landable: false,
        conflictedFiles: [], // Would need to parse from output
      };
    }

    // Check if the rebased change has conflicts
    const conflicts = await getConflicts(user, name, changeId);

    return {
      landable: conflicts.length === 0,
      conflictedFiles: conflicts.map(c => c.filePath),
    };
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Land a change onto a bookmark
 */
export async function landChange(
  user: string,
  name: string,
  changeId: string,
  targetBookmark: string,
  authorName: string,
  authorEmail: string
): Promise<string> {
  const repoPath = getRepoPath(user, name);
  const tempDir = `/tmp/plue-jj-land-${Date.now()}`;

  try {
    // Clone to temp directory
    await run(`git clone "${repoPath}" "${tempDir}"`);
    await runJj(['git', 'init', '--colocate'], tempDir);

    // Configure author
    await runJj(['config', 'set', '--repo', 'user.name', authorName], tempDir);
    await runJj(['config', 'set', '--repo', 'user.email', authorEmail], tempDir);

    // Rebase the change onto the target bookmark
    await runJj(['rebase', '-r', changeId, '-d', targetBookmark], tempDir);

    // Move the bookmark to the rebased change
    await runJj(['bookmark', 'set', targetBookmark, '-r', changeId], tempDir);

    // Get the new change ID
    const newChangeResult = await runJj(['log', '-r', targetBookmark, '--no-graph', '-T', 'change_id'], tempDir);
    const newChangeId = newChangeResult.stdout.trim();

    // Push changes back (via git for bare repo compatibility)
    await run(`git push origin ${targetBookmark}`, tempDir);

    return newChangeId;
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

// =============================================================================
// Parsing Helpers
// =============================================================================

function parseChangesOutput(output: string): Change[] {
  if (!output.trim()) return [];

  const lines = output.trim().split('\n').filter(Boolean);

  return lines.map(line => {
    const parts = line.split('|');
    return {
      changeId: parts[0] || '',
      commitId: parts[1] || '',
      description: parts[2] || '',
      author: {
        name: parts[3] || '',
        email: parts[4] || '',
      },
      timestamp: parseInt(parts[5] || '0', 10) * 1000,
      isEmpty: parts[6] === 'true',
      hasConflicts: parts[7] === 'true',
      parentChangeIds: [],
    };
  });
}

function parseDiffSummary(output: string): ChangeFile[] {
  if (!output.trim()) return [];

  const lines = output.trim().split('\n').filter(Boolean);

  return lines.map(line => {
    const changeCode = line[0];
    const path = line.substring(2).trim();

    let status: 'added' | 'modified' | 'deleted' | 'renamed';
    switch (changeCode) {
      case 'A': status = 'added'; break;
      case 'D': status = 'deleted'; break;
      case 'R': status = 'renamed'; break;
      default: status = 'modified'; break;
    }

    return {
      path,
      status,
      additions: 0, // Would need --stat to get these
      deletions: 0,
      isBinary: false,
      hasConflict: false,
    };
  });
}

function parseGitDiff(output: string): FileDiff[] {
  // Parse git-format diff output
  const files: FileDiff[] = [];
  const filePatches = output.split(/^diff --git/m).filter(Boolean);

  for (const patch of filePatches) {
    const lines = patch.split('\n');
    const headerMatch = lines[0]?.match(/a\/(.+) b\/(.+)/);
    if (!headerMatch) continue;

    const oldPath = headerMatch[1];
    const newPath = headerMatch[2];

    let status: 'added' | 'modified' | 'deleted' | 'renamed' = 'modified';
    if (lines.some(l => l.startsWith('new file'))) status = 'added';
    if (lines.some(l => l.startsWith('deleted file'))) status = 'deleted';
    if (lines.some(l => l.startsWith('rename'))) status = 'renamed';

    const isBinary = lines.some(l => l.includes('Binary files'));

    let additions = 0;
    let deletions = 0;
    const hunks: DiffHunk[] = [];

    if (!isBinary) {
      let currentHunk: DiffHunk | null = null;
      let hunkContent: string[] = [];

      for (const line of lines) {
        // Parse hunk header: @@ -oldStart,oldLines +newStart,newLines @@
        const hunkHeaderMatch = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
        if (hunkHeaderMatch) {
          // Save previous hunk if exists
          if (currentHunk) {
            currentHunk.content = hunkContent.join('\n');
            hunks.push(currentHunk);
          }

          // Start new hunk
          currentHunk = {
            oldStart: parseInt(hunkHeaderMatch[1] || '0', 10),
            oldLines: parseInt(hunkHeaderMatch[2] || '1', 10),
            newStart: parseInt(hunkHeaderMatch[3] || '0', 10),
            newLines: parseInt(hunkHeaderMatch[4] || '1', 10),
            content: '',
          };
          hunkContent = [line];
          continue;
        }

        if (currentHunk) {
          hunkContent.push(line);
          if (line.startsWith('+') && !line.startsWith('+++')) additions++;
          if (line.startsWith('-') && !line.startsWith('---')) deletions++;
        }
      }

      // Save last hunk
      if (currentHunk) {
        currentHunk.content = hunkContent.join('\n');
        hunks.push(currentHunk);
      }
    }

    files.push({
      path: newPath || oldPath || '',
      oldPath: status === 'renamed' ? oldPath : undefined,
      status,
      additions,
      deletions,
      isBinary,
      hunks,
      hasConflict: false,
    });
  }

  return files;
}

function parseOperationType(description: string): Operation['type'] {
  const lower = description.toLowerCase();
  if (lower.includes('snapshot')) return 'snapshot';
  if (lower.includes('commit')) return 'commit';
  if (lower.includes('describe')) return 'describe';
  if (lower.includes('new')) return 'new';
  if (lower.includes('edit')) return 'edit';
  if (lower.includes('abandon')) return 'abandon';
  if (lower.includes('restore')) return 'restore';
  if (lower.includes('rebase')) return 'rebase';
  if (lower.includes('squash')) return 'squash';
  if (lower.includes('split')) return 'split';
  if (lower.includes('bookmark') || lower.includes('branch')) return 'bookmark';
  if (lower.includes('undo')) return 'undo';
  return 'snapshot';
}

// =============================================================================
// Git Compatibility Helpers
// =============================================================================

/**
 * Get clone URL for a repository (SSH format)
 */
export function getCloneUrl(user: string, name: string): string {
  const host = process.env.SSH_HOST || 'localhost';
  const port = process.env.SSH_PORT || '2222';

  // Use standard git@host:path format for port 22, otherwise use ssh:// URL
  if (port === '22') {
    return `git@${host}:${user}/${name}.git`;
  }
  return `ssh://git@${host}:${port}/${user}/${name}.git`;
}

/**
 * Sync jj state with git (for bare repo compatibility)
 */
export async function syncWithGit(user: string, name: string): Promise<void> {
  const repoPath = getRepoPath(user, name);

  // Export jj state to git
  await runJj(['git', 'export'], repoPath);
}
