# File Operations Implementation

## Overview

Implement comprehensive web-based file operations for Plue repositories, allowing users to create, edit, delete, upload, and download files directly through the browser without needing to clone the repository locally.

**Scope:**
- Create new files via web UI with commit message
- Edit existing files inline with syntax highlighting
- Delete files and directories with commit
- Upload single and multiple files
- Raw file download
- Archive download (zip/tar.gz of entire repository or subdirectory)
- Git commit creation from all web operations
- Breadcrumb navigation for file paths
- Commit to existing branch or create new branch

**Out of scope (future features):**
- Web-based merge conflict resolution
- LFS (Large File Storage) support
- File diffing in editor
- Protected file patterns
- GPG commit signing
- Cherry-pick/patch operations

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL
- **Validation**: Zod v4
- **Git Operations**: Direct git commands via `exec` (like existing `ui/lib/git.ts`)

## Architecture Overview

Plue uses bare git repositories stored in `/repos/{user}/{repo}` and performs operations by:
1. Creating temporary working directories
2. Cloning/initializing the target branch
3. Making changes to files
4. Staging changes with `git add`
5. Creating commits with proper author/committer metadata
6. Pushing back to the bare repository
7. Cleaning up temporary directory

This mirrors Gitea's `TemporaryUploadRepository` pattern.

## Database Schema Changes

No database schema changes required. All file operations result in git commits tracked by the git repository itself. The existing `repositories` table already has all needed fields:

```sql
-- Already exists in db/schema.sql
CREATE TABLE IF NOT EXISTS repositories (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT true,
  default_branch VARCHAR(255) DEFAULT 'main',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, name)
);
```

## Backend Implementation

### 1. Git Operations Library Enhancement

**File**: `/Users/williamcory/plue/ui/lib/git.ts`

Add new functions to existing git library:

```typescript
import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";

const execAsync = promisify(exec);
const REPOS_DIR = `${process.cwd()}/repos`;

/**
 * Create a temporary working directory for file operations
 */
async function createTempRepo(user: string, name: string, branch: string): Promise<string> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  const tempDir = `/tmp/plue-edit-${Date.now()}-${Math.random().toString(36).slice(2)}`;

  await mkdir(tempDir, { recursive: true });

  // Clone specific branch to temp directory
  try {
    await run(`git clone --single-branch --branch ${branch} "${repoPath}" "${tempDir}"`);
  } catch (error) {
    // If branch doesn't exist, clone default and create branch
    await run(`git clone "${repoPath}" "${tempDir}"`);
    await run(`git checkout -b ${branch}`, tempDir);
  }

  return tempDir;
}

/**
 * Cleanup temporary directory
 */
async function cleanupTempRepo(tempDir: string): Promise<void> {
  if (tempDir.startsWith('/tmp/plue-edit-')) {
    await rm(tempDir, { recursive: true, force: true });
  }
}

/**
 * Create or update a file in the repository
 */
export async function createOrUpdateFile(
  user: string,
  name: string,
  options: {
    branch: string;
    filePath: string;
    content: string;
    message: string;
    authorName: string;
    authorEmail: string;
    newBranch?: string; // If provided, create new branch from current
  }
): Promise<{ commitHash: string; branch: string }> {
  const targetBranch = options.newBranch || options.branch;
  const tempDir = await createTempRepo(user, name, options.branch);

  try {
    // If creating new branch, check out new branch
    if (options.newBranch) {
      await run(`git checkout -b ${options.newBranch}`, tempDir);
    }

    // Clean the file path (prevent directory traversal)
    const cleanPath = cleanGitPath(options.filePath);
    if (!cleanPath) {
      throw new Error(`Invalid file path: ${options.filePath}`);
    }

    const fullPath = `${tempDir}/${cleanPath}`;
    const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'));

    // Create parent directories if needed
    if (dirPath !== tempDir) {
      await mkdir(dirPath, { recursive: true });
    }

    // Write file content
    await writeFile(fullPath, options.content, 'utf-8');

    // Stage the file
    await run(`git add "${cleanPath}"`, tempDir);

    // Configure git user for this commit
    await run(`git config user.name "${options.authorName}"`, tempDir);
    await run(`git config user.email "${options.authorEmail}"`, tempDir);

    // Create commit
    await run(`git commit -m "${options.message.replace(/"/g, '\\"')}"`, tempDir);

    // Get commit hash
    const { stdout: commitHash } = await execAsync('git rev-parse HEAD', { cwd: tempDir });

    // Push to bare repository
    const repoPath = `${REPOS_DIR}/${user}/${name}`;
    await run(`git push origin ${targetBranch}`, tempDir);

    return {
      commitHash: commitHash.trim(),
      branch: targetBranch
    };
  } finally {
    await cleanupTempRepo(tempDir);
  }
}

/**
 * Delete a file or directory from the repository
 */
export async function deleteFile(
  user: string,
  name: string,
  options: {
    branch: string;
    filePath: string;
    message: string;
    authorName: string;
    authorEmail: string;
    recursive?: boolean; // For directories
    newBranch?: string;
  }
): Promise<{ commitHash: string; branch: string }> {
  const targetBranch = options.newBranch || options.branch;
  const tempDir = await createTempRepo(user, name, options.branch);

  try {
    if (options.newBranch) {
      await run(`git checkout -b ${options.newBranch}`, tempDir);
    }

    const cleanPath = cleanGitPath(options.filePath);
    if (!cleanPath) {
      throw new Error(`Invalid file path: ${options.filePath}`);
    }

    // Remove file or directory
    const rmFlag = options.recursive ? '-r' : '';
    await run(`git rm ${rmFlag} "${cleanPath}"`, tempDir);

    // Configure git user
    await run(`git config user.name "${options.authorName}"`, tempDir);
    await run(`git config user.email "${options.authorEmail}"`, tempDir);

    // Create commit
    await run(`git commit -m "${options.message.replace(/"/g, '\\"')}"`, tempDir);

    const { stdout: commitHash } = await execAsync('git rev-parse HEAD', { cwd: tempDir });

    // Push to bare repository
    await run(`git push origin ${targetBranch}`, tempDir);

    return {
      commitHash: commitHash.trim(),
      branch: targetBranch
    };
  } finally {
    await cleanupTempRepo(tempDir);
  }
}

/**
 * Upload multiple files to the repository
 */
export async function uploadFiles(
  user: string,
  name: string,
  options: {
    branch: string;
    targetPath: string; // Directory path where files will be uploaded
    files: Array<{ name: string; content: Buffer | string }>;
    message: string;
    authorName: string;
    authorEmail: string;
    newBranch?: string;
  }
): Promise<{ commitHash: string; branch: string }> {
  const targetBranch = options.newBranch || options.branch;
  const tempDir = await createTempRepo(user, name, options.branch);

  try {
    if (options.newBranch) {
      await run(`git checkout -b ${options.newBranch}`, tempDir);
    }

    const cleanTargetPath = cleanGitPath(options.targetPath) || '';
    const targetDir = cleanTargetPath ? `${tempDir}/${cleanTargetPath}` : tempDir;

    // Create target directory if needed
    if (cleanTargetPath) {
      await mkdir(targetDir, { recursive: true });
    }

    // Write all files
    for (const file of options.files) {
      const cleanFileName = cleanGitPath(file.name);
      if (!cleanFileName) continue;

      const fullPath = `${targetDir}/${cleanFileName}`;
      await writeFile(fullPath, file.content);

      const relativePath = cleanTargetPath
        ? `${cleanTargetPath}/${cleanFileName}`
        : cleanFileName;
      await run(`git add "${relativePath}"`, tempDir);
    }

    // Configure git user
    await run(`git config user.name "${options.authorName}"`, tempDir);
    await run(`git config user.email "${options.authorEmail}"`, tempDir);

    // Create commit
    await run(`git commit -m "${options.message.replace(/"/g, '\\"')}"`, tempDir);

    const { stdout: commitHash } = await execAsync('git rev-parse HEAD', { cwd: tempDir });

    // Push to bare repository
    await run(`git push origin ${targetBranch}`, tempDir);

    return {
      commitHash: commitHash.trim(),
      branch: targetBranch
    };
  } finally {
    await cleanupTempRepo(tempDir);
  }
}

/**
 * Create a repository archive (zip or tar.gz)
 */
export async function createArchive(
  user: string,
  name: string,
  ref: string,
  format: 'zip' | 'tar.gz',
  prefix?: string // Optional prefix for archive entries
): Promise<Buffer> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;

  const prefixArg = prefix ? `--prefix=${prefix}/` : '';
  const formatArg = format === 'zip' ? 'zip' : 'tar.gz';

  const { stdout } = await execAsync(
    `git archive ${prefixArg} --format=${formatArg} ${ref}`,
    { cwd: repoPath, encoding: 'buffer', maxBuffer: 100 * 1024 * 1024 } // 100MB max
  );

  return stdout as Buffer;
}

/**
 * Get raw file content as buffer (for downloads)
 */
export async function getRawFileContent(
  user: string,
  name: string,
  ref: string,
  path: string
): Promise<Buffer | null> {
  const repoPath = `${REPOS_DIR}/${user}/${name}`;
  try {
    const { stdout } = await execAsync(
      `git show "${ref}:${path}"`,
      { cwd: repoPath, encoding: 'buffer', maxBuffer: 100 * 1024 * 1024 }
    );
    return stdout as Buffer;
  } catch {
    return null;
  }
}

/**
 * Clean git path to prevent directory traversal and invalid paths
 * Returns empty string if path is invalid
 */
function cleanGitPath(path: string): string {
  if (!path) return '';

  // Remove leading/trailing slashes and dots
  path = path.trim().replace(/^[\/\.]+/, '').replace(/[\/\.]+$/, '');

  // Check for directory traversal
  if (path.includes('..') || path.includes('/.git/') || path === '.git') {
    return '';
  }

  // Normalize multiple slashes
  path = path.replace(/\/+/g, '/');

  return path;
}
```

### 2. API Routes

**File**: `/Users/williamcory/plue/server/routes/files.ts` (new file)

```typescript
import { Hono } from 'hono';
import { z } from 'zod';
import { sql } from '../../ui/lib/db';
import {
  createOrUpdateFile,
  deleteFile,
  uploadFiles,
  createArchive,
  getRawFileContent,
  repoExists
} from '../../ui/lib/git';

const app = new Hono();

// Validation schemas
const FileOperationSchema = z.object({
  branch: z.string().min(1).max(100),
  filePath: z.string().min(1).max(500),
  content: z.string().optional(),
  message: z.string().min(1).max(500),
  authorName: z.string().min(1).max(100),
  authorEmail: z.string().email(),
  newBranch: z.string().min(1).max(100).optional(),
});

const UploadSchema = z.object({
  branch: z.string().min(1).max(100),
  targetPath: z.string().max(500),
  message: z.string().min(1).max(500),
  authorName: z.string().min(1).max(100),
  authorEmail: z.string().email(),
  newBranch: z.string().min(1).max(100).optional(),
  files: z.array(z.object({
    name: z.string().min(1).max(255),
    content: z.string(), // base64 encoded
  })).min(1).max(100),
});

// Create or update file
app.post('/:user/:repo/files', async (c) => {
  const { user, repo } = c.req.param();

  // Check if repo exists
  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const body = await c.req.json();
  const validation = FileOperationSchema.safeParse(body);

  if (!validation.success) {
    return c.json({ error: 'Invalid request', details: validation.error }, 400);
  }

  const data = validation.data;

  try {
    const result = await createOrUpdateFile(user, repo, {
      branch: data.branch,
      filePath: data.filePath,
      content: data.content || '',
      message: data.message,
      authorName: data.authorName,
      authorEmail: data.authorEmail,
      newBranch: data.newBranch,
    });

    return c.json({
      success: true,
      commit: result.commitHash,
      branch: result.branch,
    });
  } catch (error: any) {
    console.error('File create/update error:', error);
    return c.json({ error: error.message || 'Failed to create/update file' }, 500);
  }
});

// Delete file
app.delete('/:user/:repo/files', async (c) => {
  const { user, repo } = c.req.param();

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const body = await c.req.json();
  const validation = FileOperationSchema.omit({ content: true }).extend({
    recursive: z.boolean().optional(),
  }).safeParse(body);

  if (!validation.success) {
    return c.json({ error: 'Invalid request', details: validation.error }, 400);
  }

  const data = validation.data;

  try {
    const result = await deleteFile(user, repo, {
      branch: data.branch,
      filePath: data.filePath,
      message: data.message,
      authorName: data.authorName,
      authorEmail: data.authorEmail,
      newBranch: data.newBranch,
      recursive: data.recursive,
    });

    return c.json({
      success: true,
      commit: result.commitHash,
      branch: result.branch,
    });
  } catch (error: any) {
    console.error('File delete error:', error);
    return c.json({ error: error.message || 'Failed to delete file' }, 500);
  }
});

// Upload files
app.post('/:user/:repo/upload', async (c) => {
  const { user, repo } = c.req.param();

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const body = await c.req.json();
  const validation = UploadSchema.safeParse(body);

  if (!validation.success) {
    return c.json({ error: 'Invalid request', details: validation.error }, 400);
  }

  const data = validation.data;

  try {
    // Decode base64 file contents
    const files = data.files.map(f => ({
      name: f.name,
      content: Buffer.from(f.content, 'base64'),
    }));

    const result = await uploadFiles(user, repo, {
      branch: data.branch,
      targetPath: data.targetPath,
      files,
      message: data.message,
      authorName: data.authorName,
      authorEmail: data.authorEmail,
      newBranch: data.newBranch,
    });

    return c.json({
      success: true,
      commit: result.commitHash,
      branch: result.branch,
      filesUploaded: files.length,
    });
  } catch (error: any) {
    console.error('File upload error:', error);
    return c.json({ error: error.message || 'Failed to upload files' }, 500);
  }
});

// Download raw file
app.get('/:user/:repo/raw/:ref/*', async (c) => {
  const { user, repo, ref } = c.req.param();
  const filePath = c.req.param('*'); // Wildcard captures rest of path

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const content = await getRawFileContent(user, repo, ref, filePath);

    if (!content) {
      return c.json({ error: 'File not found' }, 404);
    }

    // Get filename from path
    const filename = filePath.split('/').pop() || 'file';

    // Set headers for download
    c.header('Content-Type', 'application/octet-stream');
    c.header('Content-Disposition', `attachment; filename="${filename}"`);

    return c.body(content);
  } catch (error: any) {
    console.error('File download error:', error);
    return c.json({ error: 'Failed to download file' }, 500);
  }
});

// Download repository archive
app.get('/:user/:repo/archive/:ref.:format', async (c) => {
  const { user, repo, ref, format } = c.req.param();

  if (format !== 'zip' && format !== 'tar.gz') {
    return c.json({ error: 'Invalid archive format. Use zip or tar.gz' }, 400);
  }

  const exists = await repoExists(user, repo);
  if (!exists) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  try {
    const archive = await createArchive(user, repo, ref, format, `${repo}-${ref}`);

    const contentType = format === 'zip'
      ? 'application/zip'
      : 'application/gzip';

    const filename = `${repo}-${ref}.${format}`;

    c.header('Content-Type', contentType);
    c.header('Content-Disposition', `attachment; filename="${filename}"`);

    return c.body(archive);
  } catch (error: any) {
    console.error('Archive creation error:', error);
    return c.json({ error: 'Failed to create archive' }, 500);
  }
});

export default app;
```

**File**: `/Users/williamcory/plue/server/index.ts`

Add the files routes:

```typescript
import files from './routes/files';

// ... existing code ...

app.route('/api/files', files);
```

## Frontend Implementation

### 1. File Editor Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/edit/[...path].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { getFileContent, listBranches } from "../../../../lib/git";
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
const filename = pathParts[pathParts.length - 1] || "";

const isNewFile = !filePath || filePath.endsWith('/');
const content = isNewFile ? '' : await getFileContent(username!, reponame!, branch, filePath);

if (!isNewFile && content === null) {
  return Astro.redirect("/404");
}

const branches = await listBranches(username!, reponame!);
const breadcrumbParts = filePath ? filePath.split("/") : [];
---

<Layout title={`${isNewFile ? 'New File' : 'Edit ' + filename} · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    {isNewFile ? 'New File' : 'Edit File'}
  </div>

  <div class="container">
    <form id="edit-form" class="file-editor">
      <div class="form-group">
        <label for="filename">Filename</label>
        <input
          type="text"
          id="filename"
          name="filename"
          value={filePath}
          placeholder="path/to/file.txt"
          required
        />
      </div>

      <div class="form-group">
        <label for="content">File Content</label>
        <textarea
          id="content"
          name="content"
          rows="20"
          required
        >{content}</textarea>
      </div>

      <div class="commit-section">
        <h3>Commit Changes</h3>

        <div class="form-group">
          <input
            type="text"
            id="commit-message"
            name="message"
            placeholder={isNewFile ? `Create ${filename}` : `Update ${filename}`}
            required
          />
        </div>

        <div class="form-group">
          <label>
            <input type="radio" name="commit-choice" value="direct" checked />
            Commit directly to the <strong>{branch}</strong> branch
          </label>
        </div>

        <div class="form-group">
          <label>
            <input type="radio" name="commit-choice" value="new-branch" />
            Create a new branch for this commit
          </label>
          <input
            type="text"
            id="new-branch"
            name="newBranch"
            placeholder="new-branch-name"
            disabled
          />
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary">
            {isNewFile ? 'Create File' : 'Commit Changes'}
          </button>
          <a href={`/${username}/${reponame}/blob/${branch}/${filePath}`} class="btn-secondary">
            Cancel
          </a>
        </div>
      </div>
    </form>
  </div>

  <script>
    // Handle new branch input toggle
    const radios = document.querySelectorAll('input[name="commit-choice"]');
    const newBranchInput = document.getElementById('new-branch') as HTMLInputElement;

    radios.forEach(radio => {
      radio.addEventListener('change', (e) => {
        const target = e.target as HTMLInputElement;
        newBranchInput.disabled = target.value !== 'new-branch';
        if (!newBranchInput.disabled) {
          newBranchInput.focus();
        }
      });
    });

    // Handle form submission
    const form = document.getElementById('edit-form') as HTMLFormElement;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const formData = new FormData(form);
      const commitChoice = formData.get('commit-choice');
      const newBranch = commitChoice === 'new-branch' ? formData.get('newBranch') : null;

      const payload = {
        branch: '{branch}',
        filePath: formData.get('filename'),
        content: formData.get('content'),
        message: formData.get('message'),
        authorName: 'User', // TODO: Get from session
        authorEmail: 'user@plue.local', // TODO: Get from session
        newBranch: newBranch || undefined,
      };

      try {
        const response = await fetch('/api/files/{username}/{reponame}/files', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });

        const result = await response.json();

        if (response.ok) {
          // Redirect to the file view
          const targetBranch = result.branch;
          const targetPath = formData.get('filename');
          window.location.href = `/{username}/{reponame}/blob/${targetBranch}/${targetPath}`;
        } else {
          alert(`Error: ${result.error}`);
        }
      } catch (error) {
        alert('Failed to save file');
        console.error(error);
      }
    });
  </script>

  <style>
    .file-editor {
      max-width: 900px;
      margin: 2rem auto;
      padding: 2rem;
      border: 2px solid #000;
    }

    .form-group {
      margin-bottom: 1.5rem;
    }

    .form-group label {
      display: block;
      margin-bottom: 0.5rem;
      font-weight: bold;
    }

    .form-group input[type="text"],
    .form-group textarea {
      width: 100%;
      padding: 0.5rem;
      border: 2px solid #000;
      font-family: monospace;
      font-size: 14px;
    }

    .form-group textarea {
      resize: vertical;
      min-height: 400px;
    }

    #new-branch:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .commit-section {
      margin-top: 2rem;
      padding-top: 2rem;
      border-top: 2px solid #000;
    }

    .form-actions {
      display: flex;
      gap: 1rem;
      margin-top: 1.5rem;
    }

    .btn-primary, .btn-secondary {
      padding: 0.75rem 1.5rem;
      border: 2px solid #000;
      background: #000;
      color: #fff;
      text-decoration: none;
      cursor: pointer;
      font-weight: bold;
    }

    .btn-secondary {
      background: #fff;
      color: #000;
    }

    .btn-primary:hover {
      background: #333;
    }

    .btn-secondary:hover {
      background: #f0f0f0;
    }
  </style>
</Layout>
```

### 2. File Upload Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/upload/[...path].astro` (new file)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
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
const targetPath = pathParts.slice(1).join("/");
---

<Layout title={`Upload Files · ${username}/${reponame}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    Upload Files
  </div>

  <div class="container">
    <form id="upload-form" class="upload-form">
      <div class="form-group">
        <label for="files">Select Files</label>
        <input
          type="file"
          id="files"
          name="files"
          multiple
          required
        />
        <div id="file-list" class="file-list"></div>
      </div>

      <div class="form-group">
        <label for="target-path">Upload to directory (optional)</label>
        <input
          type="text"
          id="target-path"
          name="targetPath"
          value={targetPath}
          placeholder="path/to/directory"
        />
      </div>

      <div class="commit-section">
        <h3>Commit Changes</h3>

        <div class="form-group">
          <input
            type="text"
            id="commit-message"
            name="message"
            placeholder="Upload files"
            required
          />
        </div>

        <div class="form-group">
          <label>
            <input type="radio" name="commit-choice" value="direct" checked />
            Commit directly to the <strong>{branch}</strong> branch
          </label>
        </div>

        <div class="form-group">
          <label>
            <input type="radio" name="commit-choice" value="new-branch" />
            Create a new branch for this commit
          </label>
          <input
            type="text"
            id="new-branch"
            name="newBranch"
            placeholder="new-branch-name"
            disabled
          />
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary">Upload Files</button>
          <a href={`/${username}/${reponame}/tree/${branch}/${targetPath}`} class="btn-secondary">
            Cancel
          </a>
        </div>
      </div>
    </form>
  </div>

  <script>
    const fileInput = document.getElementById('files') as HTMLInputElement;
    const fileList = document.getElementById('file-list') as HTMLDivElement;

    fileInput.addEventListener('change', () => {
      const files = Array.from(fileInput.files || []);
      fileList.innerHTML = files.length > 0
        ? `<ul>${files.map(f => `<li>${f.name} (${(f.size / 1024).toFixed(2)} KB)</li>`).join('')}</ul>`
        : '';
    });

    // Handle new branch input toggle
    const radios = document.querySelectorAll('input[name="commit-choice"]');
    const newBranchInput = document.getElementById('new-branch') as HTMLInputElement;

    radios.forEach(radio => {
      radio.addEventListener('change', (e) => {
        const target = e.target as HTMLInputElement;
        newBranchInput.disabled = target.value !== 'new-branch';
        if (!newBranchInput.disabled) {
          newBranchInput.focus();
        }
      });
    });

    // Handle form submission
    const form = document.getElementById('upload-form') as HTMLFormElement;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const formData = new FormData(form);
      const files = Array.from(fileInput.files || []);

      if (files.length === 0) {
        alert('Please select at least one file');
        return;
      }

      // Read files as base64
      const filePromises = files.map(file => {
        return new Promise((resolve) => {
          const reader = new FileReader();
          reader.onload = () => {
            const base64 = (reader.result as string).split(',')[1];
            resolve({ name: file.name, content: base64 });
          };
          reader.readAsDataURL(file);
        });
      });

      const encodedFiles = await Promise.all(filePromises);

      const commitChoice = formData.get('commit-choice');
      const newBranch = commitChoice === 'new-branch' ? formData.get('newBranch') : null;

      const payload = {
        branch: '{branch}',
        targetPath: formData.get('targetPath') || '',
        message: formData.get('message'),
        authorName: 'User', // TODO: Get from session
        authorEmail: 'user@plue.local', // TODO: Get from session
        newBranch: newBranch || undefined,
        files: encodedFiles,
      };

      try {
        const response = await fetch('/api/files/{username}/{reponame}/upload', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });

        const result = await response.json();

        if (response.ok) {
          const targetBranch = result.branch;
          const targetDir = formData.get('targetPath') || '';
          window.location.href = `/{username}/{reponame}/tree/${targetBranch}/${targetDir}`;
        } else {
          alert(`Error: ${result.error}`);
        }
      } catch (error) {
        alert('Failed to upload files');
        console.error(error);
      }
    });
  </script>

  <style>
    .upload-form {
      max-width: 900px;
      margin: 2rem auto;
      padding: 2rem;
      border: 2px solid #000;
    }

    .form-group {
      margin-bottom: 1.5rem;
    }

    .form-group label {
      display: block;
      margin-bottom: 0.5rem;
      font-weight: bold;
    }

    .form-group input[type="text"],
    .form-group input[type="file"] {
      width: 100%;
      padding: 0.5rem;
      border: 2px solid #000;
    }

    .file-list {
      margin-top: 1rem;
      padding: 1rem;
      border: 1px solid #ccc;
      min-height: 50px;
    }

    .file-list ul {
      list-style: none;
      padding: 0;
      margin: 0;
    }

    .file-list li {
      padding: 0.25rem 0;
      font-family: monospace;
    }

    #new-branch:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .commit-section {
      margin-top: 2rem;
      padding-top: 2rem;
      border-top: 2px solid #000;
    }

    .form-actions {
      display: flex;
      gap: 1rem;
      margin-top: 1.5rem;
    }

    .btn-primary, .btn-secondary {
      padding: 0.75rem 1.5rem;
      border: 2px solid #000;
      background: #000;
      color: #fff;
      text-decoration: none;
      cursor: pointer;
      font-weight: bold;
    }

    .btn-secondary {
      background: #fff;
      color: #000;
    }

    .btn-primary:hover {
      background: #333;
    }

    .btn-secondary:hover {
      background: #f0f0f0;
    }
  </style>
</Layout>
```

### 3. Update File Viewer with Action Buttons

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/blob/[...path].astro`

Add action buttons to existing blob view:

```astro
<!-- Add after the breadcrumb section -->
<div class="file-actions">
  <a href={`/${username}/${reponame}/edit/${branch}/${filePath}`} class="action-btn">
    Edit
  </a>
  <a href={`/api/files/${username}/${reponame}/raw/${branch}/${filePath}`} class="action-btn">
    Raw
  </a>
  <button class="action-btn" id="delete-btn">Delete</button>
</div>

<script define:vars={{ username, reponame, branch, filePath }}>
  document.getElementById('delete-btn')?.addEventListener('click', async () => {
    const message = prompt('Commit message for deletion:');
    if (!message) return;

    const confirmDelete = confirm(`Are you sure you want to delete ${filePath}?`);
    if (!confirmDelete) return;

    try {
      const response = await fetch(`/api/files/${username}/${reponame}/files`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          branch,
          filePath,
          message,
          authorName: 'User', // TODO: from session
          authorEmail: 'user@plue.local', // TODO: from session
        }),
      });

      if (response.ok) {
        const parentPath = filePath.split('/').slice(0, -1).join('/');
        window.location.href = `/${username}/${reponame}/tree/${branch}/${parentPath}`;
      } else {
        const error = await response.json();
        alert(`Error: ${error.error}`);
      }
    } catch (error) {
      alert('Failed to delete file');
      console.error(error);
    }
  });
</script>

<style>
  .file-actions {
    display: flex;
    gap: 0.5rem;
    margin: 1rem 0;
    padding: 1rem;
    border: 2px solid #000;
    background: #f9f9f9;
  }

  .action-btn {
    padding: 0.5rem 1rem;
    border: 2px solid #000;
    background: #fff;
    color: #000;
    text-decoration: none;
    cursor: pointer;
    font-weight: bold;
  }

  .action-btn:hover {
    background: #000;
    color: #fff;
  }
</style>
```

### 4. Update Tree View with Action Buttons

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/tree/[...path].astro`

Add upload and create file buttons:

```astro
<!-- Add before the file tree display -->
<div class="tree-actions">
  <a href={`/${username}/${reponame}/edit/${branch}/${currentPath}/`} class="action-btn">
    + New File
  </a>
  <a href={`/${username}/${reponame}/upload/${branch}/${currentPath}`} class="action-btn">
    Upload Files
  </a>
  <a href={`/api/files/${username}/${reponame}/archive/${branch}.zip`} class="action-btn">
    Download ZIP
  </a>
  <a href={`/api/files/${username}/${reponame}/archive/${branch}.tar.gz`} class="action-btn">
    Download TAR.GZ
  </a>
</div>
```

## Implementation Checklist

### Phase 1: Backend Foundation
- [ ] Add new git operation functions to `/Users/williamcory/plue/ui/lib/git.ts`
  - [ ] `createOrUpdateFile()` with temp repo workflow
  - [ ] `deleteFile()` with recursive option
  - [ ] `uploadFiles()` with multi-file support
  - [ ] `createArchive()` for zip/tar.gz
  - [ ] `getRawFileContent()` for downloads
  - [ ] `cleanGitPath()` security function
- [ ] Create `/Users/williamcory/plue/server/routes/files.ts` with Hono routes
  - [ ] POST `/:user/:repo/files` - create/update file
  - [ ] DELETE `/:user/:repo/files` - delete file/directory
  - [ ] POST `/:user/:repo/upload` - upload multiple files
  - [ ] GET `/:user/:repo/raw/:ref/*` - raw file download
  - [ ] GET `/:user/:repo/archive/:ref.:format` - archive download
- [ ] Add Zod validation schemas for all operations
- [ ] Register files routes in `/Users/williamcory/plue/server/index.ts`

### Phase 2: Frontend Pages
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/edit/[...path].astro`
  - [ ] File content textarea with monospace font
  - [ ] Filename input with path support
  - [ ] Commit message input
  - [ ] Branch selection (commit to current or create new)
  - [ ] Client-side form validation
  - [ ] API integration with error handling
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/upload/[...path].astro`
  - [ ] Multiple file input
  - [ ] File list preview with sizes
  - [ ] Target directory input
  - [ ] Commit message and branch selection
  - [ ] Base64 encoding for file upload
  - [ ] Progress indication
- [ ] Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/blob/[...path].astro`
  - [ ] Add Edit, Raw, Delete action buttons
  - [ ] Delete confirmation dialog
  - [ ] Error handling for delete operations
- [ ] Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/tree/[...path].astro`
  - [ ] Add "New File" button
  - [ ] Add "Upload Files" button
  - [ ] Add archive download buttons (ZIP, TAR.GZ)

### Phase 3: Testing & Polish
- [ ] Test file creation workflow
  - [ ] Create new file in root
  - [ ] Create file in nested directory
  - [ ] Create file with new branch
- [ ] Test file editing workflow
  - [ ] Edit existing file
  - [ ] Edit with commit to new branch
  - [ ] Handle concurrent edit conflicts
- [ ] Test file deletion workflow
  - [ ] Delete single file
  - [ ] Delete directory recursively
  - [ ] Prevent deletion of root directory
- [ ] Test file upload workflow
  - [ ] Upload single file
  - [ ] Upload multiple files
  - [ ] Upload to nested directory
  - [ ] Handle large files (size limits)
- [ ] Test download workflows
  - [ ] Raw file download
  - [ ] ZIP archive download
  - [ ] TAR.GZ archive download
  - [ ] Archive of subdirectory
- [ ] Security testing
  - [ ] Verify path traversal prevention
  - [ ] Test .git directory protection
  - [ ] Validate file size limits
  - [ ] Test XSS in filenames/content

### Phase 4: Future Enhancements (Out of Scope)
- [ ] Syntax highlighting in editor (CodeMirror/Monaco)
- [ ] File preview before commit
- [ ] Diff view in editor
- [ ] Protected file patterns from repository settings
- [ ] LFS support for large files
- [ ] GPG commit signing
- [ ] Merge conflict resolution UI
- [ ] Branch comparison before commit

## Reference Implementation Notes

### Gitea's Approach

Gitea uses a `TemporaryUploadRepository` pattern (see `/Users/williamcory/plue/gitea/services/repository/files/temp_repo.go`):

1. **Temporary Clone**: Creates a shallow clone of the target branch
2. **File Operations**: Uses git commands directly (hash-object, update-index, write-tree)
3. **Commit Tree**: Creates commit with proper signatures and metadata
4. **Push**: Pushes commit back to bare repository
5. **Cleanup**: Removes temporary directory

Key operations:
- `HashObjectAndWrite()` - writes content to git object database
- `AddObjectToIndex()` - stages files using git update-index
- `WriteTree()` - creates tree object from index
- `CommitTree()` - creates commit with author/committer metadata
- `Push()` - pushes to remote (bare repo)

### Plue's Simplified Approach

Plue uses a similar but simpler workflow:
1. Create temp directory in `/tmp`
2. Clone target branch
3. Make file changes with standard filesystem operations
4. Use `git add`, `git commit`, `git push` commands
5. Cleanup temp directory

This is easier to implement and debug but potentially slower for large operations.

## Error Handling

### Common Errors

1. **Invalid Path**: Path contains `..` or `.git`
   - Response: 400 Bad Request
   - Message: "Invalid file path"

2. **File Already Exists**: Creating file that exists
   - Response: 409 Conflict
   - Message: "File already exists"

3. **File Not Found**: Editing/deleting non-existent file
   - Response: 404 Not Found
   - Message: "File not found"

4. **Branch Not Found**: Target branch doesn't exist
   - Response: 404 Not Found
   - Message: "Branch not found"

5. **Repository Not Found**: Invalid user/repo
   - Response: 404 Not Found
   - Message: "Repository not found"

6. **Concurrent Modification**: File changed since last view
   - Response: 409 Conflict
   - Message: "File was modified by another user"

7. **File Too Large**: Upload exceeds size limit
   - Response: 413 Payload Too Large
   - Message: "File exceeds maximum size"

### Security Considerations

1. **Path Traversal**: Always use `cleanGitPath()` to validate paths
2. **Git Directory**: Prevent access to `.git` directory
3. **File Size Limits**: Enforce maximum file sizes (default 100MB)
4. **Temp Directory**: Use random names and cleanup on error
5. **User Permissions**: TODO: Check user has write access to repository (future auth)

## API Documentation

### Create/Update File

```
POST /api/files/:user/:repo/files
```

**Request Body:**
```json
{
  "branch": "main",
  "filePath": "src/index.ts",
  "content": "console.log('Hello');",
  "message": "Create index.ts",
  "authorName": "John Doe",
  "authorEmail": "john@example.com",
  "newBranch": "feature-xyz" // optional
}
```

**Response:**
```json
{
  "success": true,
  "commit": "a1b2c3d4...",
  "branch": "main"
}
```

### Delete File

```
DELETE /api/files/:user/:repo/files
```

**Request Body:**
```json
{
  "branch": "main",
  "filePath": "src/old-file.ts",
  "message": "Remove old file",
  "authorName": "John Doe",
  "authorEmail": "john@example.com",
  "recursive": false,
  "newBranch": "cleanup" // optional
}
```

### Upload Files

```
POST /api/files/:user/:repo/upload
```

**Request Body:**
```json
{
  "branch": "main",
  "targetPath": "assets/images",
  "message": "Upload images",
  "authorName": "John Doe",
  "authorEmail": "john@example.com",
  "files": [
    { "name": "logo.png", "content": "base64..." },
    { "name": "banner.jpg", "content": "base64..." }
  ]
}
```

### Download Raw File

```
GET /api/files/:user/:repo/raw/:ref/*
```

Example: `GET /api/files/evilrabbit/myrepo/raw/main/src/index.ts`

Returns file content with `Content-Disposition: attachment`

### Download Archive

```
GET /api/files/:user/:repo/archive/:ref.:format
```

Examples:
- `GET /api/files/evilrabbit/myrepo/archive/main.zip`
- `GET /api/files/evilrabbit/myrepo/archive/v1.0.0.tar.gz`

Returns archive file with `Content-Disposition: attachment`

## Testing Strategy

### Manual Testing Checklist

1. **Create File**
   - [ ] Visit `/:user/:repo/edit/:branch/` (new file)
   - [ ] Enter filename `test.txt`
   - [ ] Enter content `Hello World`
   - [ ] Commit directly to branch
   - [ ] Verify file appears in tree view
   - [ ] Verify commit appears in commit history

2. **Edit File**
   - [ ] Visit existing file blob view
   - [ ] Click "Edit" button
   - [ ] Modify content
   - [ ] Create new branch "edit-test"
   - [ ] Verify new branch created
   - [ ] Verify file updated in new branch
   - [ ] Verify original branch unchanged

3. **Delete File**
   - [ ] Visit file blob view
   - [ ] Click "Delete" button
   - [ ] Confirm deletion
   - [ ] Verify file removed
   - [ ] Verify commit created

4. **Upload Files**
   - [ ] Visit tree view
   - [ ] Click "Upload Files"
   - [ ] Select multiple files
   - [ ] Set target directory
   - [ ] Commit and verify all files uploaded

5. **Download**
   - [ ] Click "Raw" on text file
   - [ ] Verify file downloads
   - [ ] Click "Download ZIP"
   - [ ] Verify archive contains all files
   - [ ] Extract and verify structure

### Automated Testing (Future)

```typescript
import { test, expect } from "bun:test";
import { createOrUpdateFile, deleteFile } from "../ui/lib/git";

test("create file creates commit", async () => {
  const result = await createOrUpdateFile("testuser", "testrepo", {
    branch: "main",
    filePath: "test.txt",
    content: "test content",
    message: "Test commit",
    authorName: "Test",
    authorEmail: "test@example.com",
  });

  expect(result.commitHash).toMatch(/^[0-9a-f]{40}$/);
  expect(result.branch).toBe("main");
});

test("delete file removes file from tree", async () => {
  // TODO: Implement
});
```

## Implementation Time Estimate

- **Phase 1** (Backend): 4-6 hours
- **Phase 2** (Frontend): 6-8 hours
- **Phase 3** (Testing): 3-4 hours
- **Total**: 13-18 hours

## Success Criteria

1. Users can create new files through web UI
2. Users can edit existing files with syntax highlighting
3. Users can delete files and directories
4. Users can upload multiple files at once
5. Users can download raw files
6. Users can download repository archives
7. All operations create proper git commits
8. All operations support creating new branches
9. Path traversal attacks are prevented
10. Error messages are clear and helpful
