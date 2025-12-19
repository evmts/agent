# Tags & Releases Feature Implementation

## Overview

Implement a complete tags and releases system for Plue, enabling version management, release notes, and asset distribution. This feature adds Git tag management, release creation with markdown notes, file attachments, pre-release/draft states, and auto-generated release notes from commit history.

**Scope**: Full CRUD operations for releases, tag operations, asset uploads, release notes generation, and archive downloads.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database.

---

## 1. Database Schema Changes

### 1.1 Releases Table

Releases represent tagged versions of a repository with associated metadata, notes, and assets.

```sql
-- Releases and tags
CREATE TABLE IF NOT EXISTS releases (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  -- User who published the release
  publisher_id INTEGER NOT NULL REFERENCES users(id),

  -- Tag information
  tag_name VARCHAR(255) NOT NULL,
  lower_tag_name VARCHAR(255) NOT NULL, -- For case-insensitive lookups
  target VARCHAR(255) NOT NULL, -- Branch or commit to create tag from

  -- Release metadata
  title VARCHAR(255) NOT NULL,
  note TEXT, -- Markdown release notes

  -- Git information
  sha1 VARCHAR(64), -- Commit SHA the tag points to
  num_commits INTEGER DEFAULT 0, -- Number of commits in this release

  -- Release states
  is_draft BOOLEAN DEFAULT false, -- Draft releases are not published
  is_prerelease BOOLEAN DEFAULT false, -- Pre-release (alpha, beta, rc)
  is_tag BOOLEAN DEFAULT false, -- True if just a tag (no release notes)

  -- Migration fields (for imported releases)
  original_author VARCHAR(255),
  original_author_id BIGINT,

  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(repository_id, lower_tag_name)
);

CREATE INDEX idx_releases_repo ON releases(repository_id);
CREATE INDEX idx_releases_tag ON releases(tag_name);
CREATE INDEX idx_releases_sha ON releases(sha1);
CREATE INDEX idx_releases_created ON releases(created_at DESC);
```

**Key Features:**
- **Tag management**: Each release is associated with a Git tag
- **Draft releases**: Create releases before they're ready to publish
- **Pre-releases**: Mark alpha/beta/rc versions
- **Tag-only mode**: Create tags without release notes
- **Commit tracking**: Store commit count and SHA for each release

### 1.2 Release Attachments Table

Release attachments store uploaded binaries, archives, and other files.

```sql
-- Release attachments (binaries, archives, etc.)
CREATE TABLE IF NOT EXISTS release_attachments (
  id SERIAL PRIMARY KEY,

  -- References
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  release_id INTEGER REFERENCES releases(id) ON DELETE CASCADE,
  uploader_id INTEGER REFERENCES users(id),

  -- File metadata
  uuid VARCHAR(36) UNIQUE NOT NULL, -- UUID for file storage
  name VARCHAR(512) NOT NULL, -- Original filename
  size BIGINT NOT NULL, -- File size in bytes
  download_count INTEGER DEFAULT 0,

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_release_attachments_release ON release_attachments(release_id);
CREATE INDEX idx_release_attachments_uuid ON release_attachments(uuid);
CREATE INDEX idx_release_attachments_repo ON release_attachments(repository_id);
```

**Key Features:**
- **UUID-based storage**: Files stored by UUID to prevent naming conflicts
- **Download tracking**: Count how many times each asset is downloaded
- **Multi-file support**: Multiple attachments per release
- **File metadata**: Original filename, size tracking

### 1.3 Add Milestone Reference to Issues (Optional Enhancement)

If implementing milestones alongside releases:

```sql
-- Add milestone_id to issues table
ALTER TABLE issues ADD COLUMN milestone_id INTEGER REFERENCES milestones(id) ON DELETE SET NULL;
CREATE INDEX idx_issues_milestone ON issues(milestone_id);
```

---

## 2. Backend API Implementation

### 2.1 Release Model Types

Create TypeScript types for releases:

**File: `ui/lib/types.ts`** (add to existing file)

```typescript
export interface Release {
  id: number;
  repository_id: number;
  publisher_id: number;
  tag_name: string;
  lower_tag_name: string;
  target: string;
  title: string;
  note: string;
  sha1: string;
  num_commits: number;
  is_draft: boolean;
  is_prerelease: boolean;
  is_tag: boolean;
  original_author?: string;
  original_author_id?: number;
  created_at: string;

  // Joined fields
  publisher?: User;
  attachments?: ReleaseAttachment[];
  rendered_note?: string;
}

export interface ReleaseAttachment {
  id: number;
  repository_id: number;
  release_id: number;
  uploader_id: number;
  uuid: string;
  name: string;
  size: number;
  download_count: number;
  created_at: string;

  // Computed fields
  download_url?: string;
}

export interface CreateReleaseInput {
  tag_name: string;
  target: string; // branch or commit SHA
  title: string;
  note: string;
  is_draft: boolean;
  is_prerelease: boolean;
  tag_message?: string; // Optional annotated tag message
  attachment_uuids?: string[]; // UUIDs of uploaded files
}

export interface UpdateReleaseInput {
  title?: string;
  note?: string;
  is_draft?: boolean;
  is_prerelease?: boolean;
  add_attachment_uuids?: string[];
  remove_attachment_uuids?: string[];
  edit_attachments?: Record<string, string>; // UUID -> new name
}
```

### 2.2 Git Tag Operations

Create helper functions for Git tag operations:

**File: `ui/lib/git.ts`** (add to existing file)

```typescript
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);
const REPOS_DIR = `${process.cwd()}/repos`;

async function run(cmd: string, cwd?: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { cwd });
    return stdout;
  } catch (error: any) {
    return error.stdout || "";
  }
}

export interface GitTag {
  name: string;
  sha: string;
  message: string;
  tagger: {
    name: string;
    email: string;
    date: number; // Unix timestamp
  };
}

/**
 * List all tags in a repository
 */
export async function listTags(user: string, name: string): Promise<GitTag[]> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    // Get tag list with commit info
    const result = await run(`git tag -l --sort=-version:refname`, repoPath);
    const tagNames = result.trim().split("\n").filter(Boolean);

    const tags: GitTag[] = [];
    for (const tagName of tagNames) {
      const tag = await getTag(user, name, tagName);
      if (tag) tags.push(tag);
    }

    return tags;
  } catch {
    return [];
  }
}

/**
 * Get detailed information about a specific tag
 */
export async function getTag(user: string, name: string, tagName: string): Promise<GitTag | null> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    // Try to get annotated tag info first
    const annotatedInfo = await run(`git show "${tagName}" --format="%H|%an|%ae|%at|%B" --no-patch`, repoPath);

    if (annotatedInfo) {
      const [sha, taggerName, taggerEmail, timestamp, ...messageParts] = annotatedInfo.trim().split("|");
      return {
        name: tagName,
        sha: sha || '',
        message: messageParts.join("|").trim(),
        tagger: {
          name: taggerName || '',
          email: taggerEmail || '',
          date: parseInt(timestamp || '0', 10) * 1000,
        },
      };
    }

    // Fallback to lightweight tag
    const sha = await run(`git rev-list -n 1 "${tagName}"`, repoPath);
    return {
      name: tagName,
      sha: sha.trim(),
      message: '',
      tagger: { name: '', email: '', date: 0 },
    };
  } catch {
    return null;
  }
}

/**
 * Create a new Git tag
 */
export async function createTag(
  user: string,
  name: string,
  tagName: string,
  target: string,
  message?: string
): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  if (message) {
    // Create annotated tag
    await run(`git tag -a "${tagName}" "${target}" -m "${message.replace(/"/g, '\\"')}"`, repoPath);
  } else {
    // Create lightweight tag
    await run(`git tag "${tagName}" "${target}"`, repoPath);
  }
}

/**
 * Delete a Git tag
 */
export async function deleteTag(user: string, name: string, tagName: string): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  await run(`git tag -d "${tagName}"`, repoPath);
}

/**
 * Get commit count up to a specific commit
 */
export async function getCommitCount(user: string, name: string, sha: string): Promise<number> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const result = await run(`git rev-list --count "${sha}"`, repoPath);
    return parseInt(result.trim(), 10) || 0;
  } catch {
    return 0;
  }
}

/**
 * Generate release notes from commits between two tags/commits
 */
export async function generateReleaseNotes(
  user: string,
  name: string,
  fromRef: string,
  toRef: string
): Promise<string> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    // Get commits between refs
    const range = fromRef ? `${fromRef}..${toRef}` : toRef;
    const format = "- %s (@%an)"; // Simple format: "- commit message (@author)"
    const result = await run(`git log "${range}" --format="${format}" --no-merges`, repoPath);

    if (!result.trim()) {
      return "No changes in this release.";
    }

    return `## What's Changed\n\n${result.trim()}`;
  } catch {
    return "Failed to generate release notes.";
  }
}

/**
 * Get archive URL for a tag (tarball or zip)
 */
export function getArchiveUrl(user: string, repo: string, tag: string, format: 'tar.gz' | 'zip'): string {
  return `/${user}/${repo}/archive/${tag}.${format}`;
}

/**
 * Create archive file for a tag
 */
export async function createArchive(
  user: string,
  name: string,
  tag: string,
  format: 'tar.gz' | 'zip',
  outputPath: string
): Promise<void> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  if (format === 'tar.gz') {
    await run(`git archive --format=tar.gz --prefix="${name}-${tag}/" "${tag}" > "${outputPath}"`, repoPath);
  } else {
    await run(`git archive --format=zip --prefix="${name}-${tag}/" "${tag}" > "${outputPath}"`, repoPath);
  }
}
```

### 2.3 Release Service Layer

Create business logic for release operations:

**File: `server/lib/releases.ts`** (new file)

```typescript
import { sql } from "../../ui/lib/db";
import type { Release, ReleaseAttachment, CreateReleaseInput, UpdateReleaseInput } from "../../ui/lib/types";
import {
  createTag,
  deleteTag,
  getTag,
  getCommitCount,
  generateReleaseNotes as gitGenerateNotes,
} from "../../ui/lib/git";
import { z } from "zod";

/**
 * List releases for a repository
 */
export async function listReleases(
  repoId: number,
  options: {
    includeDrafts?: boolean;
    includeTags?: boolean;
    limit?: number;
    offset?: number;
  } = {}
): Promise<Release[]> {
  const { includeDrafts = false, includeTags = false, limit = 20, offset = 0 } = options;

  let query = sql`
    SELECT r.*, u.username, u.display_name
    FROM releases r
    LEFT JOIN users u ON r.publisher_id = u.id
    WHERE r.repository_id = ${repoId}
  `;

  if (!includeDrafts) {
    query = sql`${query} AND r.is_draft = false`;
  }

  if (!includeTags) {
    query = sql`${query} AND r.is_tag = false`;
  }

  query = sql`
    ${query}
    ORDER BY r.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  const releases = await query as Release[];

  // Load attachments for each release
  for (const release of releases) {
    release.attachments = await getReleaseAttachments(release.id);
  }

  return releases;
}

/**
 * Get a specific release by tag name
 */
export async function getReleaseByTag(repoId: number, tagName: string): Promise<Release | null> {
  const [release] = await sql`
    SELECT r.*, u.username, u.display_name
    FROM releases r
    LEFT JOIN users u ON r.publisher_id = u.id
    WHERE r.repository_id = ${repoId}
      AND r.lower_tag_name = ${tagName.toLowerCase()}
  ` as Release[];

  if (!release) return null;

  release.attachments = await getReleaseAttachments(release.id);
  return release;
}

/**
 * Get a specific release by ID
 */
export async function getReleaseById(id: number): Promise<Release | null> {
  const [release] = await sql`
    SELECT r.*, u.username, u.display_name
    FROM releases r
    LEFT JOIN users u ON r.publisher_id = u.id
    WHERE r.id = ${id}
  ` as Release[];

  if (!release) return null;

  release.attachments = await getReleaseAttachments(release.id);
  return release;
}

/**
 * Get latest non-draft, non-prerelease release
 */
export async function getLatestRelease(repoId: number): Promise<Release | null> {
  const [release] = await sql`
    SELECT r.*, u.username, u.display_name
    FROM releases r
    LEFT JOIN users u ON r.publisher_id = u.id
    WHERE r.repository_id = ${repoId}
      AND r.is_draft = false
      AND r.is_prerelease = false
      AND r.is_tag = false
    ORDER BY r.created_at DESC
    LIMIT 1
  ` as Release[];

  if (!release) return null;

  release.attachments = await getReleaseAttachments(release.id);
  return release;
}

/**
 * Create a new release
 */
export async function createRelease(
  repoId: number,
  userId: number,
  username: string,
  repoName: string,
  input: CreateReleaseInput
): Promise<Release> {
  // Check if release with this tag already exists
  const existing = await getReleaseByTag(repoId, input.tag_name);
  if (existing && !existing.is_tag) {
    throw new Error(`Release with tag "${input.tag_name}" already exists`);
  }

  // Get or create Git tag
  let tag = await getTag(username, repoName, input.tag_name);

  if (!tag && !input.is_draft) {
    // Create the tag
    await createTag(
      username,
      repoName,
      input.tag_name,
      input.target,
      input.tag_message
    );
    tag = await getTag(username, repoName, input.tag_name);
  }

  const sha = tag?.sha || '';
  const numCommits = sha ? await getCommitCount(username, repoName, sha) : 0;

  // Insert release record
  const [release] = await sql`
    INSERT INTO releases (
      repository_id, publisher_id, tag_name, lower_tag_name,
      target, title, note, sha1, num_commits,
      is_draft, is_prerelease, is_tag
    ) VALUES (
      ${repoId}, ${userId}, ${input.tag_name}, ${input.tag_name.toLowerCase()},
      ${input.target}, ${input.title}, ${input.note}, ${sha}, ${numCommits},
      ${input.is_draft}, ${input.is_prerelease}, false
    )
    RETURNING *
  ` as Release[];

  // Attach uploaded files
  if (input.attachment_uuids && input.attachment_uuids.length > 0) {
    await attachFiles(release.id, input.attachment_uuids);
  }

  return getReleaseById(release.id) as Promise<Release>;
}

/**
 * Update an existing release
 */
export async function updateRelease(
  releaseId: number,
  input: UpdateReleaseInput
): Promise<Release> {
  const updates: string[] = [];
  const values: any[] = [];
  let paramIndex = 1;

  if (input.title !== undefined) {
    updates.push(`title = $${paramIndex++}`);
    values.push(input.title);
  }

  if (input.note !== undefined) {
    updates.push(`note = $${paramIndex++}`);
    values.push(input.note);
  }

  if (input.is_draft !== undefined) {
    updates.push(`is_draft = $${paramIndex++}`);
    values.push(input.is_draft);
  }

  if (input.is_prerelease !== undefined) {
    updates.push(`is_prerelease = $${paramIndex++}`);
    values.push(input.is_prerelease);
  }

  if (updates.length > 0) {
    values.push(releaseId);
    await sql.unsafe(`
      UPDATE releases
      SET ${updates.join(', ')}
      WHERE id = $${paramIndex}
    `, values);
  }

  // Handle attachment changes
  if (input.add_attachment_uuids && input.add_attachment_uuids.length > 0) {
    await attachFiles(releaseId, input.add_attachment_uuids);
  }

  if (input.remove_attachment_uuids && input.remove_attachment_uuids.length > 0) {
    await removeAttachments(input.remove_attachment_uuids);
  }

  if (input.edit_attachments) {
    for (const [uuid, newName] of Object.entries(input.edit_attachments)) {
      await renameAttachment(uuid, newName);
    }
  }

  return getReleaseById(releaseId) as Promise<Release>;
}

/**
 * Delete a release (optionally delete the git tag too)
 */
export async function deleteRelease(
  releaseId: number,
  username: string,
  repoName: string,
  deleteTag: boolean = false
): Promise<void> {
  const release = await getReleaseById(releaseId);
  if (!release) throw new Error("Release not found");

  // Delete attachments
  if (release.attachments && release.attachments.length > 0) {
    const uuids = release.attachments.map(a => a.uuid);
    await removeAttachments(uuids);
  }

  // Delete the release record
  await sql`DELETE FROM releases WHERE id = ${releaseId}`;

  // Optionally delete the git tag
  if (deleteTag) {
    await deleteTag(username, repoName, release.tag_name);
  }
}

/**
 * Generate release notes from commits
 */
export async function generateReleaseNotes(
  username: string,
  repoName: string,
  tagName: string,
  previousTag?: string
): Promise<string> {
  const fromRef = previousTag || '';
  return gitGenerateNotes(username, repoName, fromRef, tagName);
}

// ============================================================================
// Attachment Helpers
// ============================================================================

async function getReleaseAttachments(releaseId: number): Promise<ReleaseAttachment[]> {
  const attachments = await sql`
    SELECT * FROM release_attachments
    WHERE release_id = ${releaseId}
    ORDER BY name ASC
  ` as ReleaseAttachment[];

  // Add download URLs
  for (const att of attachments) {
    att.download_url = `/api/attachments/${att.uuid}`;
  }

  return attachments;
}

async function attachFiles(releaseId: number, uuids: string[]): Promise<void> {
  for (const uuid of uuids) {
    await sql`
      UPDATE release_attachments
      SET release_id = ${releaseId}
      WHERE uuid = ${uuid} AND release_id IS NULL
    `;
  }
}

async function removeAttachments(uuids: string[]): Promise<void> {
  await sql`
    DELETE FROM release_attachments
    WHERE uuid = ANY(${uuids})
  `;

  // TODO: Delete actual files from storage
}

async function renameAttachment(uuid: string, newName: string): Promise<void> {
  await sql`
    UPDATE release_attachments
    SET name = ${newName}
    WHERE uuid = ${uuid}
  `;
}
```

### 2.4 API Routes

Create Hono routes for release operations:

**File: `server/routes/releases.ts`** (new file)

```typescript
import { Hono } from 'hono';
import { z } from 'zod';
import {
  listReleases,
  getReleaseByTag,
  getReleaseById,
  getLatestRelease,
  createRelease,
  updateRelease,
  deleteRelease,
  generateReleaseNotes,
} from '../lib/releases';
import { sql } from '../../ui/lib/db';
import type { Repository, User } from '../../ui/lib/types';

const app = new Hono();

// ============================================================================
// List Releases
// ============================================================================

app.get('/:user/:repo/releases', async (c) => {
  const { user: username, repo: repoName } = c.req.param();
  const includeDrafts = c.req.query('drafts') === 'true';
  const includeTags = c.req.query('tags') === 'true';
  const limit = parseInt(c.req.query('limit') || '20', 10);
  const offset = parseInt(c.req.query('offset') || '0', 10);

  // Get repo
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  ` as Repository[];

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const releases = await listReleases(repo.id, {
    includeDrafts,
    includeTags,
    limit,
    offset,
  });

  return c.json({ releases });
});

// ============================================================================
// Get Single Release
// ============================================================================

app.get('/:user/:repo/releases/:tag', async (c) => {
  const { user: username, repo: repoName, tag } = c.req.param();

  // Get repo
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  ` as Repository[];

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const release = await getReleaseByTag(repo.id, tag);

  if (!release) {
    return c.json({ error: 'Release not found' }, 404);
  }

  return c.json({ release });
});

// ============================================================================
// Get Latest Release
// ============================================================================

app.get('/:user/:repo/releases/latest', async (c) => {
  const { user: username, repo: repoName } = c.req.param();

  // Get repo
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  ` as Repository[];

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const release = await getLatestRelease(repo.id);

  if (!release) {
    return c.json({ error: 'No releases found' }, 404);
  }

  return c.json({ release });
});

// ============================================================================
// Create Release
// ============================================================================

const createReleaseSchema = z.object({
  tag_name: z.string().min(1).max(255),
  target: z.string().min(1),
  title: z.string().min(1).max(255),
  note: z.string().default(''),
  is_draft: z.boolean().default(false),
  is_prerelease: z.boolean().default(false),
  tag_message: z.string().optional(),
  attachment_uuids: z.array(z.string()).optional(),
});

app.post('/:user/:repo/releases', async (c) => {
  const { user: username, repo: repoName } = c.req.param();

  // Parse and validate body
  const body = await c.req.json();
  const result = createReleaseSchema.safeParse(body);

  if (!result.success) {
    return c.json({ error: 'Invalid input', details: result.error }, 400);
  }

  // Get repo
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  ` as Repository[];

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Get user (TODO: use actual authenticated user)
  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];

  try {
    const release = await createRelease(
      repo.id,
      user.id,
      username,
      repoName,
      result.data
    );

    return c.json({ release }, 201);
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// ============================================================================
// Update Release
// ============================================================================

const updateReleaseSchema = z.object({
  title: z.string().max(255).optional(),
  note: z.string().optional(),
  is_draft: z.boolean().optional(),
  is_prerelease: z.boolean().optional(),
  add_attachment_uuids: z.array(z.string()).optional(),
  remove_attachment_uuids: z.array(z.string()).optional(),
  edit_attachments: z.record(z.string()).optional(),
});

app.patch('/:user/:repo/releases/:id', async (c) => {
  const { id } = c.req.param();
  const releaseId = parseInt(id, 10);

  // Parse and validate body
  const body = await c.req.json();
  const result = updateReleaseSchema.safeParse(body);

  if (!result.success) {
    return c.json({ error: 'Invalid input', details: result.error }, 400);
  }

  try {
    const release = await updateRelease(releaseId, result.data);
    return c.json({ release });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// ============================================================================
// Delete Release
// ============================================================================

app.delete('/:user/:repo/releases/:id', async (c) => {
  const { user: username, repo: repoName, id } = c.req.param();
  const releaseId = parseInt(id, 10);
  const deleteTag = c.req.query('delete_tag') === 'true';

  try {
    await deleteRelease(releaseId, username, repoName, deleteTag);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// ============================================================================
// Generate Release Notes
// ============================================================================

app.post('/:user/:repo/releases/generate-notes', async (c) => {
  const { user: username, repo: repoName } = c.req.param();
  const { tag_name, previous_tag } = await c.req.json();

  if (!tag_name) {
    return c.json({ error: 'tag_name is required' }, 400);
  }

  const notes = await generateReleaseNotes(username, repoName, tag_name, previous_tag);
  return c.json({ notes });
});

export default app;
```

**File: `server/routes/index.ts`** (update existing file)

```typescript
import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';
import releases from './releases'; // Add this

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// Mount routes
app.route('/sessions', sessions);
app.route('/session', messages);
app.route('/pty', pty);
app.route('/api', releases); // Add this

export default app;
```

### 2.5 File Upload Handler

Create endpoint for uploading release assets:

**File: `server/routes/uploads.ts`** (new file)

```typescript
import { Hono } from 'hono';
import { writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { sql } from '../../ui/lib/db';

const app = new Hono();

const UPLOAD_DIR = `${process.cwd()}/uploads/attachments`;

// Ensure upload directory exists
if (!existsSync(UPLOAD_DIR)) {
  await mkdir(UPLOAD_DIR, { recursive: true });
}

/**
 * Upload a file for a release
 */
app.post('/upload', async (c) => {
  const formData = await c.req.formData();
  const file = formData.get('file') as File;
  const repoId = formData.get('repository_id');
  const uploaderId = formData.get('uploader_id');

  if (!file || !repoId || !uploaderId) {
    return c.json({ error: 'Missing required fields' }, 400);
  }

  // Generate UUID for file
  const uuid = randomUUID();
  const arrayBuffer = await file.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);

  // Save file to disk (UUID-based path)
  const filePath = `${UPLOAD_DIR}/${uuid.substring(0, 2)}/${uuid.substring(2, 4)}/${uuid}`;
  await mkdir(filePath.substring(0, filePath.lastIndexOf('/')), { recursive: true });
  await writeFile(filePath, buffer);

  // Insert attachment record (not yet linked to a release)
  const [attachment] = await sql`
    INSERT INTO release_attachments (
      repository_id, uploader_id, uuid, name, size
    ) VALUES (
      ${repoId}, ${uploaderId}, ${uuid}, ${file.name}, ${buffer.length}
    )
    RETURNING *
  `;

  return c.json({ attachment });
});

/**
 * Download an attachment
 */
app.get('/attachments/:uuid', async (c) => {
  const { uuid } = c.req.param();

  // Get attachment metadata
  const [attachment] = await sql`
    SELECT * FROM release_attachments WHERE uuid = ${uuid}
  `;

  if (!attachment) {
    return c.json({ error: 'Attachment not found' }, 404);
  }

  // Increment download count
  await sql`
    UPDATE release_attachments
    SET download_count = download_count + 1
    WHERE uuid = ${uuid}
  `;

  // Serve file
  const filePath = `${UPLOAD_DIR}/${uuid.substring(0, 2)}/${uuid.substring(2, 4)}/${uuid}`;

  if (!existsSync(filePath)) {
    return c.json({ error: 'File not found' }, 404);
  }

  const file = Bun.file(filePath);
  return new Response(file, {
    headers: {
      'Content-Disposition': `attachment; filename="${attachment.name}"`,
      'Content-Type': 'application/octet-stream',
      'Content-Length': attachment.size.toString(),
    },
  });
});

export default app;
```

Add to `server/routes/index.ts`:

```typescript
import uploads from './uploads';

// ...

app.route('/api', uploads);
```

---

## 3. Frontend UI Implementation

### 3.1 Releases List Page

**File: `ui/pages/[user]/[repo]/releases/index.astro`** (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import Markdown from "../../../../components/Markdown.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository, Release } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Fetch releases
const releases = await sql`
  SELECT r.*, u.username, u.display_name,
    (SELECT json_agg(ra.*) FROM release_attachments ra WHERE ra.release_id = r.id) as attachments
  FROM releases r
  LEFT JOIN users u ON r.publisher_id = u.id
  WHERE r.repository_id = ${repo.id}
    AND r.is_draft = false
    AND r.is_tag = false
  ORDER BY r.created_at DESC
` as Release[];

const [{ count: issueCount }] = await sql`
  SELECT COUNT(*) as count FROM issues WHERE repository_id = ${repo.id} AND state = 'open'
`;
---

<Layout title={`Releases · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">Releases</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>
      Issues
      {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
    </a>
    <a href={`/${username}/${reponame}/commits/${repo.default_branch}`}>Commits</a>
    <a href={`/${username}/${reponame}/releases`} class="active">Releases</a>
  </nav>

  <div class="container">
    <div class="release-header">
      <h1>Releases</h1>
      <a href={`/${username}/${reponame}/releases/new`} class="btn btn-primary">
        New Release
      </a>
    </div>

    {releases.length === 0 ? (
      <div class="empty-state">
        <p>No releases published yet.</p>
        <a href={`/${username}/${reponame}/releases/new`} class="btn">Create Release</a>
      </div>
    ) : (
      <div class="releases-list">
        {releases.map((release) => (
          <div class="release-item" key={release.id}>
            <div class="release-header-row">
              <div class="release-title-group">
                <h2>
                  <a href={`/${username}/${reponame}/releases/${release.tag_name}`}>
                    {release.title}
                  </a>
                </h2>
                {release.is_prerelease && <span class="badge badge-warning">Pre-release</span>}
              </div>
              <div class="release-meta">
                <span class="tag">{release.tag_name}</span>
                <span class="date">
                  {new Date(release.created_at).toLocaleDateString()}
                </span>
              </div>
            </div>

            {release.note && (
              <div class="release-notes">
                <Markdown content={release.note} />
              </div>
            )}

            {release.attachments && release.attachments.length > 0 && (
              <div class="release-assets">
                <h3>Assets</h3>
                <ul>
                  {release.attachments.map((asset) => (
                    <li key={asset.id}>
                      <a href={`/api/attachments/${asset.uuid}`} download>
                        {asset.name}
                      </a>
                      <span class="asset-meta">
                        {(asset.size / 1024 / 1024).toFixed(2)} MB
                        · {asset.download_count} downloads
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <div class="release-downloads">
              <a href={`/${username}/${reponame}/archive/${release.tag_name}.zip`}>
                Source code (zip)
              </a>
              <a href={`/${username}/${reponame}/archive/${release.tag_name}.tar.gz`}>
                Source code (tar.gz)
              </a>
            </div>
          </div>
        ))}
      </div>
    )}
  </div>
</Layout>

<style>
  .release-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
  }

  .release-header h1 {
    margin: 0;
  }

  .empty-state {
    text-align: center;
    padding: 48px 24px;
    border: 2px solid var(--border);
  }

  .releases-list {
    display: flex;
    flex-direction: column;
    gap: 32px;
  }

  .release-item {
    border: 2px solid var(--border);
    padding: 24px;
  }

  .release-header-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 16px;
  }

  .release-title-group {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .release-title-group h2 {
    margin: 0;
    font-size: 24px;
  }

  .release-meta {
    display: flex;
    gap: 12px;
    align-items: center;
    font-size: 14px;
  }

  .tag {
    background: var(--bg-alt);
    padding: 4px 8px;
    border: 1px solid var(--border);
    font-family: monospace;
  }

  .release-notes {
    margin-bottom: 16px;
    padding: 16px;
    background: var(--bg-alt);
  }

  .release-assets {
    margin-bottom: 16px;
  }

  .release-assets h3 {
    font-size: 16px;
    margin-bottom: 8px;
  }

  .release-assets ul {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  .release-assets li {
    padding: 8px 0;
    border-bottom: 1px solid var(--border);
  }

  .release-assets li:last-child {
    border-bottom: none;
  }

  .asset-meta {
    margin-left: 12px;
    font-size: 12px;
    color: var(--text-muted);
  }

  .release-downloads {
    display: flex;
    gap: 16px;
    font-size: 14px;
  }

  .badge-warning {
    background: #ff9800;
    color: white;
  }
</style>
```

### 3.2 Single Release Page

**File: `ui/pages/[user]/[repo]/releases/[tag].astro`** (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import Markdown from "../../../../components/Markdown.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository, Release } from "../../../../lib/types";

const { user: username, repo: reponame, tag } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Fetch release
const [release] = await sql`
  SELECT r.*, u.username, u.display_name,
    (SELECT json_agg(ra.*) FROM release_attachments ra WHERE ra.release_id = r.id) as attachments
  FROM releases r
  LEFT JOIN users u ON r.publisher_id = u.id
  WHERE r.repository_id = ${repo.id}
    AND r.lower_tag_name = ${tag?.toLowerCase()}
` as Release[];

if (!release) return Astro.redirect("/404");
---

<Layout title={`${release.title} · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/releases`}>Releases</a>
    <span class="sep">/</span>
    <span class="current">{release.tag_name}</span>
  </div>

  <div class="container">
    <div class="release-detail">
      <div class="release-header">
        <div class="release-title-group">
          <h1>{release.title}</h1>
          {release.is_prerelease && <span class="badge badge-warning">Pre-release</span>}
          {release.is_draft && <span class="badge badge-secondary">Draft</span>}
        </div>
        <div class="release-actions">
          <a href={`/${username}/${reponame}/releases/${release.tag_name}/edit`} class="btn btn-sm">
            Edit
          </a>
        </div>
      </div>

      <div class="release-meta">
        <span class="tag">{release.tag_name}</span>
        <span>·</span>
        <span>Published by {release.username}</span>
        <span>·</span>
        <span>{new Date(release.created_at).toLocaleDateString()}</span>
      </div>

      {release.note && (
        <div class="release-notes">
          <Markdown content={release.note} />
        </div>
      )}

      <div class="release-sidebar">
        <div class="sidebar-section">
          <h3>Downloads</h3>
          <ul>
            <li>
              <a href={`/${username}/${reponame}/archive/${release.tag_name}.zip`}>
                Source code (zip)
              </a>
            </li>
            <li>
              <a href={`/${username}/${reponame}/archive/${release.tag_name}.tar.gz`}>
                Source code (tar.gz)
              </a>
            </li>
          </ul>
        </div>

        {release.attachments && release.attachments.length > 0 && (
          <div class="sidebar-section">
            <h3>Assets</h3>
            <ul>
              {release.attachments.map((asset) => (
                <li key={asset.id}>
                  <a href={`/api/attachments/${asset.uuid}`} download>
                    {asset.name}
                  </a>
                  <div class="asset-meta">
                    {(asset.size / 1024 / 1024).toFixed(2)} MB
                    · {asset.download_count} downloads
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </div>
  </div>
</Layout>

<style>
  .release-detail {
    max-width: 1200px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 300px;
    gap: 32px;
  }

  .release-header {
    grid-column: 1 / -1;
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .release-title-group {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .release-title-group h1 {
    margin: 0;
    font-size: 32px;
  }

  .release-meta {
    grid-column: 1 / -1;
    display: flex;
    gap: 8px;
    font-size: 14px;
    color: var(--text-muted);
    margin-bottom: 24px;
  }

  .tag {
    background: var(--bg-alt);
    padding: 4px 8px;
    border: 1px solid var(--border);
    font-family: monospace;
  }

  .release-notes {
    grid-column: 1;
    padding: 24px;
    background: var(--bg-alt);
    border: 2px solid var(--border);
  }

  .release-sidebar {
    grid-column: 2;
    display: flex;
    flex-direction: column;
    gap: 24px;
  }

  .sidebar-section {
    border: 2px solid var(--border);
    padding: 16px;
  }

  .sidebar-section h3 {
    margin: 0 0 12px 0;
    font-size: 16px;
  }

  .sidebar-section ul {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  .sidebar-section li {
    padding: 8px 0;
    border-bottom: 1px solid var(--border);
  }

  .sidebar-section li:last-child {
    border-bottom: none;
  }

  .asset-meta {
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 4px;
  }

  .badge-warning {
    background: #ff9800;
    color: white;
  }

  .badge-secondary {
    background: #666;
    color: white;
  }
</style>
```

### 3.3 Create/Edit Release Page

**File: `ui/pages/[user]/[repo]/releases/new.astro`** (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { listTags } from "../../../../lib/git";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Get existing tags
const tags = await listTags(username!, reponame!);
---

<Layout title={`New Release · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/releases`}>Releases</a>
    <span class="sep">/</span>
    <span class="current">New</span>
  </div>

  <div class="container">
    <h1>Create a New Release</h1>

    <form id="release-form" class="release-form">
      <div class="form-row">
        <div class="form-group">
          <label for="tag_name">Tag</label>
          <input
            type="text"
            id="tag_name"
            name="tag_name"
            required
            placeholder="v1.0.0"
            list="existing-tags"
          />
          <datalist id="existing-tags">
            {tags.map((tag) => <option value={tag.name} />)}
          </datalist>
          <small>Choose an existing tag or create a new one</small>
        </div>

        <div class="form-group">
          <label for="target">Target</label>
          <input
            type="text"
            id="target"
            name="target"
            required
            value={repo.default_branch}
            placeholder="main"
          />
          <small>Branch or commit SHA</small>
        </div>
      </div>

      <div class="form-group">
        <label for="title">Release Title</label>
        <input
          type="text"
          id="title"
          name="title"
          required
          placeholder="v1.0.0 - Initial Release"
        />
      </div>

      <div class="form-group">
        <label for="note">Release Notes</label>
        <textarea
          id="note"
          name="note"
          rows="15"
          placeholder="Describe this release..."
        ></textarea>
        <button type="button" id="generate-notes" class="btn btn-sm">
          Auto-generate from commits
        </button>
      </div>

      <div class="form-group">
        <label>Attachments</label>
        <input
          type="file"
          id="file-upload"
          multiple
          accept="*/*"
        />
        <div id="attachments-list"></div>
      </div>

      <div class="form-group checkbox-group">
        <label>
          <input type="checkbox" id="is_prerelease" name="is_prerelease" />
          This is a pre-release
        </label>
        <small>Mark as unstable (alpha, beta, RC)</small>
      </div>

      <div class="form-group checkbox-group">
        <label>
          <input type="checkbox" id="is_draft" name="is_draft" />
          Save as draft
        </label>
        <small>Don't publish this release yet</small>
      </div>

      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Publish Release</button>
        <a href={`/${username}/${reponame}/releases`} class="btn">Cancel</a>
      </div>
    </form>
  </div>
</Layout>

<script>
  const form = document.getElementById('release-form') as HTMLFormElement;
  const generateBtn = document.getElementById('generate-notes') as HTMLButtonElement;
  const fileInput = document.getElementById('file-upload') as HTMLInputElement;
  const attachmentsList = document.getElementById('attachments-list') as HTMLDivElement;

  const uploadedFiles: Array<{ uuid: string; name: string; size: number }> = [];

  // File upload handling
  fileInput?.addEventListener('change', async (e) => {
    const files = (e.target as HTMLInputElement).files;
    if (!files) return;

    for (const file of Array.from(files)) {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('repository_id', '{repo.id}');
      formData.append('uploader_id', '{user.id}');

      try {
        const res = await fetch('/api/upload', {
          method: 'POST',
          body: formData,
        });

        const data = await res.json();
        uploadedFiles.push(data.attachment);

        // Update UI
        const item = document.createElement('div');
        item.className = 'attachment-item';
        item.innerHTML = `
          <span>${file.name}</span>
          <span>${(file.size / 1024 / 1024).toFixed(2)} MB</span>
          <button type="button" data-uuid="${data.attachment.uuid}">Remove</button>
        `;
        attachmentsList.appendChild(item);

        // Remove handler
        item.querySelector('button')?.addEventListener('click', (e) => {
          const uuid = (e.target as HTMLButtonElement).dataset.uuid;
          const index = uploadedFiles.findIndex(f => f.uuid === uuid);
          if (index > -1) {
            uploadedFiles.splice(index, 1);
            item.remove();
          }
        });
      } catch (error) {
        console.error('Upload failed:', error);
        alert('File upload failed');
      }
    }

    // Clear input
    fileInput.value = '';
  });

  // Generate release notes
  generateBtn?.addEventListener('click', async () => {
    const tagName = (document.getElementById('tag_name') as HTMLInputElement).value;
    if (!tagName) {
      alert('Please enter a tag name first');
      return;
    }

    generateBtn.disabled = true;
    generateBtn.textContent = 'Generating...';

    try {
      const res = await fetch(`/api/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/releases/generate-notes`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tag_name: tagName }),
      });

      const data = await res.json();
      (document.getElementById('note') as HTMLTextAreaElement).value = data.notes;
    } catch (error) {
      console.error('Failed to generate notes:', error);
      alert('Failed to generate release notes');
    } finally {
      generateBtn.disabled = false;
      generateBtn.textContent = 'Auto-generate from commits';
    }
  });

  // Form submission
  form?.addEventListener('submit', async (e) => {
    e.preventDefault();

    const formData = new FormData(form);
    const data = {
      tag_name: formData.get('tag_name'),
      target: formData.get('target'),
      title: formData.get('title'),
      note: formData.get('note'),
      is_prerelease: formData.get('is_prerelease') === 'on',
      is_draft: formData.get('is_draft') === 'on',
      attachment_uuids: uploadedFiles.map(f => f.uuid),
    };

    try {
      const res = await fetch(`/api/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/releases`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (res.ok) {
        window.location.href = `/${window.location.pathname.split('/')[1]}/${window.location.pathname.split('/')[2]}/releases`;
      } else {
        const error = await res.json();
        alert(`Error: ${error.error}`);
      }
    } catch (error) {
      console.error('Failed to create release:', error);
      alert('Failed to create release');
    }
  });
</script>

<style>
  .container {
    max-width: 900px;
    margin: 0 auto;
  }

  .release-form {
    margin-top: 24px;
  }

  .form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
  }

  .form-group {
    margin-bottom: 24px;
  }

  .form-group label {
    display: block;
    font-weight: bold;
    margin-bottom: 8px;
  }

  .form-group input,
  .form-group textarea {
    width: 100%;
    padding: 8px;
    border: 2px solid var(--border);
    background: var(--bg);
    color: var(--text);
    font-family: inherit;
  }

  .form-group small {
    display: block;
    margin-top: 4px;
    font-size: 12px;
    color: var(--text-muted);
  }

  .checkbox-group label {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: normal;
  }

  .checkbox-group input[type="checkbox"] {
    width: auto;
  }

  .attachment-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px;
    border: 1px solid var(--border);
    margin-top: 8px;
  }

  .form-actions {
    display: flex;
    gap: 12px;
    margin-top: 24px;
  }
</style>
```

### 3.4 Update Repository Navigation

**File: `ui/pages/[user]/[repo]/index.astro`** (update existing file)

Add releases link to the navigation:

```astro
<nav class="repo-nav">
  <a href={`/${username}/${reponame}`} class="active">Code</a>
  <a href={`/${username}/${reponame}/issues`}>
    Issues
    {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
  </a>
  <a href={`/${username}/${reponame}/commits/${defaultBranch}`}>Commits</a>
  <a href={`/${username}/${reponame}/releases`}>Releases</a> <!-- Add this -->
</nav>
```

---

## 4. Archive Download Handler

Add route to generate and serve archive files:

**File: `server/routes/archives.ts`** (new file)

```typescript
import { Hono } from 'hono';
import { createArchive } from '../../ui/lib/git';
import { sql } from '../../ui/lib/db';
import { existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import type { Repository } from '../../ui/lib/types';

const app = new Hono();

const ARCHIVE_DIR = `${process.cwd()}/tmp/archives`;

// Ensure archive directory exists
if (!existsSync(ARCHIVE_DIR)) {
  await mkdir(ARCHIVE_DIR, { recursive: true });
}

/**
 * Download repository archive (zip or tar.gz)
 */
app.get('/:user/:repo/archive/:tag.:format', async (c) => {
  const { user: username, repo: repoName, tag, format } = c.req.param();

  if (format !== 'zip' && format !== 'tar.gz') {
    return c.json({ error: 'Invalid format' }, 400);
  }

  // Get repo
  const [repo] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  ` as Repository[];

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Generate archive
  const archivePath = `${ARCHIVE_DIR}/${repoName}-${tag}.${format}`;

  try {
    await createArchive(username, repoName, tag, format as 'tar.gz' | 'zip', archivePath);

    const file = Bun.file(archivePath);
    return new Response(file, {
      headers: {
        'Content-Disposition': `attachment; filename="${repoName}-${tag}.${format}"`,
        'Content-Type': format === 'zip' ? 'application/zip' : 'application/gzip',
      },
    });
  } catch (error) {
    console.error('Archive generation failed:', error);
    return c.json({ error: 'Failed to generate archive' }, 500);
  }
});

export default app;
```

Add to `server/routes/index.ts`:

```typescript
import archives from './archives';

// ...

app.route('/', archives);
```

---

## 5. Implementation Checklist

### Phase 1: Database & Core Backend

- [ ] Create database migration for `releases` table
- [ ] Create database migration for `release_attachments` table
- [ ] Add TypeScript types to `ui/lib/types.ts`
- [ ] Implement Git tag operations in `ui/lib/git.ts`:
  - [ ] `listTags()`
  - [ ] `getTag()`
  - [ ] `createTag()`
  - [ ] `deleteTag()`
  - [ ] `getCommitCount()`
  - [ ] `generateReleaseNotes()`
  - [ ] `createArchive()`
- [ ] Test Git operations with sample repository

### Phase 2: Release Service Layer

- [ ] Create `server/lib/releases.ts`
- [ ] Implement `listReleases()`
- [ ] Implement `getReleaseByTag()`
- [ ] Implement `getReleaseById()`
- [ ] Implement `getLatestRelease()`
- [ ] Implement `createRelease()`
- [ ] Implement `updateRelease()`
- [ ] Implement `deleteRelease()`
- [ ] Implement `generateReleaseNotes()`
- [ ] Test all service functions

### Phase 3: API Routes

- [ ] Create `server/routes/releases.ts`
- [ ] Implement `GET /:user/:repo/releases` (list releases)
- [ ] Implement `GET /:user/:repo/releases/:tag` (get single release)
- [ ] Implement `GET /:user/:repo/releases/latest` (get latest release)
- [ ] Implement `POST /:user/:repo/releases` (create release)
- [ ] Implement `PATCH /:user/:repo/releases/:id` (update release)
- [ ] Implement `DELETE /:user/:repo/releases/:id` (delete release)
- [ ] Implement `POST /:user/:repo/releases/generate-notes` (generate notes)
- [ ] Add routes to `server/routes/index.ts`
- [ ] Test all API endpoints with curl/Postman

### Phase 4: File Upload System

- [ ] Create `server/routes/uploads.ts`
- [ ] Implement `POST /upload` (upload file)
- [ ] Implement `GET /attachments/:uuid` (download file)
- [ ] Create upload directory structure
- [ ] Implement UUID-based file storage
- [ ] Test file upload/download flow

### Phase 5: Archive Downloads

- [ ] Create `server/routes/archives.ts`
- [ ] Implement `GET /:user/:repo/archive/:tag.:format`
- [ ] Test zip archive generation
- [ ] Test tar.gz archive generation

### Phase 6: Frontend Pages

- [ ] Create `ui/pages/[user]/[repo]/releases/index.astro` (releases list)
- [ ] Create `ui/pages/[user]/[repo]/releases/[tag].astro` (single release)
- [ ] Create `ui/pages/[user]/[repo]/releases/new.astro` (create release)
- [ ] Create `ui/pages/[user]/[repo]/releases/edit/[tag].astro` (edit release)
- [ ] Update repository navigation to include releases link
- [ ] Style all pages to match brutalist design

### Phase 7: Client-Side Interactions

- [ ] Implement file upload UI with progress
- [ ] Implement auto-generate release notes button
- [ ] Implement attachment removal
- [ ] Implement form validation
- [ ] Add loading states for async operations

### Phase 8: Testing & Polish

- [ ] Test creating release with new tag
- [ ] Test creating release with existing tag
- [ ] Test draft releases
- [ ] Test pre-releases
- [ ] Test file attachments
- [ ] Test auto-generated release notes
- [ ] Test archive downloads
- [ ] Test release editing
- [ ] Test release deletion
- [ ] Add error handling for edge cases
- [ ] Optimize query performance
- [ ] Add proper error messages

### Phase 9: Optional Enhancements

- [ ] Add RSS feed for releases
- [ ] Add release comparison view
- [ ] Add webhook notifications for new releases
- [ ] Add release analytics (download counts, etc.)
- [ ] Add GPG signature verification
- [ ] Add changelog generation from conventional commits
- [ ] Add semver validation
- [ ] Add protected tags (prevent deletion)

---

## 6. Reference: Gitea Implementation Patterns

### Release Model Structure (TypeScript Translation)

From `gitea/models/repo/release.go`:

```typescript
interface Release {
  // Primary fields
  id: number;
  repository_id: number;
  publisher_id: number;

  // Tag information
  tag_name: string;
  lower_tag_name: string; // For case-insensitive queries
  target: string; // Branch or commit to tag

  // Release metadata
  title: string;
  note: string; // Markdown content

  // Git information
  sha1: string; // Commit SHA
  num_commits: number;

  // States
  is_draft: boolean;
  is_prerelease: boolean;
  is_tag: boolean; // True if just a tag, not a full release

  // Migration fields
  original_author?: string;
  original_author_id?: number;

  created_at: Date;
}
```

### Tag Creation Logic (from `gitea/services/release/release.go`)

```typescript
async function createTag(
  gitRepo: GitRepository,
  release: Release,
  message: string
): Promise<boolean> {
  let created = false;

  // Only create tag if not a draft
  if (!release.is_draft) {
    // Check if tag exists
    const tagExists = await gitRepo.tagExists(release.tag_name);

    if (!tagExists) {
      // Get commit to tag
      const commit = await gitRepo.getCommit(release.target);

      // Create annotated or lightweight tag
      if (message) {
        await gitRepo.createAnnotatedTag(release.tag_name, message, commit.id);
      } else {
        await gitRepo.createTag(release.tag_name, commit.id);
      }

      created = true;
      release.lower_tag_name = release.tag_name.toLowerCase();
    }

    // Get tag commit and update release
    const tagCommit = await gitRepo.getTagCommit(release.tag_name);
    release.sha1 = tagCommit.id;
    release.num_commits = await gitRepo.commitsCount(tagCommit.id);
  } else {
    release.created_at = new Date();
  }

  return created;
}
```

### Attachment Download URL Pattern (from `gitea/models/repo/attachment.go`)

```typescript
function getAttachmentDownloadUrl(
  repoHtmlUrl: string,
  tagName: string,
  attachmentName: string
): string {
  // Pattern: /repo/releases/download/tag-name/filename
  return `${repoHtmlUrl}/releases/download/${encodeURIComponent(tagName)}/${encodeURIComponent(attachmentName)}`;
}
```

### Archive URL Patterns (from `gitea/models/repo/release.go`)

```typescript
function getArchiveUrls(repoHtmlUrl: string, tagName: string) {
  return {
    zip: `${repoHtmlUrl}/archive/${encodeURIComponent(tagName)}.zip`,
    tarGz: `${repoHtmlUrl}/archive/${encodeURIComponent(tagName)}.tar.gz`,
  };
}
```

---

## 7. Key Design Decisions

### 7.1 Tag vs Release Distinction

- **Tags**: Lightweight Git references, minimal metadata
- **Releases**: Rich objects with notes, attachments, draft/prerelease states
- A tag can be converted to a release by adding notes/attachments
- Deleting a release can optionally preserve the tag

### 7.2 Draft Releases

- Draft releases don't create Git tags immediately
- Useful for preparing releases before announcement
- Only visible to users with write access

### 7.3 Pre-releases

- Mark releases as unstable (alpha, beta, RC)
- Don't show as "latest" release
- Helps manage version expectations

### 7.4 Attachment Storage

- UUID-based storage prevents naming conflicts
- Two-level directory structure (`/ab/cd/abcd...uuid`)
- Metadata stored in database, files on disk
- Download count tracking

### 7.5 Auto-generated Release Notes

- Parse commits between tags
- Simple format: `- commit message (@author)`
- Can be edited before publishing

---

## 8. Testing Strategy

### Unit Tests

```typescript
// Test tag creation
test("createTag should create lightweight tag", async () => {
  await createTag("user", "repo", "v1.0.0", "main");
  const tag = await getTag("user", "repo", "v1.0.0");
  expect(tag).not.toBeNull();
  expect(tag?.name).toBe("v1.0.0");
});

// Test release creation
test("createRelease should create release with attachments", async () => {
  const release = await createRelease(1, 1, "user", "repo", {
    tag_name: "v1.0.0",
    target: "main",
    title: "First Release",
    note: "Initial version",
    is_draft: false,
    is_prerelease: false,
    attachment_uuids: ["uuid1", "uuid2"],
  });

  expect(release.tag_name).toBe("v1.0.0");
  expect(release.attachments).toHaveLength(2);
});
```

### Integration Tests

```bash
# Test release creation API
curl -X POST http://localhost:3000/api/user/repo/releases \
  -H "Content-Type: application/json" \
  -d '{
    "tag_name": "v1.0.0",
    "target": "main",
    "title": "First Release",
    "note": "Initial version",
    "is_draft": false,
    "is_prerelease": false
  }'

# Test archive download
curl -O http://localhost:3000/user/repo/archive/v1.0.0.zip
```

---

## 9. Deployment Notes

### Storage Requirements

- Attachment storage: `${process.cwd()}/uploads/attachments/`
- Archive cache: `${process.cwd()}/tmp/archives/`
- Ensure sufficient disk space for large binaries

### Performance Considerations

- Cache archive files (TTL: 1 hour)
- Index `releases.lower_tag_name` for fast lookups
- Paginate release lists for large repositories
- Stream large file downloads

### Security

- Validate file types for attachments
- Limit attachment size (default: 100MB)
- Sanitize markdown in release notes
- Validate tag names (no shell injection)

---

## 10. Future Enhancements

1. **Release Analytics**: Track downloads, views, engagement
2. **Automated Releases**: CI/CD integration for automatic releases
3. **Changelog Generation**: Parse conventional commits for changelogs
4. **GPG Signatures**: Verify signed tags
5. **Protected Tags**: Prevent accidental deletion of important tags
6. **Release Templates**: Predefined release note templates
7. **Multi-platform Builds**: Upload platform-specific binaries
8. **Release Notifications**: Email/webhook notifications for new releases

---

This completes the Tags & Releases feature implementation guide. Follow the checklist sequentially, testing each component before moving to the next phase.
