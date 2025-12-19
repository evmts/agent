# Code Navigation Implementation

## Overview

Implement comprehensive code navigation features for Plue repositories, enabling users to explore code history, understand authorship, visualize commit relationships, and compare different versions.

**Scope:**
- Blame view (line-by-line commit attribution)
- Git graph visualization (commit history graph with branches)
- Commit comparison (diff between two commits)
- File history (all commits that touched a file)
- Permalink support (link to specific lines and commits)
- Breadcrumb navigation for all views
- Integration with existing file viewer

**Out of scope (future features):**
- Advanced graph filtering (by author, date range)
- Interactive graph manipulation (cherry-pick, rebase UI)
- Code ownership statistics
- Heat maps of code activity
- Blame ignore revisions UI management

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL
- **Git Operations**: Direct git commands via `exec` (like existing `ui/lib/git.ts`)

## Architecture Overview

Plue's code navigation extends the existing file viewing system with:
1. Git blame for line-level commit attribution
2. Git log with graph for commit visualization
3. Git diff for commit comparison
4. Git log with file path for file history
5. URL anchors for line permalinks

## Database Schema Changes

No database schema changes required. All navigation data comes from git commands.

## Backend Implementation

### 1. Git Operations Library Enhancement

**File**: `/Users/williamcory/plue/ui/lib/git.ts`

Add new functions to existing git library:

```typescript
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);
const REPOS_DIR = `${process.cwd()}/repos`;

/**
 * Blame data for a single line
 */
export interface BlameLine {
  lineNumber: number;
  commitHash: string;
  commitShortHash: string;
  authorName: string;
  authorEmail: string;
  authorTime: number;
  commitMessage: string;
  code: string;
  previousCommitHash?: string;
  previousFilePath?: string;
}

/**
 * Get git blame for a file
 * Returns line-by-line commit attribution
 */
export async function getFileBlame(
  user: string,
  name: string,
  ref: string,
  path: string
): Promise<BlameLine[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  try {
    // Use porcelain format for easier parsing
    const { stdout } = await execAsync(
      `git blame --porcelain "${ref}" -- "${path}"`,
      { cwd: repoPath, maxBuffer: 50 * 1024 * 1024 } // 50MB max
    );

    return parseGitBlame(stdout);
  } catch (error: any) {
    console.error('Blame error:', error);
    return [];
  }
}

/**
 * Parse git blame --porcelain output
 */
function parseGitBlame(output: string): BlameLine[] {
  const lines: BlameLine[] = [];
  const commits: Record<string, {
    author: string;
    authorEmail: string;
    authorTime: number;
    summary: string;
    previous?: { hash: string; path: string };
  }> = {};

  const blameLines = output.split('\n');
  let currentHash = '';
  let lineNumber = 0;

  for (let i = 0; i < blameLines.length; i++) {
    const line = blameLines[i];

    // Line starting with hash (40 or 64 chars)
    if (/^[0-9a-f]{40,64} /.test(line)) {
      const parts = line.split(' ');
      currentHash = parts[0];
      lineNumber = parseInt(parts[2], 10);

      // Initialize commit data if not seen before
      if (!commits[currentHash]) {
        commits[currentHash] = {
          author: '',
          authorEmail: '',
          authorTime: 0,
          summary: '',
        };
      }
    } else if (line.startsWith('author ')) {
      commits[currentHash].author = line.substring(7);
    } else if (line.startsWith('author-mail ')) {
      commits[currentHash].authorEmail = line.substring(12).replace(/[<>]/g, '');
    } else if (line.startsWith('author-time ')) {
      commits[currentHash].authorTime = parseInt(line.substring(12), 10) * 1000;
    } else if (line.startsWith('summary ')) {
      commits[currentHash].summary = line.substring(8);
    } else if (line.startsWith('previous ')) {
      const parts = line.substring(9).split(' ');
      commits[currentHash].previous = {
        hash: parts[0],
        path: parts[1] || '',
      };
    } else if (line.startsWith('\t')) {
      // This is the actual code line
      const commit = commits[currentHash];
      lines.push({
        lineNumber,
        commitHash: currentHash,
        commitShortHash: currentHash.substring(0, 7),
        authorName: commit.author,
        authorEmail: commit.authorEmail,
        authorTime: commit.authorTime,
        commitMessage: commit.summary,
        code: line.substring(1), // Remove leading tab
        previousCommitHash: commit.previous?.hash,
        previousFilePath: commit.previous?.path,
      });
    }
  }

  return lines;
}

/**
 * Graph commit data
 */
export interface GraphCommit {
  hash: string;
  shortHash: string;
  authorName: string;
  authorEmail: string;
  timestamp: number;
  message: string;
  parents: string[];
  refs: string[]; // Branch/tag names
  graph: string; // ASCII graph characters
}

/**
 * Get commit graph for repository
 * Returns commits with graph visualization data
 */
export async function getCommitGraph(
  user: string,
  name: string,
  options: {
    ref?: string;
    limit?: number;
    skip?: number;
    hidePRRefs?: boolean;
    branches?: string[];
    filePath?: string;
  } = {}
): Promise<GraphCommit[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const limit = options.limit || 50;
  const skip = options.skip || 0;

  // Build git log command
  const format = 'COMMIT:%H|%h|%an|%ae|%at|%s|%P|%D';
  let cmd = `git log --graph --date-order --decorate=full --pretty=format:"${format}"`;

  if (options.hidePRRefs) {
    cmd += ' --exclude="refs/pull/*"';
  }

  if (options.branches && options.branches.length > 0) {
    cmd += ` ${options.branches.join(' ')}`;
  } else {
    cmd += ' --all';
  }

  cmd += ` -n ${limit + skip}`;

  if (options.filePath) {
    cmd += ` -- "${options.filePath}"`;
  }

  try {
    const { stdout } = await execAsync(cmd, {
      cwd: repoPath,
      maxBuffer: 100 * 1024 * 1024 // 100MB max
    });

    const commits = parseGitGraph(stdout);
    return commits.slice(skip);
  } catch (error: any) {
    console.error('Graph error:', error);
    return [];
  }
}

/**
 * Parse git log --graph output
 */
function parseGitGraph(output: string): GraphCommit[] {
  const commits: GraphCommit[] = [];
  const lines = output.split('\n');

  for (const line of lines) {
    const commitIndex = line.indexOf('COMMIT:');
    if (commitIndex === -1) continue;

    const graph = line.substring(0, commitIndex);
    const data = line.substring(commitIndex + 7); // Skip 'COMMIT:'
    const parts = data.split('|');

    if (parts.length < 7) continue;

    const parents = parts[6] ? parts[6].trim().split(' ') : [];
    const refs = parts[7] ? parseRefs(parts[7]) : [];

    commits.push({
      hash: parts[0],
      shortHash: parts[1],
      authorName: parts[2],
      authorEmail: parts[3],
      timestamp: parseInt(parts[4], 10) * 1000,
      message: parts[5],
      parents,
      refs,
      graph: graph.replace(/\*/g, '●'), // Replace * with filled circle for better visuals
    });
  }

  return commits;
}

/**
 * Parse git refs from decoration string
 */
function parseRefs(decoration: string): string[] {
  // decoration format: "HEAD -> main, origin/main, tag: v1.0"
  const refs: string[] = [];
  const parts = decoration.trim().split(',');

  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.startsWith('HEAD ->')) {
      refs.push(trimmed.substring(7).trim());
    } else if (trimmed.startsWith('tag:')) {
      refs.push(trimmed.substring(4).trim());
    } else if (trimmed && !trimmed.includes('->')) {
      refs.push(trimmed);
    }
  }

  return refs;
}

/**
 * Get file history (commits that modified a file)
 */
export async function getFileHistory(
  user: string,
  name: string,
  ref: string,
  path: string,
  limit: number = 50
): Promise<Commit[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  try {
    const format = "%H|%h|%an|%ae|%at|%s";
    const { stdout } = await execAsync(
      `git log "${ref}" --format="${format}" -n ${limit} -- "${path}"`,
      { cwd: repoPath }
    );

    return parseGitLog(stdout);
  } catch (error) {
    console.error('File history error:', error);
    return [];
  }
}

/**
 * Compare two commits
 * Returns diff information
 */
export interface CommitComparison {
  baseCommit: Commit;
  headCommit: Commit;
  diffStat: {
    filesChanged: number;
    insertions: number;
    deletions: number;
  };
  files: Array<{
    path: string;
    status: 'added' | 'modified' | 'deleted' | 'renamed';
    oldPath?: string;
    additions: number;
    deletions: number;
    patch: string;
  }>;
}

/**
 * Get comparison between two commits
 */
export async function compareCommits(
  user: string,
  name: string,
  baseRef: string,
  headRef: string
): Promise<CommitComparison | null> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  try {
    // Get commit info
    const format = "%H|%h|%an|%ae|%at|%s";
    const { stdout: baseInfo } = await execAsync(
      `git log -1 "${baseRef}" --format="${format}"`,
      { cwd: repoPath }
    );
    const { stdout: headInfo } = await execAsync(
      `git log -1 "${headRef}" --format="${format}"`,
      { cwd: repoPath }
    );

    const [baseCommit] = parseGitLog(baseInfo);
    const [headCommit] = parseGitLog(headInfo);

    if (!baseCommit || !headCommit) return null;

    // Get diff stat
    const { stdout: statOutput } = await execAsync(
      `git diff --numstat "${baseRef}...${headRef}"`,
      { cwd: repoPath }
    );

    const diffStat = parseDiffStat(statOutput);

    // Get full diff
    const { stdout: diffOutput } = await execAsync(
      `git diff "${baseRef}...${headRef}"`,
      { cwd: repoPath, maxBuffer: 50 * 1024 * 1024 }
    );

    const files = parseDiff(diffOutput);

    return {
      baseCommit,
      headCommit,
      diffStat,
      files,
    };
  } catch (error) {
    console.error('Compare commits error:', error);
    return null;
  }
}

/**
 * Parse diff --numstat output
 */
function parseDiffStat(output: string): {
  filesChanged: number;
  insertions: number;
  deletions: number;
} {
  const lines = output.trim().split('\n').filter(Boolean);
  let insertions = 0;
  let deletions = 0;

  for (const line of lines) {
    const parts = line.split('\t');
    insertions += parseInt(parts[0], 10) || 0;
    deletions += parseInt(parts[1], 10) || 0;
  }

  return {
    filesChanged: lines.length,
    insertions,
    deletions,
  };
}

/**
 * Parse git diff output into file changes
 */
function parseDiff(output: string): Array<{
  path: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  oldPath?: string;
  additions: number;
  deletions: number;
  patch: string;
}> {
  const files: Array<any> = [];
  const fileDiffs = output.split('diff --git ').slice(1);

  for (const fileDiff of fileDiffs) {
    const lines = fileDiff.split('\n');
    const headerLine = lines[0];

    // Parse file paths from "a/path b/path"
    const match = headerLine.match(/a\/(.+?) b\/(.+)/);
    if (!match) continue;

    const oldPath = match[1];
    const newPath = match[2];

    let status: 'added' | 'modified' | 'deleted' | 'renamed' = 'modified';
    if (oldPath === '/dev/null') status = 'added';
    else if (newPath === '/dev/null') status = 'deleted';
    else if (oldPath !== newPath) status = 'renamed';

    let additions = 0;
    let deletions = 0;

    for (const line of lines) {
      if (line.startsWith('+') && !line.startsWith('+++')) additions++;
      if (line.startsWith('-') && !line.startsWith('---')) deletions++;
    }

    files.push({
      path: status === 'deleted' ? oldPath : newPath,
      status,
      oldPath: status === 'renamed' ? oldPath : undefined,
      additions,
      deletions,
      patch: fileDiff,
    });
  }

  return files;
}

/**
 * Get commit count for a ref
 */
export async function getCommitCount(
  user: string,
  name: string,
  ref: string
): Promise<number> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  try {
    const { stdout } = await execAsync(
      `git rev-list --count "${ref}"`,
      { cwd: repoPath }
    );
    return parseInt(stdout.trim(), 10);
  } catch {
    return 0;
  }
}

/**
 * Check if a commit exists in repository
 */
export async function commitExists(
  user: string,
  name: string,
  commitHash: string
): Promise<boolean> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  try {
    await execAsync(`git cat-file -e "${commitHash}^{commit}"`, { cwd: repoPath });
    return true;
  } catch {
    return false;
  }
}
```

### 2. API Routes

**File**: `/Users/williamcory/plue/server/routes/code-nav.ts` (new file)

```typescript
import { Hono } from 'hono';
import {
  getFileBlame,
  getCommitGraph,
  getFileHistory,
  compareCommits,
  getCommitCount,
  repoExists,
  commitExists,
} from '../../ui/lib/git';

const app = new Hono();

// Get blame data for a file
app.get('/:user/:repo/blame/:ref/*', async (c) => {
  const { user, repo, ref } = c.req.param();
  const filePath = c.req.param('*');

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const blame = await getFileBlame(user, repo, ref, filePath);
    return c.json({ blame });
  } catch (error: any) {
    console.error('Blame error:', error);
    return c.json({ error: 'Failed to get blame data' }, 500);
  }
});

// Get commit graph
app.get('/:user/:repo/graph', async (c) => {
  const { user, repo } = c.req.param();
  const ref = c.req.query('ref');
  const limit = parseInt(c.req.query('limit') || '50', 10);
  const skip = parseInt(c.req.query('skip') || '0', 10);
  const hidePRRefs = c.req.query('hide_pr_refs') === 'true';
  const branches = c.req.query('branches')?.split(',').filter(Boolean);
  const filePath = c.req.query('file');

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const commits = await getCommitGraph(user, repo, {
      ref,
      limit,
      skip,
      hidePRRefs,
      branches,
      filePath,
    });

    const total = await getCommitCount(user, repo, ref || 'HEAD');

    return c.json({ commits, total });
  } catch (error: any) {
    console.error('Graph error:', error);
    return c.json({ error: 'Failed to get commit graph' }, 500);
  }
});

// Get file history
app.get('/:user/:repo/history/:ref/*', async (c) => {
  const { user, repo, ref } = c.req.param();
  const filePath = c.req.param('*');
  const limit = parseInt(c.req.query('limit') || '50', 10);

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const commits = await getFileHistory(user, repo, ref, filePath, limit);
    return c.json({ commits, filePath });
  } catch (error: any) {
    console.error('File history error:', error);
    return c.json({ error: 'Failed to get file history' }, 500);
  }
});

// Compare two commits
app.get('/:user/:repo/compare/:base...:head', async (c) => {
  const { user, repo, base, head } = c.req.param();

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const comparison = await compareCommits(user, repo, base, head);

    if (!comparison) {
      return c.json({ error: 'Invalid commit references' }, 400);
    }

    return c.json(comparison);
  } catch (error: any) {
    console.error('Compare error:', error);
    return c.json({ error: 'Failed to compare commits' }, 500);
  }
});

export default app;
```

**File**: `/Users/williamcory/plue/server/index.ts`

Register the code navigation routes:

```typescript
import codeNav from './routes/code-nav';

// ... existing code ...

app.route('/api/code-nav', codeNav);
```

## Frontend Implementation

### 1. Blame View Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/blame/[...path].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { getFileBlame, repoExists } from "../../../../lib/git";
import type { User, Repository, BlameLine } from "../../../../lib/types";

const { user: username, repo: reponame, path: pathParam } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const pathParts = pathParam?.split("/") || [];
const branch = pathParts[0] || repo.default_branch || "main";
const filePath = pathParts.slice(1).join("/");
const filename = pathParts[pathParts.length - 1] || "";

if (!filePath) return Astro.redirect("/404");

const blameData = await getFileBlame(username!, reponame!, branch, filePath);

if (!blameData || blameData.length === 0) {
  return Astro.redirect("/404");
}

// Group blame lines by commit for visual grouping
const blameGroups: Array<{ commit: string; lines: BlameLine[] }> = [];
let currentGroup: BlameLine[] = [];
let currentCommit = '';

for (const line of blameData) {
  if (line.commitHash !== currentCommit) {
    if (currentGroup.length > 0) {
      blameGroups.push({ commit: currentCommit, lines: currentGroup });
    }
    currentCommit = line.commitHash;
    currentGroup = [line];
  } else {
    currentGroup.push(line);
  }
}
if (currentGroup.length > 0) {
  blameGroups.push({ commit: currentCommit, lines: currentGroup });
}

const breadcrumbParts = filePath ? filePath.split("/") : [];

function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  const now = Date.now();
  const diff = now - timestamp;

  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return `${Math.floor(diff / (60 * 1000))} minutes ago`;
  if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))} hours ago`;
  if (diff < 30 * 24 * 60 * 60 * 1000) return `${Math.floor(diff / (24 * 60 * 60 * 1000))} days ago`;

  return date.toLocaleDateString();
}
---

<Layout title={`Blame: ${filename} · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/tree/${branch}`}>tree</a>
    <span class="sep">/</span>
    <span>blame</span>
    {breadcrumbParts.map((part, i) => {
      const partPath = breadcrumbParts.slice(0, i + 1).join("/");
      const isLast = i === breadcrumbParts.length - 1;
      return (
        <>
          <span class="sep">/</span>
          {isLast ? (
            <span class="current">{part}</span>
          ) : (
            <a href={`/${username}/${reponame}/blame/${branch}/${partPath}`}>{part}</a>
          )}
        </>
      );
    })}
  </div>

  <nav class="file-nav">
    <a href={`/${username}/${reponame}/blob/${branch}/${filePath}`}>View</a>
    <a href={`/${username}/${reponame}/blame/${branch}/${filePath}`} class="active">Blame</a>
    <a href={`/${username}/${reponame}/commits/${branch}/${filePath}`}>History</a>
    <a href={`/api/files/${username}/${reponame}/raw/${branch}/${filePath}`}>Raw</a>
  </nav>

  <div class="container">
    <div class="blame-view">
      {blameGroups.map((group) => {
        const firstLine = group.lines[0];
        return (
          <div class="blame-group">
            {group.lines.map((line, idx) => (
              <div class="blame-line" id={`L${line.lineNumber}`}>
                <div class="blame-commit">
                  {idx === 0 ? (
                    <>
                      <a href={`/${username}/${reponame}/commit/${line.commitHash}`} class="commit-hash">
                        {line.commitShortHash}
                      </a>
                      <div class="commit-info">
                        <div class="commit-author">{line.authorName}</div>
                        <div class="commit-time">{formatDate(line.authorTime)}</div>
                      </div>
                      <div class="commit-message" title={line.commitMessage}>
                        {line.commitMessage}
                      </div>
                    </>
                  ) : (
                    <div class="blame-continuation"></div>
                  )}
                </div>
                <div class="line-number">
                  <a href={`#L${line.lineNumber}`}>{line.lineNumber}</a>
                </div>
                <div class="code-content">
                  <pre>{line.code}</pre>
                </div>
              </div>
            ))}
          </div>
        );
      })}
    </div>
  </div>

  <style>
    .file-nav {
      display: flex;
      gap: 1rem;
      padding: 1rem;
      border-bottom: 2px solid #000;
      background: #f9f9f9;
    }

    .file-nav a {
      padding: 0.5rem 1rem;
      text-decoration: none;
      color: #000;
      border: 2px solid transparent;
    }

    .file-nav a.active {
      border: 2px solid #000;
      background: #fff;
      font-weight: bold;
    }

    .file-nav a:hover:not(.active) {
      border-color: #666;
    }

    .blame-view {
      border: 2px solid #000;
      background: #fff;
      overflow-x: auto;
    }

    .blame-group {
      border-bottom: 1px solid #e0e0e0;
    }

    .blame-line {
      display: grid;
      grid-template-columns: 400px 50px 1fr;
      min-height: 20px;
      font-size: 13px;
      line-height: 20px;
    }

    .blame-line:hover {
      background: #f5f5f5;
    }

    .blame-commit {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0 0.5rem;
      border-right: 1px solid #ddd;
      background: #fafafa;
      overflow: hidden;
    }

    .commit-hash {
      font-family: monospace;
      font-weight: bold;
      text-decoration: none;
      color: #0066cc;
      white-space: nowrap;
    }

    .commit-hash:hover {
      text-decoration: underline;
    }

    .commit-info {
      display: flex;
      flex-direction: column;
      min-width: 120px;
    }

    .commit-author {
      font-weight: 500;
      font-size: 12px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .commit-time {
      font-size: 11px;
      color: #666;
    }

    .commit-message {
      flex: 1;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      color: #333;
      font-size: 12px;
    }

    .blame-continuation {
      height: 100%;
      background: #f0f0f0;
    }

    .line-number {
      text-align: right;
      padding: 0 0.5rem;
      color: #666;
      background: #fafafa;
      border-right: 1px solid #ddd;
      user-select: none;
    }

    .line-number a {
      text-decoration: none;
      color: inherit;
    }

    .line-number a:hover {
      text-decoration: underline;
    }

    .code-content {
      padding: 0 0.5rem;
      overflow-x: auto;
    }

    .code-content pre {
      margin: 0;
      font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
      font-size: 13px;
      white-space: pre;
      tab-size: 4;
    }

    @media (max-width: 768px) {
      .blame-line {
        grid-template-columns: 200px 40px 1fr;
      }

      .commit-info {
        display: none;
      }

      .commit-message {
        display: none;
      }
    }
  </style>
</Layout>
```

### 2. Git Graph Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/graph/[...ref].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { getCommitGraph, listBranches } from "../../../../lib/git";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame, ref: refParam } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const ref = refParam || repo.default_branch || "main";
const page = parseInt(Astro.url.searchParams.get('page') || '1', 10);
const limit = 50;
const skip = (page - 1) * limit;

const commits = await getCommitGraph(username!, reponame!, {
  ref,
  limit,
  skip,
});

const branches = await listBranches(username!, reponame!);

function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleString();
}
---

<Layout title={`Graph · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span>graph</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/commits/${ref}`}>Commits</a>
    <a href={`/${username}/${reponame}/graph/${ref}`} class="active">Graph</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
  </nav>

  <div class="container">
    <div class="graph-controls">
      <select id="branch-select" onchange="window.location.href = `/${username}/${reponame}/graph/${this.value}`">
        {branches.map(branch => (
          <option value={branch} selected={branch === ref}>{branch}</option>
        ))}
      </select>
    </div>

    <div class="graph-view">
      {commits.map((commit) => (
        <div class="graph-commit">
          <div class="graph-visual">
            <pre>{commit.graph}</pre>
          </div>
          <div class="commit-details">
            <div class="commit-header">
              <a href={`/${username}/${reponame}/commit/${commit.hash}`} class="commit-hash">
                {commit.shortHash}
              </a>
              {commit.refs.length > 0 && (
                <div class="commit-refs">
                  {commit.refs.map(ref => (
                    <span class="ref-label">{ref}</span>
                  ))}
                </div>
              )}
              <span class="commit-author">{commit.authorName}</span>
              <span class="commit-time">{formatDate(commit.timestamp)}</span>
            </div>
            <div class="commit-message">{commit.message}</div>
          </div>
        </div>
      ))}
    </div>

    <div class="pagination">
      {page > 1 && (
        <a href={`?page=${page - 1}`} class="page-link">Previous</a>
      )}
      <span class="page-info">Page {page}</span>
      {commits.length === limit && (
        <a href={`?page=${page + 1}`} class="page-link">Next</a>
      )}
    </div>
  </div>

  <style>
    .graph-controls {
      padding: 1rem;
      border: 2px solid #000;
      background: #f9f9f9;
      margin-bottom: 1rem;
    }

    .graph-controls select {
      padding: 0.5rem;
      border: 2px solid #000;
      font-size: 14px;
    }

    .graph-view {
      border: 2px solid #000;
      background: #fff;
    }

    .graph-commit {
      display: grid;
      grid-template-columns: 150px 1fr;
      padding: 0.5rem;
      border-bottom: 1px solid #e0e0e0;
    }

    .graph-commit:hover {
      background: #f5f5f5;
    }

    .graph-visual {
      font-family: monospace;
      color: #666;
    }

    .graph-visual pre {
      margin: 0;
      font-size: 14px;
      line-height: 1.5;
    }

    .commit-details {
      display: flex;
      flex-direction: column;
      gap: 0.25rem;
    }

    .commit-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 13px;
    }

    .commit-hash {
      font-family: monospace;
      font-weight: bold;
      text-decoration: none;
      color: #0066cc;
    }

    .commit-hash:hover {
      text-decoration: underline;
    }

    .commit-refs {
      display: flex;
      gap: 0.25rem;
    }

    .ref-label {
      padding: 0.125rem 0.5rem;
      background: #e0f2ff;
      border: 1px solid #0066cc;
      border-radius: 3px;
      font-size: 11px;
      font-weight: 500;
    }

    .commit-author {
      color: #333;
      font-weight: 500;
    }

    .commit-time {
      color: #666;
      margin-left: auto;
    }

    .commit-message {
      color: #000;
      font-size: 14px;
    }

    .pagination {
      display: flex;
      justify-content: center;
      align-items: center;
      gap: 1rem;
      padding: 1rem;
      margin-top: 1rem;
    }

    .page-link {
      padding: 0.5rem 1rem;
      border: 2px solid #000;
      background: #fff;
      text-decoration: none;
      color: #000;
      font-weight: bold;
    }

    .page-link:hover {
      background: #000;
      color: #fff;
    }

    .page-info {
      font-weight: bold;
    }
  </style>
</Layout>
```

### 3. Commit Comparison Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/compare/[...refs].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { compareCommits } from "../../../../lib/git";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame, refs: refsParam } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Parse "base...head" format
const parts = refsParam?.split('...') || [];
if (parts.length !== 2) {
  return Astro.redirect(`/${username}/${reponame}`);
}

const [baseRef, headRef] = parts;
const comparison = await compareCommits(username!, reponame!, baseRef, headRef);

if (!comparison) {
  return Astro.redirect("/404");
}

function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleString();
}
---

<Layout title={`Compare ${baseRef}...${headRef} · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span>compare</span>
  </div>

  <div class="container">
    <div class="compare-header">
      <h2>Comparing changes</h2>
      <div class="compare-refs">
        <a href={`/${username}/${reponame}/commit/${comparison.baseCommit.hash}`} class="ref">
          {baseRef}
        </a>
        <span class="sep">...</span>
        <a href={`/${username}/${reponame}/commit/${comparison.headCommit.hash}`} class="ref">
          {headRef}
        </a>
      </div>
    </div>

    <div class="diff-stats">
      <div class="stat">
        <strong>{comparison.diffStat.filesChanged}</strong> files changed
      </div>
      <div class="stat additions">
        <strong>{comparison.diffStat.insertions}</strong> additions
      </div>
      <div class="stat deletions">
        <strong>{comparison.diffStat.deletions}</strong> deletions
      </div>
    </div>

    <div class="commits-summary">
      <h3>Commits</h3>
      <div class="commit-item">
        <div class="commit-header">
          <a href={`/${username}/${reponame}/commit/${comparison.headCommit.hash}`}>
            {comparison.headCommit.shortHash}
          </a>
          <span class="author">{comparison.headCommit.authorName}</span>
          <span class="time">{formatDate(comparison.headCommit.timestamp)}</span>
        </div>
        <div class="commit-message">{comparison.headCommit.message}</div>
      </div>
    </div>

    <div class="files-changed">
      <h3>Files Changed ({comparison.files.length})</h3>
      {comparison.files.map((file) => (
        <div class="file-diff">
          <div class="file-header">
            <span class={`status status-${file.status}`}>{file.status}</span>
            <span class="file-path">{file.path}</span>
            {file.oldPath && file.oldPath !== file.path && (
              <span class="old-path">← {file.oldPath}</span>
            )}
            <span class="diff-stats">
              <span class="additions">+{file.additions}</span>
              <span class="deletions">-{file.deletions}</span>
            </span>
          </div>
          <div class="file-patch">
            <pre>{file.patch}</pre>
          </div>
        </div>
      ))}
    </div>
  </div>

  <style>
    .compare-header {
      padding: 2rem;
      border: 2px solid #000;
      background: #f9f9f9;
      margin-bottom: 1rem;
    }

    .compare-header h2 {
      margin: 0 0 1rem 0;
    }

    .compare-refs {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-family: monospace;
      font-size: 16px;
    }

    .compare-refs .ref {
      padding: 0.5rem 1rem;
      background: #fff;
      border: 2px solid #000;
      text-decoration: none;
      color: #000;
      font-weight: bold;
    }

    .compare-refs .ref:hover {
      background: #000;
      color: #fff;
    }

    .diff-stats {
      display: flex;
      gap: 2rem;
      padding: 1rem;
      border: 2px solid #000;
      background: #fff;
      margin-bottom: 1rem;
    }

    .stat {
      font-size: 14px;
    }

    .stat strong {
      font-size: 20px;
      margin-right: 0.25rem;
    }

    .stat.additions strong {
      color: #28a745;
    }

    .stat.deletions strong {
      color: #dc3545;
    }

    .commits-summary,
    .files-changed {
      margin-bottom: 2rem;
    }

    .commits-summary h3,
    .files-changed h3 {
      margin-bottom: 1rem;
    }

    .commit-item {
      padding: 1rem;
      border: 2px solid #000;
      background: #fff;
    }

    .commit-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 0.5rem;
      font-size: 13px;
    }

    .commit-header a {
      font-family: monospace;
      font-weight: bold;
      text-decoration: none;
      color: #0066cc;
    }

    .commit-header .author {
      font-weight: 500;
    }

    .commit-header .time {
      color: #666;
      margin-left: auto;
    }

    .commit-message {
      font-size: 14px;
      color: #333;
    }

    .file-diff {
      margin-bottom: 1rem;
      border: 2px solid #000;
      background: #fff;
    }

    .file-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.75rem;
      background: #f6f8fa;
      border-bottom: 1px solid #ddd;
      font-size: 13px;
    }

    .status {
      padding: 0.125rem 0.5rem;
      border-radius: 3px;
      font-weight: bold;
      font-size: 11px;
      text-transform: uppercase;
    }

    .status-added {
      background: #d4edda;
      color: #155724;
    }

    .status-modified {
      background: #fff3cd;
      color: #856404;
    }

    .status-deleted {
      background: #f8d7da;
      color: #721c24;
    }

    .status-renamed {
      background: #d1ecf1;
      color: #0c5460;
    }

    .file-path {
      font-family: monospace;
      font-weight: bold;
    }

    .old-path {
      color: #666;
      font-family: monospace;
      font-size: 12px;
    }

    .diff-stats {
      margin-left: auto;
      display: flex;
      gap: 0.5rem;
    }

    .diff-stats .additions {
      color: #28a745;
      font-weight: bold;
    }

    .diff-stats .deletions {
      color: #dc3545;
      font-weight: bold;
    }

    .file-patch {
      padding: 1rem;
      overflow-x: auto;
      max-height: 600px;
      overflow-y: auto;
    }

    .file-patch pre {
      margin: 0;
      font-family: monospace;
      font-size: 12px;
      line-height: 1.5;
    }
  </style>
</Layout>
```

### 4. File History Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/commits/[...path].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { getFileHistory } from "../../../../lib/git";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame, path: pathParam } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const pathParts = pathParam?.split("/") || [];
const branch = pathParts[0] || repo.default_branch || "main";
const filePath = pathParts.slice(1).join("/");

const commits = filePath
  ? await getFileHistory(username!, reponame!, branch, filePath)
  : await getCommits(username!, reponame!, branch);

const breadcrumbParts = filePath ? filePath.split("/") : [];

function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleString();
}
---

<Layout title={`History · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/tree/${branch}`}>{branch}</a>
    {filePath && (
      <>
        <span class="sep">/</span>
        <span>history</span>
        {breadcrumbParts.map((part, i) => (
          <>
            <span class="sep">/</span>
            <span class={i === breadcrumbParts.length - 1 ? "current" : ""}>{part}</span>
          </>
        ))}
      </>
    )}
  </div>

  {filePath && (
    <nav class="file-nav">
      <a href={`/${username}/${reponame}/blob/${branch}/${filePath}`}>View</a>
      <a href={`/${username}/${reponame}/blame/${branch}/${filePath}`}>Blame</a>
      <a href={`/${username}/${reponame}/commits/${branch}/${filePath}`} class="active">History</a>
      <a href={`/api/files/${username}/${reponame}/raw/${branch}/${filePath}`}>Raw</a>
    </nav>
  )}

  <div class="container">
    <h2>{filePath ? `History for ${filePath}` : 'Commit History'}</h2>

    <div class="commits-list">
      {commits.map((commit) => (
        <div class="commit-item">
          <div class="commit-header">
            <a href={`/${username}/${reponame}/commit/${commit.hash}`} class="commit-hash">
              {commit.shortHash}
            </a>
            <span class="commit-author">{commit.authorName}</span>
            <span class="commit-time">{formatDate(commit.timestamp)}</span>
          </div>
          <div class="commit-message">{commit.message}</div>
          <div class="commit-actions">
            <a href={`/${username}/${reponame}/commit/${commit.hash}`}>View commit</a>
            {filePath && (
              <>
                <a href={`/${username}/${reponame}/blob/${commit.hash}/${filePath}`}>View file @ this commit</a>
                <a href={`/${username}/${reponame}/blame/${commit.hash}/${filePath}`}>Blame @ this commit</a>
              </>
            )}
          </div>
        </div>
      ))}
    </div>
  </div>

  <style>
    .file-nav {
      display: flex;
      gap: 1rem;
      padding: 1rem;
      border-bottom: 2px solid #000;
      background: #f9f9f9;
    }

    .file-nav a {
      padding: 0.5rem 1rem;
      text-decoration: none;
      color: #000;
      border: 2px solid transparent;
    }

    .file-nav a.active {
      border: 2px solid #000;
      background: #fff;
      font-weight: bold;
    }

    .container h2 {
      margin: 2rem 0 1rem 0;
    }

    .commits-list {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }

    .commit-item {
      padding: 1rem;
      border: 2px solid #000;
      background: #fff;
    }

    .commit-item:hover {
      background: #f9f9f9;
    }

    .commit-header {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 0.5rem;
      font-size: 13px;
    }

    .commit-hash {
      font-family: monospace;
      font-weight: bold;
      text-decoration: none;
      color: #0066cc;
    }

    .commit-hash:hover {
      text-decoration: underline;
    }

    .commit-author {
      font-weight: 500;
      color: #333;
    }

    .commit-time {
      color: #666;
      margin-left: auto;
    }

    .commit-message {
      margin-bottom: 0.5rem;
      font-size: 14px;
      color: #000;
    }

    .commit-actions {
      display: flex;
      gap: 1rem;
      font-size: 12px;
    }

    .commit-actions a {
      color: #0066cc;
      text-decoration: none;
    }

    .commit-actions a:hover {
      text-decoration: underline;
    }
  </style>
</Layout>
```

### 5. Update Blob View with Permalinks

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/blob/[...path].astro`

Add line number anchors and blame/history links:

```astro
<!-- Add to file navigation -->
<nav class="file-nav">
  <a href={`/${username}/${reponame}/blob/${branch}/${filePath}`} class="active">View</a>
  <a href={`/${username}/${reponame}/blame/${branch}/${filePath}`}>Blame</a>
  <a href={`/${username}/${reponame}/commits/${branch}/${filePath}`}>History</a>
  <a href={`/api/files/${username}/${reponame}/raw/${branch}/${filePath}`}>Raw</a>
</nav>

<!-- Update FileViewer component to include line numbers with anchors -->
<div class="code-viewer">
  {content.split('\n').map((line, idx) => (
    <div class="code-line" id={`L${idx + 1}`}>
      <span class="line-number">
        <a href={`#L${idx + 1}`}>{idx + 1}</a>
      </span>
      <pre class="code-content">{line}</pre>
    </div>
  ))}
</div>

<style>
  .file-nav {
    display: flex;
    gap: 1rem;
    padding: 1rem;
    border-bottom: 2px solid #000;
    background: #f9f9f9;
  }

  .file-nav a {
    padding: 0.5rem 1rem;
    text-decoration: none;
    color: #000;
    border: 2px solid transparent;
  }

  .file-nav a.active {
    border: 2px solid #000;
    background: #fff;
    font-weight: bold;
  }

  .code-viewer {
    border: 2px solid #000;
    background: #fff;
  }

  .code-line {
    display: grid;
    grid-template-columns: 50px 1fr;
    min-height: 20px;
  }

  .code-line:target {
    background: #fffbdd;
  }

  .line-number {
    text-align: right;
    padding: 0 0.5rem;
    background: #f6f8fa;
    border-right: 1px solid #ddd;
    user-select: none;
    color: #666;
  }

  .line-number a {
    text-decoration: none;
    color: inherit;
  }

  .line-number a:hover {
    color: #0066cc;
  }

  .code-content {
    margin: 0;
    padding: 0 0.5rem;
    font-family: monospace;
    font-size: 13px;
    white-space: pre;
    tab-size: 4;
  }
</style>
```

## Implementation Checklist

### Phase 1: Backend Foundation
- [ ] Add git blame functionality to `/Users/williamcory/plue/ui/lib/git.ts`
  - [ ] `getFileBlame()` with porcelain format parsing
  - [ ] `parseGitBlame()` helper
- [ ] Add git graph functionality
  - [ ] `getCommitGraph()` with graph visualization
  - [ ] `parseGitGraph()` helper
  - [ ] `parseRefs()` for branch/tag decoration
- [ ] Add file history functionality
  - [ ] `getFileHistory()` for file-specific commits
- [ ] Add commit comparison functionality
  - [ ] `compareCommits()` for diff between refs
  - [ ] `parseDiffStat()` for file change stats
  - [ ] `parseDiff()` for detailed patch data
- [ ] Add utility functions
  - [ ] `getCommitCount()` for pagination
  - [ ] `commitExists()` for validation
- [ ] Create `/Users/williamcory/plue/server/routes/code-nav.ts`
  - [ ] GET `/:user/:repo/blame/:ref/*` - blame data
  - [ ] GET `/:user/:repo/graph` - commit graph
  - [ ] GET `/:user/:repo/history/:ref/*` - file history
  - [ ] GET `/:user/:repo/compare/:base...:head` - comparison
- [ ] Register routes in `/Users/williamcory/plue/server/index.ts`

### Phase 2: Frontend Pages
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/blame/[...path].astro`
  - [ ] Blame line display with commit grouping
  - [ ] Commit info sidebar (hash, author, time, message)
  - [ ] Line numbers with anchors
  - [ ] Syntax highlighting integration
  - [ ] File navigation (view, blame, history, raw)
  - [ ] Breadcrumb navigation
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/graph/[...ref].astro`
  - [ ] ASCII graph visualization
  - [ ] Commit details with refs/tags
  - [ ] Branch selector
  - [ ] Pagination
  - [ ] Link to individual commits
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/compare/[...refs].astro`
  - [ ] Ref selector (base...head)
  - [ ] Diff stats summary
  - [ ] Commit list between refs
  - [ ] File-by-file diff display
  - [ ] Syntax highlighted patches
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/commits/[...path].astro`
  - [ ] Commit list for file or branch
  - [ ] Commit metadata display
  - [ ] Links to view file at commit
  - [ ] Links to blame at commit
  - [ ] Pagination
- [ ] Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/blob/[...path].astro`
  - [ ] Add file navigation bar
  - [ ] Add line numbers with anchors (#L123)
  - [ ] Highlight target line on page load
  - [ ] Add blame/history/raw links

### Phase 3: Testing & Polish
- [ ] Test blame view
  - [ ] Verify blame data accuracy
  - [ ] Test commit grouping visual
  - [ ] Test line number anchors/permalinks
  - [ ] Test previous commit navigation
  - [ ] Test with large files
- [ ] Test graph view
  - [ ] Verify graph ASCII art renders correctly
  - [ ] Test branch filtering
  - [ ] Test pagination
  - [ ] Test ref decoration display
  - [ ] Test with complex merge histories
- [ ] Test commit comparison
  - [ ] Compare two commits
  - [ ] Compare branches
  - [ ] Compare tags
  - [ ] Verify diff stats accuracy
  - [ ] Test large diffs
- [ ] Test file history
  - [ ] Verify file-specific commits
  - [ ] Test file renames tracking
  - [ ] Test pagination
  - [ ] Test links to file at commit
- [ ] Test permalinks
  - [ ] Line anchors (#L123)
  - [ ] Line range selection
  - [ ] Commit-specific file links
  - [ ] Share links work correctly

### Phase 4: Performance & UX
- [ ] Optimize blame parsing for large files
- [ ] Add loading indicators for slow operations
- [ ] Implement client-side caching where appropriate
- [ ] Add keyboard shortcuts (j/k for navigation)
- [ ] Mobile responsive design
- [ ] Add copy-to-clipboard for commit hashes
- [ ] Add hover tooltips for commit info

## Implementation Time Estimate

- **Phase 1** (Backend): 6-8 hours
- **Phase 2** (Frontend): 10-12 hours
- **Phase 3** (Testing): 4-6 hours
- **Phase 4** (Polish): 3-4 hours
- **Total**: 23-30 hours

## Success Criteria

1. Users can view line-by-line blame for any file
2. Users can navigate commit history with visual graph
3. Users can compare any two commits/branches/tags
4. Users can view complete file history
5. Users can create permalinks to specific lines
6. All views have proper breadcrumb navigation
7. All views are mobile-responsive
8. Performance is acceptable for large files (< 2s load)
9. Git operations handle edge cases (renames, merges, etc.)
10. UI is consistent with brutalist design aesthetic

## Reference Implementation Notes

### Gitea's Approach

**Blame View** (`gitea/routers/web/repo/blame.go`):
- Uses `git blame --porcelain` for structured output
- Supports `.git-blame-ignore-revs` for ignoring formatting commits
- Groups consecutive lines by commit for cleaner UI
- Shows previous commit for each blame part
- Integrates with syntax highlighting

**Git Graph** (`gitea/services/repository/gitgraph/graph.go`):
- Uses `git log --graph --date-order --decorate=full`
- Parses ASCII graph characters into data structure
- Supports pagination with commit skip
- Filters PR refs optionally
- Supports branch and file path filtering

**Commit Comparison** (`gitea/routers/web/repo/compare.go`):
- Supports both `..` (direct) and `...` (merge-base) comparison
- Parses refs to handle branches, tags, commits
- Shows diff stats and file-by-file patches
- Handles fork comparisons
- Integrates with CSV diff for data files

**File History** (`gitea/modules/git/commit.go`):
- Uses `git log -- <file>` for file-specific history
- Follows file renames with `-M` flag
- Supports pagination
- Shows commit metadata with file status

### Plue's Simplified Approach

Plue uses direct git commands with simplified parsing:
1. **Blame**: Parse `--porcelain` output into structured data
2. **Graph**: Parse `--graph` output preserving ASCII art
3. **Compare**: Use `git diff` with numstat for stats
4. **History**: Standard git log with file path filter

This is simpler than Gitea's approach but covers core use cases effectively.

## Error Handling

### Common Errors

1. **File Not Found**: 404 if file doesn't exist at ref
2. **Invalid Ref**: 400 if branch/tag/commit invalid
3. **Binary File**: Show message for blame (can't blame binary)
4. **Large File**: Truncate or paginate for performance
5. **Repository Not Found**: 404 if repo doesn't exist
6. **Git Command Failed**: 500 with error message

### Security Considerations

1. **Path Validation**: Sanitize file paths to prevent traversal
2. **Ref Validation**: Validate commit hashes are valid hex
3. **Buffer Limits**: Set maxBuffer for git command output
4. **Rate Limiting**: Consider rate limits for expensive operations
5. **Access Control**: TODO: Check user permissions (future)

## API Documentation

### Get Blame Data

```
GET /api/code-nav/:user/:repo/blame/:ref/*
```

Example: `GET /api/code-nav/alice/myrepo/blame/main/src/index.ts`

**Response:**
```json
{
  "blame": [
    {
      "lineNumber": 1,
      "commitHash": "a1b2c3d4...",
      "commitShortHash": "a1b2c3d",
      "authorName": "Alice",
      "authorEmail": "alice@example.com",
      "authorTime": 1704067200000,
      "commitMessage": "Initial commit",
      "code": "import { foo } from './foo';",
      "previousCommitHash": "...",
      "previousFilePath": "src/index.ts"
    }
  ]
}
```

### Get Commit Graph

```
GET /api/code-nav/:user/:repo/graph?ref=main&limit=50&skip=0
```

**Query Parameters:**
- `ref`: Branch/tag/commit (optional, defaults to HEAD)
- `limit`: Number of commits (optional, default 50)
- `skip`: Skip N commits (optional, default 0)
- `hide_pr_refs`: Hide pull request refs (optional, default false)
- `branches`: Comma-separated branch names (optional)
- `file`: File path to filter (optional)

### Get File History

```
GET /api/code-nav/:user/:repo/history/:ref/*
```

Example: `GET /api/code-nav/alice/myrepo/history/main/src/index.ts?limit=50`

### Compare Commits

```
GET /api/code-nav/:user/:repo/compare/:base...:head
```

Example: `GET /api/code-nav/alice/myrepo/compare/v1.0...v2.0`

## Testing Strategy

### Manual Testing Checklist

1. **Blame View**
   - [ ] Open blame for text file
   - [ ] Verify commit info displayed
   - [ ] Click commit hash to view commit
   - [ ] Test line number anchors
   - [ ] Test with file that has renames

2. **Graph View**
   - [ ] View graph for repository
   - [ ] Switch branches
   - [ ] Navigate pagination
   - [ ] Verify graph visualization
   - [ ] Test with complex merge history

3. **Commit Comparison**
   - [ ] Compare two commits
   - [ ] Compare two branches
   - [ ] Compare two tags
   - [ ] Verify diff stats
   - [ ] Verify file patches

4. **File History**
   - [ ] View history for file
   - [ ] Click commit to view file at that commit
   - [ ] Test blame link from history
   - [ ] Navigate pagination

5. **Permalinks**
   - [ ] Create line permalink (#L123)
   - [ ] Share link and verify it works
   - [ ] Test line highlighting

### Automated Testing (Future)

```typescript
import { test, expect } from "bun:test";
import { getFileBlame, getCommitGraph } from "../ui/lib/git";

test("getFileBlame returns blame data", async () => {
  const blame = await getFileBlame("testuser", "testrepo", "main", "README.md");
  expect(blame.length).toBeGreaterThan(0);
  expect(blame[0].commitHash).toMatch(/^[0-9a-f]{40}$/);
});

test("getCommitGraph returns commits with graph", async () => {
  const commits = await getCommitGraph("testuser", "testrepo", { limit: 10 });
  expect(commits.length).toBeLessThanOrEqual(10);
  expect(commits[0].graph).toBeTruthy();
});
```
