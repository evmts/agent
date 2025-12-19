# Pull Requests Feature Implementation

## Overview

Implement a GitHub-style Pull Request (PR) feature for Plue, allowing users to propose, review, and merge changes between branches. This builds on the existing Issues feature and repository infrastructure.

**Scope**: Full PR lifecycle including creation, reviewing, diffing, conflict detection, and merging with multiple merge strategies.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database, Git CLI operations.

---

## 1. Database Schema Changes

### 1.1 Pull Requests Table

```sql
-- Pull requests extend issues
CREATE TABLE IF NOT EXISTS pull_requests (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,

  -- Branch information
  head_repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
  head_branch VARCHAR(255) NOT NULL,
  head_commit_id VARCHAR(64),
  base_repo_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  base_branch VARCHAR(255) NOT NULL,
  merge_base VARCHAR(64),

  -- Status
  status VARCHAR(20) DEFAULT 'checking' CHECK (status IN (
    'checking',      -- Checking for conflicts
    'mergeable',     -- Can be merged
    'conflict',      -- Has merge conflicts
    'merged',        -- Already merged
    'error',         -- Error during check
    'empty'          -- No changes
  )),

  -- Merge information
  has_merged BOOLEAN DEFAULT false,
  merged_at TIMESTAMP,
  merged_by INTEGER REFERENCES users(id),
  merged_commit_id VARCHAR(64),
  merge_style VARCHAR(20) CHECK (merge_style IN ('merge', 'squash', 'rebase')),

  -- Stats
  commits_ahead INTEGER DEFAULT 0,
  commits_behind INTEGER DEFAULT 0,
  additions INTEGER DEFAULT 0,
  deletions INTEGER DEFAULT 0,
  changed_files INTEGER DEFAULT 0,
  conflicted_files TEXT[], -- Array of file paths with conflicts

  -- Settings
  allow_maintainer_edit BOOLEAN DEFAULT true,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(issue_id)
);

CREATE INDEX idx_pull_requests_head_repo ON pull_requests(head_repo_id);
CREATE INDEX idx_pull_requests_base_repo ON pull_requests(base_repo_id);
CREATE INDEX idx_pull_requests_status ON pull_requests(status);
CREATE INDEX idx_pull_requests_merged ON pull_requests(has_merged);
```

### 1.2 Reviews Table

```sql
-- Code reviews for pull requests
CREATE TABLE IF NOT EXISTS reviews (
  id SERIAL PRIMARY KEY,
  pull_request_id INTEGER NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  reviewer_id INTEGER NOT NULL REFERENCES users(id),

  -- Review type
  type VARCHAR(20) NOT NULL CHECK (type IN (
    'pending',    -- Draft review not yet submitted
    'comment',    -- General feedback
    'approve',    -- Approve changes
    'request_changes' -- Request changes before merge
  )),

  content TEXT, -- Overall review comment
  commit_id VARCHAR(64), -- Commit being reviewed

  -- Status
  official BOOLEAN DEFAULT false, -- Made by assigned reviewer
  stale BOOLEAN DEFAULT false,    -- Outdated due to new commits
  dismissed BOOLEAN DEFAULT false, -- Dismissed by maintainer

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_reviews_pr ON reviews(pull_request_id);
CREATE INDEX idx_reviews_reviewer ON reviews(reviewer_id);
CREATE INDEX idx_reviews_type ON reviews(type);
```

### 1.3 Review Comments Table

```sql
-- Line-by-line code comments
CREATE TABLE IF NOT EXISTS review_comments (
  id SERIAL PRIMARY KEY,
  review_id INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  pull_request_id INTEGER NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  author_id INTEGER NOT NULL REFERENCES users(id),

  -- Location in diff
  commit_id VARCHAR(64) NOT NULL,
  file_path TEXT NOT NULL,
  diff_side VARCHAR(10) CHECK (diff_side IN ('left', 'right')), -- old vs new
  line INTEGER NOT NULL, -- Line number in the file

  -- Content
  body TEXT NOT NULL,

  -- Status
  invalidated BOOLEAN DEFAULT false, -- Line changed by subsequent commit
  resolved BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_review_comments_review ON review_comments(review_id);
CREATE INDEX idx_review_comments_pr ON review_comments(pull_request_id);
CREATE INDEX idx_review_comments_file ON review_comments(pull_request_id, file_path);
```

### 1.4 Schema Migration

Update `/Users/williamcory/plue/db/schema.sql` to include these tables after the existing Issues/Comments section.

Update `/Users/williamcory/plue/db/migrate.ts` to run the new schema additions.

---

## 2. TypeScript Types

Add to `/Users/williamcory/plue/ui/lib/types.ts`:

```typescript
export type PullRequestStatus =
  | 'checking'
  | 'mergeable'
  | 'conflict'
  | 'merged'
  | 'error'
  | 'empty';

export type MergeStyle = 'merge' | 'squash' | 'rebase';

export type ReviewType = 'pending' | 'comment' | 'approve' | 'request_changes';

export interface PullRequest {
  id: number;
  issue_id: number;

  // Branch info
  head_repo_id: number | null;
  head_branch: string;
  head_commit_id: string | null;
  base_repo_id: number;
  base_branch: string;
  merge_base: string | null;

  // Status
  status: PullRequestStatus;

  // Merge info
  has_merged: boolean;
  merged_at: Date | null;
  merged_by: number | null;
  merged_commit_id: string | null;
  merge_style: MergeStyle | null;

  // Stats
  commits_ahead: number;
  commits_behind: number;
  additions: number;
  deletions: number;
  changed_files: number;
  conflicted_files: string[] | null;

  allow_maintainer_edit: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined fields
  issue?: Issue;
  head_repo?: Repository;
  base_repo?: Repository;
  merger?: User;
}

export interface Review {
  id: number;
  pull_request_id: number;
  reviewer_id: number;
  type: ReviewType;
  content: string | null;
  commit_id: string | null;
  official: boolean;
  stale: boolean;
  dismissed: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined
  reviewer?: User;
}

export interface ReviewComment {
  id: number;
  review_id: number;
  pull_request_id: number;
  author_id: number;
  commit_id: string;
  file_path: string;
  diff_side: 'left' | 'right';
  line: number;
  body: string;
  invalidated: boolean;
  resolved: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined
  author?: User;
}

export interface DiffFile {
  name: string;
  oldName?: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  additions: number;
  deletions: number;
  changes: number;
  patch: string;
  isBinary: boolean;
}

export interface CompareInfo {
  merge_base: string;
  base_commit_id: string;
  head_commit_id: string;
  commits: Commit[];
  files: DiffFile[];
  total_additions: number;
  total_deletions: number;
  total_files: number;
}
```

---

## 3. Git Operations Library

Extend `/Users/williamcory/plue/ui/lib/git.ts` with PR-specific operations:

```typescript
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
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

/**
 * Merge a pull request using specified strategy
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

  await run(`git config user.name "${authorName}"`, repoPath);
  await run(`git config user.email "${authorEmail}"`, repoPath);
  await run(`git checkout "${baseBranch}"`, repoPath);

  let mergeCommitId: string;

  switch (style) {
    case 'merge':
      // Standard merge commit (--no-ff ensures merge commit)
      await run(`git merge --no-ff -m "${message}" "${headBranch}"`, repoPath);
      mergeCommitId = await run(`git rev-parse HEAD`, repoPath);
      break;

    case 'squash':
      // Squash all commits into one
      await run(`git merge --squash "${headBranch}"`, repoPath);
      await run(`git commit -m "${message}"`, repoPath);
      mergeCommitId = await run(`git rev-parse HEAD`, repoPath);
      break;

    case 'rebase':
      // Rebase and fast-forward
      await run(`git rebase "${headBranch}"`, repoPath);
      mergeCommitId = await run(`git rev-parse HEAD`, repoPath);
      break;

    default:
      throw new Error(`Unknown merge style: ${style}`);
  }

  return mergeCommitId.trim();
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
```

---

## 4. API Routes

Create `/Users/williamcory/plue/server/routes/pulls.ts`:

```typescript
/**
 * Pull Request routes - PR CRUD, merging, diffing, reviews
 */

import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';
import type {
  User,
  Repository,
  Issue,
  PullRequest,
  Review,
  ReviewComment,
  MergeStyle
} from '../../ui/lib/types';
import {
  compareRefs,
  checkMergeable,
  mergePullRequest,
} from '../../ui/lib/git';

const app = new Hono();

// List pull requests for a repository
app.get('/:user/:repo/pulls', async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const state = c.req.query('state') || 'open';

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const pulls = await sql`
    SELECT
      pr.*,
      i.title, i.state, i.issue_number, i.created_at as issue_created_at,
      u.username as author_username
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    JOIN users u ON i.author_id = u.id
    WHERE pr.base_repo_id = ${repo.id}
    ${state === 'all' ? sql`` : state === 'open'
      ? sql`AND i.state = 'open' AND pr.has_merged = false`
      : state === 'closed'
      ? sql`AND i.state = 'closed'`
      : state === 'merged'
      ? sql`AND pr.has_merged = true`
      : sql``
    }
    ORDER BY pr.created_at DESC
  `;

  return c.json({ pulls });
});

// Get a specific pull request
app.get('/:user/:repo/pulls/:number', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*, i.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  `;

  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  return c.json({ pull: pr });
});

// Create a pull request
app.post('/:user/:repo/pulls', async (c) => {
  const { user: username, repo: reponame } = c.req.param();
  const body = await c.req.json();
  const { title, description, head_branch, base_branch, author_id } = body;

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  // Get next issue number
  const [{ max_number }] = await sql`
    SELECT COALESCE(MAX(issue_number), 0) as max_number
    FROM issues
    WHERE repository_id = ${repo.id}
  `;
  const issueNumber = max_number + 1;

  // Create issue first
  const [issue] = await sql`
    INSERT INTO issues (
      repository_id, author_id, issue_number, title, body, state
    ) VALUES (
      ${repo.id}, ${author_id}, ${issueNumber}, ${title}, ${description || ''}, 'open'
    )
    RETURNING *
  ` as Issue[];

  // Compare branches
  const compareInfo = await compareRefs(username, reponame, base_branch, head_branch);

  // Check for conflicts
  const { mergeable, conflictedFiles } = await checkMergeable(
    username,
    reponame,
    base_branch,
    head_branch
  );

  // Create pull request
  const [pr] = await sql`
    INSERT INTO pull_requests (
      issue_id,
      head_repo_id, head_branch, head_commit_id,
      base_repo_id, base_branch,
      merge_base,
      status,
      additions, deletions, changed_files,
      conflicted_files
    ) VALUES (
      ${issue.id},
      ${repo.id}, ${head_branch}, ${compareInfo.head_commit_id},
      ${repo.id}, ${base_branch},
      ${compareInfo.merge_base},
      ${mergeable ? 'mergeable' : 'conflict'},
      ${compareInfo.total_additions}, ${compareInfo.total_deletions}, ${compareInfo.total_files},
      ${conflictedFiles.length > 0 ? JSON.stringify(conflictedFiles) : null}
    )
    RETURNING *
  ` as PullRequest[];

  return c.json({ pull: { ...pr, issue } }, 201);
});

// Get pull request diff
app.get('/:user/:repo/pulls/:number/diff', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];

  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  const compareInfo = await compareRefs(
    username,
    reponame,
    pr.base_branch,
    pr.head_branch
  );

  return c.json({ diff: compareInfo });
});

// Merge a pull request
app.post('/:user/:repo/pulls/:number/merge', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();
  const body = await c.req.json();
  const { merge_style, merge_message, merger_id } = body as {
    merge_style: MergeStyle;
    merge_message: string;
    merger_id: number;
  };

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*, i.state
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];

  if (!pr) return c.json({ error: 'Pull request not found' }, 404);
  if (pr.has_merged) return c.json({ error: 'Already merged' }, 400);
  if (pr.status !== 'mergeable') {
    return c.json({ error: `Cannot merge: status is ${pr.status}` }, 400);
  }

  const [merger] = await sql`SELECT * FROM users WHERE id = ${merger_id}` as User[];

  // Perform merge
  const mergeCommitId = await mergePullRequest(
    username,
    reponame,
    pr.base_branch,
    pr.head_branch,
    merge_style,
    merge_message,
    merger.username,
    `${merger.username}@plue.local`
  );

  // Update PR
  await sql`
    UPDATE pull_requests
    SET
      has_merged = true,
      merged_at = NOW(),
      merged_by = ${merger_id},
      merged_commit_id = ${mergeCommitId},
      merge_style = ${merge_style},
      status = 'merged'
    WHERE id = ${pr.id}
  `;

  // Close issue
  await sql`
    UPDATE issues
    SET state = 'closed', closed_at = NOW()
    WHERE id = ${pr.issue_id}
  `;

  return c.json({ success: true, merge_commit_id: mergeCommitId });
});

// Create a review
app.post('/:user/:repo/pulls/:number/reviews', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();
  const body = await c.req.json();
  const { reviewer_id, type, content, commit_id } = body;

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];

  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  const [review] = await sql`
    INSERT INTO reviews (
      pull_request_id, reviewer_id, type, content, commit_id
    ) VALUES (
      ${pr.id}, ${reviewer_id}, ${type}, ${content || null}, ${commit_id || null}
    )
    RETURNING *
  ` as Review[];

  return c.json({ review }, 201);
});

// List reviews for a PR
app.get('/:user/:repo/pulls/:number/reviews', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];

  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  const reviews = await sql`
    SELECT r.*, u.username as reviewer_username
    FROM reviews r
    JOIN users u ON r.reviewer_id = u.id
    WHERE r.pull_request_id = ${pr.id}
    ORDER BY r.created_at DESC
  ` as Review[];

  return c.json({ reviews });
});

export default app;
```

Register the routes in `/Users/williamcory/plue/server/index.ts`:

```typescript
import pullsRoutes from './routes/pulls';

// ... existing code ...

app.route('/api', pullsRoutes);
```

---

## 5. UI Pages

### 5.1 Pull Requests List Page

Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/pulls/index.astro`:

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;
const state = Astro.url.searchParams.get("state") || "open";

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];
if (!repo) return Astro.redirect("/404");

const pulls = await sql`
  SELECT
    pr.*,
    i.title, i.state, i.issue_number, i.author_id,
    u.username as author_username
  FROM pull_requests pr
  JOIN issues i ON pr.issue_id = i.id
  JOIN users u ON i.author_id = u.id
  WHERE pr.base_repo_id = ${repo.id}
  ${state === 'all' ? sql`` : state === 'open'
    ? sql`AND i.state = 'open' AND pr.has_merged = false`
    : state === 'merged'
    ? sql`AND pr.has_merged = true`
    : sql``
  }
  ORDER BY pr.created_at DESC
`;

const [{ open_count }] = await sql`
  SELECT COUNT(*) as open_count
  FROM pull_requests pr
  JOIN issues i ON pr.issue_id = i.id
  WHERE pr.base_repo_id = ${repo.id}
    AND i.state = 'open'
    AND pr.has_merged = false
`;

const [{ merged_count }] = await sql`
  SELECT COUNT(*) as merged_count
  FROM pull_requests pr
  WHERE pr.base_repo_id = ${repo.id} AND pr.has_merged = true
`;
---

<Layout title={`Pull Requests · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">pulls</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/pulls`} class="active">Pull Requests</a>
    <a href={`/${username}/${reponame}/commits/${repo.default_branch}`}>Commits</a>
  </nav>

  <div class="container">
    <div class="flex-between mb-3">
      <h1 class="page-title">Pull Requests</h1>
      <a href={`/${username}/${reponame}/pulls/new`} class="btn btn-primary">New PR</a>
    </div>

    <div class="tabs">
      <a
        href={`/${username}/${reponame}/pulls?state=open`}
        class:list={["tab", { active: state === "open" }]}
      >
        {open_count} Open
      </a>
      <a
        href={`/${username}/${reponame}/pulls?state=merged`}
        class:list={["tab", { active: state === "merged" }]}
      >
        {merged_count} Merged
      </a>
    </div>

    {pulls.length === 0 ? (
      <div class="empty-state">
        <p>No {state} pull requests</p>
      </div>
    ) : (
      <div class="pr-list">
        {pulls.map((pr: any) => (
          <a href={`/${username}/${reponame}/pulls/${pr.issue_number}`} class="pr-item">
            <span class:list={["pr-status", pr.has_merged ? "merged" : pr.status]}>
              {pr.has_merged ? "merged" : pr.status}
            </span>
            <div class="pr-content">
              <div class="pr-title">{pr.title}</div>
              <div class="pr-meta">
                #{pr.issue_number} · {pr.head_branch} → {pr.base_branch} · by {pr.author_username}
              </div>
              <div class="pr-stats">
                +{pr.additions} -{pr.deletions} · {pr.changed_files} files
              </div>
            </div>
          </a>
        ))}
      </div>
    )}
  </div>
</Layout>

<style>
  .pr-list {
    border: 1px solid black;
  }

  .pr-item {
    display: flex;
    gap: 1rem;
    padding: 1rem;
    border-bottom: 1px solid black;
    text-decoration: none;
    color: inherit;
  }

  .pr-item:last-child {
    border-bottom: none;
  }

  .pr-item:hover {
    background: #f5f5f5;
  }

  .pr-status {
    padding: 0.25rem 0.5rem;
    border: 1px solid black;
    font-size: 0.75rem;
    text-transform: uppercase;
    align-self: flex-start;
  }

  .pr-status.mergeable {
    background: #d4edda;
  }

  .pr-status.merged {
    background: #6f42c1;
    color: white;
  }

  .pr-status.conflict {
    background: #f8d7da;
  }

  .pr-content {
    flex: 1;
  }

  .pr-title {
    font-weight: bold;
    margin-bottom: 0.25rem;
  }

  .pr-meta {
    font-size: 0.875rem;
    color: #666;
  }

  .pr-stats {
    font-size: 0.875rem;
    color: #666;
    margin-top: 0.25rem;
  }
</style>
```

### 5.2 Pull Request Detail Page

Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/pulls/[number].astro`:

```astro
---
import Layout from "../../../../../layouts/Layout.astro";
import Header from "../../../../../components/Header.astro";
import Markdown from "../../../../../components/Markdown.astro";
import { sql } from "../../../../../lib/db";
import type { User, Repository, PullRequest } from "../../../../../lib/types";

const { user: username, repo: reponame, number } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];
if (!repo) return Astro.redirect("/404");

const [pr] = await sql`
  SELECT pr.*, i.*, u.username as author_username
  FROM pull_requests pr
  JOIN issues i ON pr.issue_id = i.id
  JOIN users u ON i.author_id = u.id
  WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number!, 10)}
` as PullRequest[];

if (!pr) return Astro.redirect("/404");

const reviews = await sql`
  SELECT r.*, u.username as reviewer_username
  FROM reviews r
  JOIN users u ON r.reviewer_id = u.id
  WHERE r.pull_request_id = ${pr.id}
  ORDER BY r.created_at DESC
`;

const canMerge = pr.status === 'mergeable' && !pr.has_merged && pr.state === 'open';
---

<Layout title={`PR #${number} · ${pr.title}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/pulls`}>pulls</a>
    <span class="sep">/</span>
    <span class="current">#{number}</span>
  </div>

  <div class="container">
    <div class="pr-header">
      <h1 class="pr-title">{pr.title} <span class="pr-number">#{pr.issue_number}</span></h1>
      <div class="pr-branches">
        {pr.head_branch} → {pr.base_branch}
      </div>
      <div class="pr-status-bar">
        <span class:list={["status-badge", pr.has_merged ? "merged" : pr.status]}>
          {pr.has_merged ? "Merged" : pr.status}
        </span>
        {pr.conflicted_files && pr.conflicted_files.length > 0 && (
          <span class="conflict-warning">
            {pr.conflicted_files.length} conflicted files
          </span>
        )}
      </div>
    </div>

    <div class="pr-body">
      <div class="pr-description">
        <div class="author-info">
          <strong>{pr.author_username}</strong> opened this pull request
        </div>
        <Markdown content={pr.body || "No description provided."} />
      </div>

      <div class="pr-stats">
        <div class="stat">
          <span class="stat-label">Commits:</span>
          <span class="stat-value">{pr.commits_ahead}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Files changed:</span>
          <span class="stat-value">{pr.changed_files}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Additions:</span>
          <span class="stat-value add">+{pr.additions}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Deletions:</span>
          <span class="stat-value del">-{pr.deletions}</span>
        </div>
      </div>
    </div>

    <div class="pr-tabs">
      <a href={`/${username}/${reponame}/pulls/${number}`} class="tab active">Conversation</a>
      <a href={`/${username}/${reponame}/pulls/${number}/files`} class="tab">Files Changed</a>
    </div>

    <div class="reviews-section">
      <h2>Reviews</h2>
      {reviews.length === 0 ? (
        <p class="empty-reviews">No reviews yet</p>
      ) : (
        reviews.map((review: any) => (
          <div class="review-card">
            <div class="review-header">
              <strong>{review.reviewer_username}</strong>
              <span class:list={["review-type", review.type]}>
                {review.type.replace('_', ' ')}
              </span>
            </div>
            {review.content && (
              <div class="review-content">
                <Markdown content={review.content} />
              </div>
            )}
          </div>
        ))
      )}
    </div>

    {canMerge && (
      <div class="merge-section">
        <h2>Merge Pull Request</h2>
        <form method="POST" action={`/api/${username}/${repo}/pulls/${number}/merge`}>
          <input type="hidden" name="merger_id" value="1" />
          <div class="form-group">
            <label for="merge_style">Merge Strategy:</label>
            <select name="merge_style" id="merge_style">
              <option value="merge">Create a merge commit</option>
              <option value="squash">Squash and merge</option>
              <option value="rebase">Rebase and merge</option>
            </select>
          </div>
          <div class="form-group">
            <label for="merge_message">Commit Message:</label>
            <textarea
              name="merge_message"
              id="merge_message"
              rows="3"
            >Merge pull request #{pr.issue_number} from {pr.head_branch}

{pr.title}</textarea>
          </div>
          <button type="submit" class="btn btn-success">Merge Pull Request</button>
        </form>
      </div>
    )}
  </div>
</Layout>

<style>
  .pr-header {
    margin-bottom: 2rem;
  }

  .pr-title {
    margin-bottom: 0.5rem;
  }

  .pr-number {
    color: #666;
    font-weight: normal;
  }

  .pr-branches {
    font-family: monospace;
    margin-bottom: 0.5rem;
  }

  .status-badge {
    display: inline-block;
    padding: 0.25rem 0.5rem;
    border: 1px solid black;
    font-size: 0.875rem;
  }

  .status-badge.mergeable {
    background: #d4edda;
  }

  .status-badge.merged {
    background: #6f42c1;
    color: white;
  }

  .status-badge.conflict {
    background: #f8d7da;
  }

  .conflict-warning {
    color: #721c24;
    margin-left: 1rem;
  }

  .pr-body {
    border: 1px solid black;
    padding: 1rem;
    margin-bottom: 2rem;
  }

  .pr-stats {
    display: flex;
    gap: 2rem;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid black;
  }

  .stat-label {
    font-weight: bold;
  }

  .stat-value.add {
    color: green;
  }

  .stat-value.del {
    color: red;
  }

  .reviews-section {
    margin: 2rem 0;
  }

  .review-card {
    border: 1px solid black;
    padding: 1rem;
    margin-bottom: 1rem;
  }

  .review-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
  }

  .review-type {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    text-transform: uppercase;
  }

  .review-type.approve {
    background: #d4edda;
  }

  .review-type.request_changes {
    background: #f8d7da;
  }

  .merge-section {
    border: 1px solid black;
    padding: 1rem;
    margin-top: 2rem;
  }

  .form-group {
    margin-bottom: 1rem;
  }

  .form-group label {
    display: block;
    font-weight: bold;
    margin-bottom: 0.25rem;
  }

  .form-group select,
  .form-group textarea {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid black;
    font-family: monospace;
  }
</style>
```

### 5.3 Files Changed Page (Diff Viewer)

Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/pulls/[number]/files.astro`:

```astro
---
import Layout from "../../../../../../layouts/Layout.astro";
import Header from "../../../../../../components/Header.astro";
import { sql } from "../../../../../../lib/db";
import { compareRefs } from "../../../../../../lib/git";
import type { User, Repository, PullRequest } from "../../../../../../lib/types";

const { user: username, repo: reponame, number } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];
if (!repo) return Astro.redirect("/404");

const [pr] = await sql`
  SELECT pr.*, i.title
  FROM pull_requests pr
  JOIN issues i ON pr.issue_id = i.id
  WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number!, 10)}
` as PullRequest[];

if (!pr) return Astro.redirect("/404");

const compareInfo = await compareRefs(username, reponame, pr.base_branch, pr.head_branch);
---

<Layout title={`Files · PR #${number}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/pulls/${number}`}>PR #{number}</a>
    <span class="sep">/</span>
    <span class="current">files</span>
  </div>

  <div class="container">
    <h1>Files Changed</h1>

    <div class="diff-stats">
      <strong>{compareInfo.total_files}</strong> files changed,
      <span class="add">+{compareInfo.total_additions}</span>,
      <span class="del">-{compareInfo.total_deletions}</span>
    </div>

    <div class="files-list">
      {compareInfo.files.map((file) => (
        <div class="file-diff">
          <div class="file-header">
            <span class:list={["file-status", file.status]}>{file.status}</span>
            <span class="file-name">{file.name}</span>
            <span class="file-stats">
              <span class="add">+{file.additions}</span>
              <span class="del">-{file.deletions}</span>
            </span>
          </div>

          {file.isBinary ? (
            <div class="binary-file">Binary file</div>
          ) : (
            <pre class="diff-patch"><code>{file.patch}</code></pre>
          )}
        </div>
      ))}
    </div>
  </div>
</Layout>

<style>
  .diff-stats {
    margin: 1rem 0;
    padding: 1rem;
    border: 1px solid black;
  }

  .add {
    color: green;
  }

  .del {
    color: red;
  }

  .files-list {
    margin-top: 2rem;
  }

  .file-diff {
    border: 1px solid black;
    margin-bottom: 2rem;
  }

  .file-header {
    background: #f5f5f5;
    padding: 0.5rem 1rem;
    border-bottom: 1px solid black;
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .file-status {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    text-transform: uppercase;
    border: 1px solid black;
  }

  .file-status.added {
    background: #d4edda;
  }

  .file-status.modified {
    background: #fff3cd;
  }

  .file-status.deleted {
    background: #f8d7da;
  }

  .file-name {
    flex: 1;
    font-family: monospace;
  }

  .diff-patch {
    padding: 1rem;
    overflow-x: auto;
    font-size: 0.875rem;
    line-height: 1.5;
  }

  .binary-file {
    padding: 2rem;
    text-align: center;
    color: #666;
  }
</style>
```

### 5.4 New Pull Request Page

Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/pulls/new.astro`:

```astro
---
import Layout from "../../../../../layouts/Layout.astro";
import Header from "../../../../../components/Header.astro";
import { sql } from "../../../../../lib/db";
import { listBranches } from "../../../../../lib/git";
import type { User, Repository } from "../../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];
if (!repo) return Astro.redirect("/404");

const branches = await listBranches(username, reponame);
const users = await sql`SELECT id, username FROM users` as User[];
---

<Layout title={`New Pull Request · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/pulls`}>pulls</a>
    <span class="sep">/</span>
    <span class="current">new</span>
  </div>

  <div class="container">
    <h1>New Pull Request</h1>

    <form method="POST" action={`/api/${username}/${reponame}/pulls`}>
      <div class="form-group">
        <label for="title">Title</label>
        <input
          type="text"
          id="title"
          name="title"
          required
          placeholder="Describe your changes"
        />
      </div>

      <div class="form-group">
        <label for="description">Description</label>
        <textarea
          id="description"
          name="description"
          rows="10"
          placeholder="Provide more details about this pull request"
        ></textarea>
      </div>

      <div class="branch-selector">
        <div class="form-group">
          <label for="base_branch">Base branch</label>
          <select id="base_branch" name="base_branch" required>
            {branches.map(branch => (
              <option value={branch} selected={branch === repo.default_branch}>
                {branch}
              </option>
            ))}
          </select>
        </div>

        <div class="arrow">←</div>

        <div class="form-group">
          <label for="head_branch">Compare branch</label>
          <select id="head_branch" name="head_branch" required>
            {branches.map(branch => (
              <option value={branch}>{branch}</option>
            ))}
          </select>
        </div>
      </div>

      <input type="hidden" name="author_id" value={users[0].id} />

      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Create Pull Request</button>
        <a href={`/${username}/${reponame}/pulls`} class="btn">Cancel</a>
      </div>
    </form>
  </div>
</Layout>

<style>
  .form-group {
    margin-bottom: 1.5rem;
  }

  .form-group label {
    display: block;
    font-weight: bold;
    margin-bottom: 0.5rem;
  }

  .form-group input,
  .form-group textarea,
  .form-group select {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid black;
    font-family: inherit;
  }

  .branch-selector {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    gap: 1rem;
    align-items: center;
    margin: 2rem 0;
    padding: 1rem;
    border: 1px solid black;
  }

  .arrow {
    font-size: 2rem;
  }

  .form-actions {
    display: flex;
    gap: 1rem;
  }
</style>
```

---

## 6. Implementation Checklist

### Phase 1: Database & Types
- [ ] Add pull_requests, reviews, and review_comments tables to schema.sql
- [ ] Update db/migrate.ts to run new migrations
- [ ] Add TypeScript types to ui/lib/types.ts
- [ ] Run migration: `bun db/migrate.ts`

### Phase 2: Git Operations
- [ ] Implement compareRefs() in ui/lib/git.ts
- [ ] Implement checkMergeable() in ui/lib/git.ts
- [ ] Implement mergePullRequest() with merge/squash/rebase strategies
- [ ] Add getFileStatus() helper
- [ ] Test all git operations with sample branches

### Phase 3: API Routes
- [ ] Create server/routes/pulls.ts
- [ ] Implement GET /pulls (list PRs)
- [ ] Implement GET /pulls/:number (get PR details)
- [ ] Implement POST /pulls (create PR)
- [ ] Implement GET /pulls/:number/diff (get diff)
- [ ] Implement POST /pulls/:number/merge (merge PR)
- [ ] Implement POST /pulls/:number/reviews (create review)
- [ ] Implement GET /pulls/:number/reviews (list reviews)
- [ ] Register routes in server/index.ts

### Phase 4: UI Pages
- [ ] Create ui/pages/[user]/[repo]/pulls/index.astro (PR list)
- [ ] Create ui/pages/[user]/[repo]/pulls/[number].astro (PR detail)
- [ ] Create ui/pages/[user]/[repo]/pulls/[number]/files.astro (diff viewer)
- [ ] Create ui/pages/[user]/[repo]/pulls/new.astro (create PR form)
- [ ] Add "Pull Requests" link to repo navigation

### Phase 5: Components (Optional Enhancements)
- [ ] Create PullRequestCard.astro component (similar to IssueCard)
- [ ] Create DiffViewer.astro component with syntax highlighting
- [ ] Create ReviewCard.astro component
- [ ] Create MergeButton.astro component with strategy selector

### Phase 6: Testing
- [ ] Test PR creation with same-repo branches
- [ ] Test merge conflict detection
- [ ] Test all three merge strategies (merge, squash, rebase)
- [ ] Test review creation and listing
- [ ] Test edge cases (already merged, closed PRs, etc.)

---

## 7. Reference: Gitea Implementation Patterns

### Key Gitea Concepts Adapted for Plue

**Pull Request Status Flow** (from gitea/models/issues/pull.go:98-106):
- `checking` → Initial state, checking for conflicts
- `mergeable` → Can be merged cleanly
- `conflict` → Has merge conflicts
- `merged` → Successfully merged
- `error` → Error during merge check
- `empty` → No changes between branches

**Merge Strategies** (from gitea/services/pull/merge*.go):
1. **Merge Commit** (merge_merge.go): Creates a merge commit with `--no-ff`
2. **Squash** (merge_squash.go): Squashes all commits into one
3. **Rebase** (merge_rebase.go): Rebases and fast-forwards

**Review Types** (from gitea/models/issues/review.go:93-104):
- `pending`: Draft review
- `comment`: General feedback
- `approve`: Approve changes
- `request_changes`: Block merge until addressed

**Compare Logic** (from gitea/services/pull/compare.go):
- Uses three-dot notation (`base...head`) for diffs
- Calculates merge-base to find common ancestor
- Tracks commits ahead/behind

---

## 8. Implementation Notes

### Git Operations Safety
- Always use temporary directories for merge checks to avoid corrupting the bare repo
- Use `--no-commit` flag when testing merges
- Clean up temp directories in finally blocks

### Performance Considerations
- Cache diff results for large PRs
- Use `git diff --numstat` for quick stats before full patch
- Limit commit history to reasonable number (100 commits)

### Error Handling
- Handle deleted branches gracefully
- Check PR is open before allowing merge
- Validate merge status before executing merge
- Return user-friendly error messages

### Future Enhancements (Out of Scope)
- Branch protection rules
- Required reviewers/approvals
- CI/CD integration
- Suggested reviewers
- Draft PRs
- Auto-merge after checks
- Inline comment threads
- Commit-level comments

---

## 9. Testing Commands

```bash
# Start the server
bun server/main.ts

# Run migrations
bun db/migrate.ts

# Test PR creation (replace with actual values)
curl -X POST http://localhost:3000/api/evilrabbit/test-repo/pulls \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Add new feature",
    "description": "This PR adds...",
    "head_branch": "feature-branch",
    "base_branch": "main",
    "author_id": 1
  }'

# Test merge
curl -X POST http://localhost:3000/api/evilrabbit/test-repo/pulls/1/merge \
  -H "Content-Type: application/json" \
  -d '{
    "merge_style": "squash",
    "merge_message": "Merge PR #1",
    "merger_id": 1
  }'
```

---

## 10. Success Criteria

The implementation is complete when:
1. Users can create PRs between branches
2. PR list page shows all PRs with status indicators
3. PR detail page shows description, stats, and reviews
4. Files changed page displays diffs
5. Merge functionality works with all three strategies
6. Conflict detection accurately identifies conflicted files
7. Reviews can be created and displayed
8. All pages follow Plue's brutalist design aesthetic

---

**References:**
- Gitea source: `/Users/williamcory/plue/gitea/`
- Existing schema: `/Users/williamcory/plue/db/schema.sql`
- Git utilities: `/Users/williamcory/plue/ui/lib/git.ts`
- Example routes: `/Users/williamcory/plue/server/routes/sessions.ts`
- Example pages: `/Users/williamcory/plue/ui/pages/[user]/[repo]/issues/index.astro`
