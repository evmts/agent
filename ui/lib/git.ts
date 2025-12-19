import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import type { TreeEntry, Commit, CompareInfo, DiffFile, MergeStyle } from "./types";

const execAsync = promisify(exec);

const REPOS_DIR = `${process.cwd()}/repos`;

async function run(cmd: string, cwd?: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { cwd });
    return stdout;
  } catch (error: unknown) {
    // Return empty string on error (e.g., empty repo)
    return (error as { stdout?: string })?.stdout || "";
  }
}

export async function initRepo(user: string, name: string): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const tempDir = `/tmp/plue-init-${Date.now()}`;

  await mkdir(repoPath, { recursive: true });
  await run(`git init --bare "${repoPath}"`);

  // Create initial commit with README
  await mkdir(tempDir, { recursive: true });
  await run(`git init`, tempDir);
  await run(`git config user.email "plue@local"`, tempDir);
  await run(`git config user.name "Plue"`, tempDir);
  await writeFile(`${tempDir}/README.md`, `# ${name}\n\nA new repository.`);
  await run(`git add .`, tempDir);
  await run(`git commit -m "Initial commit"`, tempDir);
  await run(`git branch -M main`, tempDir);
  await run(`git remote add origin "${repoPath}"`, tempDir);
  await run(`git push -u origin main`, tempDir);
  await rm(tempDir, { recursive: true });
}

export async function deleteRepo(user: string, name: string): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  await rm(repoPath, { recursive: true });
}

export function getCloneUrl(user: string, name: string): string {
  return `file://${REPOS_DIR}/${user}/${name}`;
}

export async function listBranches(user: string, name: string): Promise<string[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    // Use git for-each-ref for bare repositories
    const result = await run(`git for-each-ref --format="%(refname:short)" refs/heads/`, repoPath);
    return result
      .trim()
      .split("\n")
      .filter(Boolean);
  } catch {
    return ["main"];
  }
}

export async function getTree(
  user: string,
  name: string,
  ref: string,
  path: string = ""
): Promise<TreeEntry[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const target = path ? `${ref}:${path}` : ref;
    const result = await run(`git ls-tree "${target}"`, repoPath);
    return parseGitLsTree(result);
  } catch {
    return [];
  }
}

export async function getFileContent(
  user: string,
  name: string,
  ref: string,
  path: string
): Promise<string | null> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const result = await run(`git show "${ref}:${path}"`, repoPath);
    return result;
  } catch {
    return null;
  }
}

export async function getCommits(
  user: string,
  name: string,
  ref: string,
  limit: number = 20
): Promise<Commit[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const format = "%H|%h|%an|%ae|%at|%s";
    const result = await run(`git log "${ref}" --format="${format}" -n ${limit}`, repoPath);
    return parseGitLog(result);
  } catch {
    return [];
  }
}

export async function repoExists(user: string, name: string): Promise<boolean> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  return existsSync(`${repoPath}/HEAD`);
}

/**
 * Compare two refs and generate diff information
 */
export async function compareRefs(
  user: string,
  name: string,
  baseRef: string,
  headRef: string
): Promise<CompareInfo> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  // Get merge base
  const mergeBase = await run(
    `git merge-base "${baseRef}" "${headRef}"`,
    repoPath
  );

  // Get commit IDs
  const baseCommitId = await run(`git rev-parse "${baseRef}"`, repoPath);
  const headCommitId = await run(`git rev-parse "${headRef}"`, repoPath);

  // Get commits between base and head (using three-dot notation)
  const commits = await getCommits(user, name, `${baseRef}...${headRef}`, 100);

  // Get diff stats
  const diffStat = await run(
    `git diff --numstat "${baseRef}...${headRef}"`,
    repoPath
  );

  const files: DiffFile[] = [];
  let totalAdditions = 0;
  let totalDeletions = 0;

  for (const line of diffStat.trim().split('\n').filter(Boolean)) {
    const [additions, deletions, filepath] = line.split('\t');

    // Check if binary
    const isBinary = additions === '-' && deletions === '-';
    const add = isBinary ? 0 : parseInt(additions, 10);
    const del = isBinary ? 0 : parseInt(deletions, 10);

    totalAdditions += add;
    totalDeletions += del;

    // Get full patch for this file
    const patch = await run(
      `git diff "${baseRef}...${headRef}" -- "${filepath}"`,
      repoPath
    );

    // Determine file status
    const status = await getFileStatus(repoPath, baseRef, headRef, filepath);

    files.push({
      name: filepath,
      status,
      additions: add,
      deletions: del,
      changes: add + del,
      patch,
      isBinary,
    });
  }

  return {
    merge_base: mergeBase.trim(),
    base_commit_id: baseCommitId.trim(),
    head_commit_id: headCommitId.trim(),
    commits,
    files,
    total_additions: totalAdditions,
    total_deletions: totalDeletions,
    total_files: files.length,
  };
}

/**
 * Check if a PR can be merged (has conflicts or not)
 */
export async function checkMergeable(
  user: string,
  name: string,
  baseBranch: string,
  headBranch: string
): Promise<{ mergeable: boolean; conflictedFiles: string[] }> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const tempDir = `/tmp/plue-merge-check-${Date.now()}`;

  try {
    // Clone to temp directory
    await mkdir(tempDir, { recursive: true });
    await run(`git clone "${repoPath}" .`, tempDir);
    await run(`git checkout "${baseBranch}"`, tempDir);

    // Attempt test merge
    try {
      await run(`git merge --no-commit --no-ff "${headBranch}"`, tempDir);
      await run(`git merge --abort`, tempDir); // Clean up
      return { mergeable: true, conflictedFiles: [] };
    } catch (error: any) {
      // Get conflicted files
      const conflictOutput = error.stdout || '';
      const conflictMatch = conflictOutput.match(/CONFLICT.*in (.+)/g);
      const conflictedFiles = conflictMatch
        ? conflictMatch.map((m: string) => m.replace(/CONFLICT.*in /, ''))
        : [];

      await run(`git merge --abort`, tempDir).catch(() => {});
      return { mergeable: false, conflictedFiles };
    }
  } catch (error) {
    console.error('Error during merge check:', error);
    return { mergeable: false, conflictedFiles: [] };
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Merge a pull request using specified strategy
 * Uses temporary clone to avoid working with bare repository
 */
export async function mergePullRequest(
  user: string,
  name: string,
  baseBranch: string,
  headBranch: string,
  style: MergeStyle,
  message: string,
  authorName: string,
  authorEmail: string
): Promise<string> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const tempDir = `/tmp/plue-merge-${Date.now()}`;

  try {
    // Clone to temp directory
    await mkdir(tempDir, { recursive: true });
    await run(`git clone "${repoPath}" .`, tempDir);
    await run(`git config user.name "${authorName}"`, tempDir);
    await run(`git config user.email "${authorEmail}"`, tempDir);
    await run(`git checkout "${baseBranch}"`, tempDir);

    let mergeCommitId: string;

    switch (style) {
      case 'merge':
        // Standard merge commit (--no-ff ensures merge commit)
        await run(`git merge --no-ff -m "${message}" "${headBranch}"`, tempDir);
        mergeCommitId = await run(`git rev-parse HEAD`, tempDir);
        break;

      case 'squash':
        // Squash all commits into one
        await run(`git merge --squash "${headBranch}"`, tempDir);
        await run(`git commit -m "${message}"`, tempDir);
        mergeCommitId = await run(`git rev-parse HEAD`, tempDir);
        break;

      case 'rebase':
        // Rebase and fast-forward
        await run(`git rebase "${headBranch}"`, tempDir);
        mergeCommitId = await run(`git rev-parse HEAD`, tempDir);
        break;

      default:
        throw new Error(`Unknown merge style: ${style}`);
    }

    // Push changes back to bare repo
    await run(`git push origin "${baseBranch}"`, tempDir);

    return mergeCommitId.trim();
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

async function getFileStatus(
  repoPath: string,
  baseRef: string,
  headRef: string,
  filepath: string
): Promise<'added' | 'modified' | 'deleted' | 'renamed'> {
  // Check if file exists in base
  const existsInBase = await run(
    `git cat-file -e "${baseRef}:${filepath}" 2>&1 || echo "missing"`,
    repoPath
  );

  // Check if file exists in head
  const existsInHead = await run(
    `git cat-file -e "${headRef}:${filepath}" 2>&1 || echo "missing"`,
    repoPath
  );

  if (existsInBase.includes('missing') && !existsInHead.includes('missing')) {
    return 'added';
  }
  if (!existsInBase.includes('missing') && existsInHead.includes('missing')) {
    return 'deleted';
  }

  // Check for renames
  const diffNameStatus = await run(
    `git diff --name-status "${baseRef}...${headRef}" -- "${filepath}"`,
    repoPath
  );

  if (diffNameStatus.startsWith('R')) return 'renamed';
  return 'modified';
}

function parseGitLsTree(output: string): TreeEntry[] {
  return output
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(line => {
      const match = line.match(/^(\d+)\s+(blob|tree)\s+([a-f0-9]+)\t(.+)$/);
      if (!match) return null;
      const [, mode, type, hash, name] = match;
      return { mode, type: type as "blob" | "tree", hash, name };
    })
    .filter((entry): entry is TreeEntry => entry !== null);
}

function parseGitLog(output: string): Commit[] {
  return output
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(line => {
      const parts = line.split("|");
      return {
        hash: parts[0] ?? '',
        shortHash: parts[1] ?? '',
        authorName: parts[2] ?? '',
        authorEmail: parts[3] ?? '',
        timestamp: parseInt(parts[4] ?? '0', 10) * 1000,
        message: parts.slice(5).join("|"),
      };
    });
}