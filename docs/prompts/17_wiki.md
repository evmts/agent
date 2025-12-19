# Wiki Implementation

## Overview

Implement a complete wiki system for Plue repositories, backed by separate git repositories for each wiki. This provides version-controlled, markdown-based documentation with full editing, history, and navigation capabilities.

**Scope:**
- Wiki as separate git repository (`repo.wiki.git`)
- Wiki page CRUD (create, read, update, delete)
- Markdown rendering with special pages
- Wiki sidebar/navigation (`_Sidebar.md`)
- Wiki footer (`_Footer.md`)
- Page history/revisions
- Wiki page list
- Raw file viewing
- Git operations for wiki repository
- API endpoints for programmatic access
- UI pages for wiki interaction

**Out of scope (future features):**
- Wiki search (implement with feature #10 Search)
- Wiki attachments/uploads
- Wiki subdirectories
- Wiki templates
- Wiki table of contents generation
- External wiki links

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL (for repository metadata)
- **Storage**: Git repositories (bare)
- **Markdown**: Custom renderer in `ui/lib/markdown.ts`
- **Validation**: Zod v4

## Architecture Overview

### Wiki Storage Model

Each repository's wiki is stored as a **separate bare git repository**:
- Main repo: `/repos/{user}/{repo}`
- Wiki repo: `/repos/{user}/{repo}.wiki.git`

### Path Conventions

Gitea uses a sophisticated path system to handle special characters in wiki page names:

**Display Title → Web Path → Git Path**
- `"Home Page"` → `"Home-Page"` → `"Home-Page.md"`
- `"100% Free"` → `"100%25+Free"` → `"100%25 Free.md"`
- `"2000-01-02 meeting"` → `"2000-01-02+meeting.-"` → `"2000-01-02 meeting.-.md"`

**Key Concepts:**
1. **Display Segment**: Human-readable title shown to users
2. **Web Path**: URL-encoded path with space→dash conversion
3. **Git Path**: Actual filename in git (`.md` extension)
4. **Dash Marker (`.-`)**: Indicates no dash-space conversion for this segment

### Reserved Page Names

Special pages that cannot be created as regular wiki pages:
- `_Sidebar` - Sidebar navigation
- `_Footer` - Footer content
- `_pages` - Reserved for page list action
- `_new` - Reserved for new page action
- `_edit` - Reserved for edit action
- `raw` - Reserved for raw file viewing

## Database Schema Changes

### 1. Add wiki support to `repositories` table

**File**: `/Users/williamcory/plue/db/schema.sql`

Add column to repositories table:

```sql
ALTER TABLE repositories
ADD COLUMN IF NOT EXISTS default_wiki_branch VARCHAR(255) DEFAULT 'master';
```

**Note**: Gitea uses 'master' as default wiki branch, different from code repos which use 'main'.

## Git Library Enhancements

### 1. Wiki repository operations

**File**: `/Users/williamcory/plue/ui/lib/git.ts`

Add wiki-specific functions:

```typescript
// Get wiki repository path
export function getWikiRepoPath(user: string, name: string): string {
  return `${REPOS_DIR}/${user}/${name}.wiki.git`;
}

// Get wiki clone URL
export function getWikiCloneUrl(user: string, name: string): string {
  return `file://${getWikiRepoPath(user, name)}`;
}

// Initialize wiki repository
export async function initWikiRepo(user: string, name: string): Promise<void> {
  const wikiPath = getWikiRepoPath(user, name);
  const tempDir = `/tmp/plue-wiki-init-${Date.now()}`;

  await mkdir(wikiPath, { recursive: true });
  await run(`git init --bare "${wikiPath}"`);

  // Create initial commit with Home.md
  await mkdir(tempDir, { recursive: true });
  await run(`git init`, tempDir);
  await run(`git config user.email "plue@local"`, tempDir);
  await run(`git config user.name "Plue"`, tempDir);
  await writeFile(`${tempDir}/Home.md`, `# Welcome to the wiki!\n\nEdit this page to get started.`);
  await run(`git add .`, tempDir);
  await run(`git commit -m "Initial wiki commit"`, tempDir);
  await run(`git branch -M master`, tempDir);
  await run(`git remote add origin "${wikiPath}"`, tempDir);
  await run(`git push -u origin master`, tempDir);
  await rm(tempDir, { recursive: true });
}

// Check if wiki exists
export async function wikiExists(user: string, name: string): Promise<boolean> {
  const wikiPath = getWikiRepoPath(user, name);
  return existsSync(`${wikiPath}/HEAD`);
}

// Delete wiki repository
export async function deleteWikiRepo(user: string, name: string): Promise<void> {
  const wikiPath = getWikiRepoPath(user, name);
  await rm(wikiPath, { recursive: true });
}
```

### 2. Wiki page operations

**File**: `/Users/williamcory/plue/ui/lib/wiki.ts` (NEW)

Create comprehensive wiki operations library:

```typescript
import { exec } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import type { TreeEntry, Commit } from "./types";
import { getWikiRepoPath } from "./git";

const execAsync = promisify(exec);

async function run(cmd: string, cwd?: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd, { cwd });
    return stdout;
  } catch (error: any) {
    return error.stdout || "";
  }
}

export type WikiPath = string; // Type alias for web paths

// Path conversion utilities (based on Gitea's wiki_path.go)

const RESERVED_NAMES = ["_pages", "_new", "_edit", "raw"];

export function validateWikiPath(name: WikiPath): boolean {
  const segments = name.split("/").map(s => unescapeSegment(s));
  return !segments.some(s => RESERVED_NAMES.includes(s));
}

function hasDashMarker(s: string): boolean {
  return s.endsWith(".-");
}

function removeDashMarker(s: string): string {
  return s.replace(/\.-$/, "");
}

function addDashMarker(s: string): string {
  return s + ".-";
}

function unescapeSegment(s: string): string {
  if (hasDashMarker(s)) {
    s = removeDashMarker(s);
  } else {
    s = s.replace(/-/g, " ");
  }
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

function escapeSegToWeb(s: string, hadDashMarker: boolean): string {
  if (hadDashMarker || s.includes("-") || s.endsWith(".md")) {
    s = addDashMarker(s);
  } else {
    s = s.replace(/ /g, "-");
  }
  return encodeURIComponent(s);
}

// Convert web path to git path
export function webPathToGitPath(webPath: WikiPath): string {
  if (webPath.endsWith(".md")) {
    try {
      return decodeURIComponent(webPath);
    } catch {
      return webPath;
    }
  }

  const segments = webPath.split("/");
  const converted = segments.map(segment => {
    const hadMarker = hasDashMarker(segment);
    const unescaped = unescapeSegment(segment);
    const escaped = escapeSegToWeb(unescaped, hadMarker);
    return escaped.replace(/%20/g, " ").replace(/\+/g, " ");
  });

  return converted.join("/") + ".md";
}

// Convert git path to web path
export function gitPathToWebPath(gitPath: string): WikiPath {
  if (!gitPath.endsWith(".md")) {
    throw new Error(`Invalid wiki filename: ${gitPath}`);
  }

  const withoutExt = gitPath.slice(0, -3);
  const segments = withoutExt.split("/");

  const converted = segments.map(segment => {
    const hadMarker = hasDashMarker(segment);
    const unescaped = unescapeSegment(segment);
    return escapeSegToWeb(unescaped, hadMarker);
  });

  return converted.join("/");
}

// Convert web path to display title
export function webPathToTitle(webPath: WikiPath): string {
  const baseName = webPath.split("/").pop() || webPath;
  if (baseName.endsWith(".md")) {
    return decodeURIComponent(baseName.slice(0, -3));
  }
  return unescapeSegment(baseName);
}

// Convert user title to web path
export function titleToWebPath(title: string): WikiPath {
  const trimmed = title.trim();
  const escaped = escapeSegToWeb(trimmed, false);
  return escaped || "unnamed";
}

// Convert web path to URL path (for use in hrefs)
export function webPathToUrlPath(webPath: WikiPath): string {
  return webPath;
}

// Wiki page operations

export interface WikiPage {
  name: string;        // Display name
  webPath: WikiPath;   // Web path
  gitPath: string;     // Git filename
  content?: string;    // Page content
  lastCommit?: Commit; // Last modification
}

// Get all wiki pages
export async function listWikiPages(
  user: string,
  repo: string
): Promise<WikiPage[]> {
  const wikiPath = getWikiRepoPath(user, repo);

  try {
    const result = await run(`git ls-tree master`, wikiPath);
    const entries = result
      .trim()
      .split("\n")
      .filter(Boolean)
      .map(line => {
        const match = line.match(/^(\d+)\s+(blob|tree)\s+([a-f0-9]+)\t(.+)$/);
        if (!match) return null;
        const [, , , , name] = match;
        return name;
      })
      .filter((name): name is string => name !== null && name.endsWith(".md"));

    const pages: WikiPage[] = [];
    for (const gitPath of entries) {
      try {
        const webPath = gitPathToWebPath(gitPath);
        const name = webPathToTitle(webPath);

        // Skip special pages
        if (name === "_Sidebar" || name === "_Footer") {
          continue;
        }

        pages.push({ name, webPath, gitPath });
      } catch (err) {
        // Skip invalid filenames
        continue;
      }
    }

    return pages;
  } catch {
    return [];
  }
}

// Get wiki page content
export async function getWikiPage(
  user: string,
  repo: string,
  webPath: WikiPath
): Promise<WikiPage | null> {
  const wikiPath = getWikiRepoPath(user, repo);
  const gitPath = webPathToGitPath(webPath);

  try {
    const content = await run(`git show master:"${gitPath}"`, wikiPath);
    const name = webPathToTitle(webPath);

    return { name, webPath, gitPath, content };
  } catch {
    // Try without .md extension
    const gitPathNoExt = gitPath.replace(/\.md$/, "");
    try {
      const content = await run(`git show master:"${gitPathNoExt}"`, wikiPath);
      const name = webPathToTitle(webPath);
      return { name, webPath, gitPath: gitPathNoExt, content };
    } catch {
      return null;
    }
  }
}

// Create wiki page
export async function createWikiPage(
  user: string,
  repo: string,
  title: string,
  content: string,
  message?: string
): Promise<void> {
  const webPath = titleToWebPath(title);
  if (!validateWikiPath(webPath)) {
    throw new Error(`Reserved wiki page name: ${title}`);
  }

  const wikiPath = getWikiRepoPath(user, repo);
  const gitPath = webPathToGitPath(webPath);
  const tempDir = `/tmp/plue-wiki-${Date.now()}`;

  try {
    // Clone wiki
    await mkdir(tempDir, { recursive: true });
    await run(`git clone "${wikiPath}" .`, tempDir);

    // Check if page already exists
    const exists = await run(`git ls-files "${gitPath}"`, tempDir);
    if (exists.trim()) {
      throw new Error("Wiki page already exists");
    }

    // Create page
    await writeFile(`${tempDir}/${gitPath}`, content);
    await run(`git add "${gitPath}"`, tempDir);

    const commitMsg = message || `Add ${title}`;
    await run(`git -c user.email="plue@local" -c user.name="Plue" commit -m "${commitMsg}"`, tempDir);
    await run(`git push origin master`, tempDir);
  } finally {
    await rm(tempDir, { recursive: true });
  }
}

// Update wiki page
export async function updateWikiPage(
  user: string,
  repo: string,
  oldWebPath: WikiPath,
  newTitle: string,
  content: string,
  message?: string
): Promise<void> {
  const newWebPath = titleToWebPath(newTitle);
  if (!validateWikiPath(newWebPath)) {
    throw new Error(`Reserved wiki page name: ${newTitle}`);
  }

  const wikiPath = getWikiRepoPath(user, repo);
  const oldGitPath = webPathToGitPath(oldWebPath);
  const newGitPath = webPathToGitPath(newWebPath);
  const tempDir = `/tmp/plue-wiki-${Date.now()}`;

  try {
    // Clone wiki
    await mkdir(tempDir, { recursive: true });
    await run(`git clone "${wikiPath}" .`, tempDir);

    // Remove old file if name changed
    if (oldGitPath !== newGitPath) {
      await run(`git rm "${oldGitPath}"`, tempDir);
    }

    // Write new content
    await writeFile(`${tempDir}/${newGitPath}`, content);
    await run(`git add "${newGitPath}"`, tempDir);

    const commitMsg = message || `Update ${newTitle}`;
    await run(`git -c user.email="plue@local" -c user.name="Plue" commit -m "${commitMsg}"`, tempDir);
    await run(`git push origin master`, tempDir);
  } finally {
    await rm(tempDir, { recursive: true });
  }
}

// Delete wiki page
export async function deleteWikiPage(
  user: string,
  repo: string,
  webPath: WikiPath
): Promise<void> {
  const wikiPath = getWikiRepoPath(user, repo);
  const gitPath = webPathToGitPath(webPath);
  const tempDir = `/tmp/plue-wiki-${Date.now()}`;

  try {
    // Clone wiki
    await mkdir(tempDir, { recursive: true });
    await run(`git clone "${wikiPath}" .`, tempDir);

    // Delete page
    await run(`git rm "${gitPath}"`, tempDir);

    const title = webPathToTitle(webPath);
    await run(`git -c user.email="plue@local" -c user.name="Plue" commit -m "Delete ${title}"`, tempDir);
    await run(`git push origin master`, tempDir);
  } finally {
    await rm(tempDir, { recursive: true });
  }
}

// Get wiki page history
export async function getWikiPageHistory(
  user: string,
  repo: string,
  webPath: WikiPath,
  limit: number = 20
): Promise<Commit[]> {
  const wikiPath = getWikiRepoPath(user, repo);
  const gitPath = webPathToGitPath(webPath);

  try {
    const format = "%H|%h|%an|%ae|%at|%s";
    const result = await run(`git log master --format="${format}" -n ${limit} -- "${gitPath}"`, wikiPath);

    return result
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
  } catch {
    return [];
  }
}
```

## API Endpoints

### 1. Wiki routes

**File**: `/Users/williamcory/plue/server/routes/wiki.ts` (NEW)

```typescript
import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { sql } from "../../ui/lib/db";
import {
  initWikiRepo,
  wikiExists,
  deleteWikiRepo
} from "../../ui/lib/git";
import {
  listWikiPages,
  getWikiPage,
  createWikiPage,
  updateWikiPage,
  deleteWikiPage,
  getWikiPageHistory,
  titleToWebPath,
  type WikiPath,
} from "../../ui/lib/wiki";
import type { Repository } from "../../ui/lib/types";

const app = new Hono();

// Validation schemas
const createPageSchema = z.object({
  title: z.string().min(1).max(255),
  content: z.string(),
  message: z.string().optional(),
});

const updatePageSchema = z.object({
  title: z.string().min(1).max(255),
  content: z.string(),
  message: z.string().optional(),
});

// Initialize wiki for a repository
app.post("/:user/:repo/init", async (c) => {
  const { user, repo } = c.req.param();

  // Check if repo exists
  const [repository] = await sql`
    SELECT r.* FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  ` as Repository[];

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  // Check if wiki already exists
  if (await wikiExists(user, repo)) {
    return c.json({ error: "Wiki already exists" }, 400);
  }

  // Initialize wiki
  await initWikiRepo(user, repo);

  return c.json({ success: true });
});

// List all wiki pages
app.get("/:user/:repo/pages", async (c) => {
  const { user, repo } = c.req.param();

  if (!await wikiExists(user, repo)) {
    return c.json({ error: "Wiki not found" }, 404);
  }

  const pages = await listWikiPages(user, repo);
  return c.json({ pages });
});

// Get a specific wiki page
app.get("/:user/:repo/page/:path", async (c) => {
  const { user, repo, path } = c.req.param();

  if (!await wikiExists(user, repo)) {
    return c.json({ error: "Wiki not found" }, 404);
  }

  const webPath = decodeURIComponent(path) as WikiPath;
  const page = await getWikiPage(user, repo, webPath);

  if (!page) {
    return c.json({ error: "Page not found" }, 404);
  }

  return c.json({ page });
});

// Create a new wiki page
app.post(
  "/:user/:repo/page",
  zValidator("json", createPageSchema),
  async (c) => {
    const { user, repo } = c.req.param();
    const { title, content, message } = c.req.valid("json");

    if (!await wikiExists(user, repo)) {
      // Auto-initialize wiki if it doesn't exist
      await initWikiRepo(user, repo);
    }

    try {
      await createWikiPage(user, repo, title, content, message);
      const webPath = titleToWebPath(title);
      return c.json({ success: true, webPath }, 201);
    } catch (error: any) {
      return c.json({ error: error.message }, 400);
    }
  }
);

// Update a wiki page
app.put(
  "/:user/:repo/page/:path",
  zValidator("json", updatePageSchema),
  async (c) => {
    const { user, repo, path } = c.req.param();
    const { title, content, message } = c.req.valid("json");

    if (!await wikiExists(user, repo)) {
      return c.json({ error: "Wiki not found" }, 404);
    }

    const oldWebPath = decodeURIComponent(path) as WikiPath;

    try {
      await updateWikiPage(user, repo, oldWebPath, title, content, message);
      const newWebPath = titleToWebPath(title);
      return c.json({ success: true, webPath: newWebPath });
    } catch (error: any) {
      return c.json({ error: error.message }, 400);
    }
  }
);

// Delete a wiki page
app.delete("/:user/:repo/page/:path", async (c) => {
  const { user, repo, path } = c.req.param();

  if (!await wikiExists(user, repo)) {
    return c.json({ error: "Wiki not found" }, 404);
  }

  const webPath = decodeURIComponent(path) as WikiPath;

  try {
    await deleteWikiPage(user, repo, webPath);
    return c.json({ success: true });
  } catch (error: any) {
    return c.json({ error: error.message }, 400);
  }
});

// Get wiki page history
app.get("/:user/:repo/page/:path/history", async (c) => {
  const { user, repo, path } = c.req.param();
  const limit = parseInt(c.req.query("limit") || "20");

  if (!await wikiExists(user, repo)) {
    return c.json({ error: "Wiki not found" }, 404);
  }

  const webPath = decodeURIComponent(path) as WikiPath;
  const history = await getWikiPageHistory(user, repo, webPath, limit);

  return c.json({ history });
});

// Delete entire wiki
app.delete("/:user/:repo", async (c) => {
  const { user, repo } = c.req.param();

  if (!await wikiExists(user, repo)) {
    return c.json({ error: "Wiki not found" }, 404);
  }

  await deleteWikiRepo(user, repo);
  return c.json({ success: true });
});

export default app;
```

### 2. Mount wiki routes

**File**: `/Users/williamcory/plue/server/routes/index.ts`

```typescript
import { Hono } from 'hono';
import sessions from './sessions';
import messages from './messages';
import pty from './pty';
import wiki from './wiki'; // NEW

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: Date.now() });
});

// Mount routes
app.route('/sessions', sessions);
app.route('/session', messages);
app.route('/pty', pty);
app.route('/wiki', wiki); // NEW

export default app;
```

## UI Pages

### 1. Wiki home page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/index.astro` (NEW)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import Markdown from "../../../../components/Markdown.astro";
import { sql } from "../../../../lib/db";
import { wikiExists } from "../../../../lib/git";
import { getWikiPage, listWikiPages, webPathToUrlPath } from "../../../../lib/wiki";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

const hasWiki = await wikiExists(username!, reponame!);

let homePage = null;
let sidebarPage = null;
let footerPage = null;
let pages: any[] = [];

if (hasWiki) {
  homePage = await getWikiPage(username!, reponame!, "Home");
  sidebarPage = await getWikiPage(username!, reponame!, "_Sidebar");
  footerPage = await getWikiPage(username!, reponame!, "_Footer");
  pages = await listWikiPages(username!, reponame!);
}
---

<Layout title={`Wiki · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <span class="current">Wiki</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    {!hasWiki ? (
      <div class="empty-state">
        <h2>No wiki yet</h2>
        <p>Create the first wiki page to get started.</p>
        <a href={`/${username}/${reponame}/wiki/_new`} class="btn">Create the first page</a>
      </div>
    ) : (
      <div class="wiki-layout">
        {sidebarPage && sidebarPage.content && (
          <aside class="wiki-sidebar">
            <Markdown content={sidebarPage.content} />
          </aside>
        )}

        <main class="wiki-content">
          <div class="wiki-header">
            <h1>{homePage?.name || "Home"}</h1>
            <div class="wiki-actions">
              <a href={`/${username}/${reponame}/wiki/_pages`} class="btn btn-sm">Pages</a>
              <a href={`/${username}/${reponame}/wiki/_new`} class="btn btn-sm">New Page</a>
              {homePage && (
                <>
                  <a href={`/${username}/${reponame}/wiki/Home/_edit`} class="btn btn-sm">Edit</a>
                  <a href={`/${username}/${reponame}/wiki/Home/_history`} class="btn btn-sm">History</a>
                </>
              )}
            </div>
          </div>

          {homePage && homePage.content ? (
            <Markdown content={homePage.content} />
          ) : (
            <p>This page is empty. <a href={`/${username}/${reponame}/wiki/Home/_edit`}>Edit it</a> to add content.</p>
          )}
        </main>
      </div>
    )}

    {footerPage && footerPage.content && (
      <footer class="wiki-footer">
        <Markdown content={footerPage.content} />
      </footer>
    )}
  </div>
</Layout>

<style>
  .empty-state {
    text-align: center;
    padding: 4rem 2rem;
  }

  .wiki-layout {
    display: grid;
    grid-template-columns: 250px 1fr;
    gap: 2rem;
    margin-top: 2rem;
  }

  .wiki-sidebar {
    border-right: 1px solid #000;
    padding-right: 2rem;
  }

  .wiki-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid #000;
  }

  .wiki-actions {
    display: flex;
    gap: 0.5rem;
  }

  .wiki-footer {
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 2px solid #000;
  }

  @media (max-width: 768px) {
    .wiki-layout {
      grid-template-columns: 1fr;
    }

    .wiki-sidebar {
      border-right: none;
      border-bottom: 1px solid #000;
      padding-right: 0;
      padding-bottom: 2rem;
    }
  }
</style>
```

### 2. Wiki page view

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/[...page].astro` (NEW)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import Markdown from "../../../../components/Markdown.astro";
import { sql } from "../../../../lib/db";
import { wikiExists } from "../../../../lib/git";
import { getWikiPage, webPathToUrlPath, type WikiPath } from "../../../../lib/wiki";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame, page } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

if (!await wikiExists(username!, reponame!)) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

const webPath = (page || "Home") as WikiPath;
const wikiPage = await getWikiPage(username!, reponame!, webPath);
const sidebarPage = await getWikiPage(username!, reponame!, "_Sidebar");
const footerPage = await getWikiPage(username!, reponame!, "_Footer");

if (!wikiPage) {
  return Astro.redirect(`/${username}/${reponame}/wiki/_new?title=${encodeURIComponent(page || "")}`);
}
---

<Layout title={`${wikiPage.name} · Wiki · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki`}>Wiki</a>
    <span class="sep">/</span>
    <span class="current">{wikiPage.name}</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    <div class="wiki-layout">
      {sidebarPage && sidebarPage.content && (
        <aside class="wiki-sidebar">
          <Markdown content={sidebarPage.content} />
        </aside>
      )}

      <main class="wiki-content">
        <div class="wiki-header">
          <h1>{wikiPage.name}</h1>
          <div class="wiki-actions">
            <a href={`/${username}/${reponame}/wiki/_pages`} class="btn btn-sm">Pages</a>
            <a href={`/${username}/${reponame}/wiki/_new`} class="btn btn-sm">New Page</a>
            <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(webPath)}/_edit`} class="btn btn-sm">Edit</a>
            <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(webPath)}/_history`} class="btn btn-sm">History</a>
            <a href={`/${username}/${reponame}/wiki/raw/${webPathToUrlPath(webPath)}`} class="btn btn-sm">Raw</a>
          </div>
        </div>

        {wikiPage.content && <Markdown content={wikiPage.content} />}
      </main>
    </div>

    {footerPage && footerPage.content && (
      <footer class="wiki-footer">
        <Markdown content={footerPage.content} />
      </footer>
    )}
  </div>
</Layout>

<style>
  .wiki-layout {
    display: grid;
    grid-template-columns: 250px 1fr;
    gap: 2rem;
    margin-top: 2rem;
  }

  .wiki-sidebar {
    border-right: 1px solid #000;
    padding-right: 2rem;
  }

  .wiki-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid #000;
  }

  .wiki-actions {
    display: flex;
    gap: 0.5rem;
  }

  .wiki-footer {
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 2px solid #000;
  }

  @media (max-width: 768px) {
    .wiki-layout {
      grid-template-columns: 1fr;
    }

    .wiki-sidebar {
      border-right: none;
      border-bottom: 1px solid #000;
      padding-right: 0;
      padding-bottom: 2rem;
    }
  }
</style>
```

### 3. New wiki page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/_new.astro` (NEW)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;
const title = Astro.url.searchParams.get("title") || "";

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

let error = "";

if (Astro.request.method === "POST") {
  const formData = await Astro.request.formData();
  const pageTitle = formData.get("title") as string;
  const content = formData.get("content") as string;
  const message = formData.get("message") as string;

  if (!pageTitle || !content) {
    error = "Title and content are required";
  } else {
    try {
      const response = await fetch(`http://localhost:3001/wiki/${username}/${reponame}/page`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: pageTitle, content, message }),
      });

      if (response.ok) {
        const data = await response.json();
        return Astro.redirect(`/${username}/${reponame}/wiki/${data.webPath}`);
      } else {
        const data = await response.json();
        error = data.error || "Failed to create page";
      }
    } catch (e: any) {
      error = e.message;
    }
  }
}
---

<Layout title={`New Wiki Page · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki`}>Wiki</a>
    <span class="sep">/</span>
    <span class="current">New Page</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    <h1>New Wiki Page</h1>

    {error && <div class="alert alert-error">{error}</div>}

    <form method="POST" class="form">
      <div class="form-group">
        <label for="title">Page Title</label>
        <input
          type="text"
          id="title"
          name="title"
          value={title}
          required
          autofocus
          placeholder="Page title"
        />
      </div>

      <div class="form-group">
        <label for="content">Content (Markdown)</label>
        <textarea
          id="content"
          name="content"
          rows="20"
          required
          placeholder="Write your content in Markdown..."
        ></textarea>
      </div>

      <div class="form-group">
        <label for="message">Commit Message (optional)</label>
        <input
          type="text"
          id="message"
          name="message"
          placeholder="Add page description"
        />
      </div>

      <div class="form-actions">
        <button type="submit" class="btn">Create Page</button>
        <a href={`/${username}/${reponame}/wiki`} class="btn btn-secondary">Cancel</a>
      </div>
    </form>
  </div>
</Layout>

<style>
  .form {
    max-width: 800px;
  }

  .alert {
    padding: 1rem;
    margin-bottom: 1rem;
    border: 2px solid #000;
  }

  .alert-error {
    background: #fee;
  }
</style>
```

### 4. Edit wiki page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/[page]/_edit.astro` (NEW)

```astro
---
import Layout from "../../../../../layouts/Layout.astro";
import Header from "../../../../../components/Header.astro";
import { sql } from "../../../../../lib/db";
import { wikiExists } from "../../../../../lib/git";
import { getWikiPage, webPathToUrlPath, type WikiPath } from "../../../../../lib/wiki";
import type { User, Repository } from "../../../../../lib/types";

const { user: username, repo: reponame, page } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

if (!await wikiExists(username!, reponame!)) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

const webPath = (page || "Home") as WikiPath;
const wikiPage = await getWikiPage(username!, reponame!, webPath);

if (!wikiPage) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

let error = "";

if (Astro.request.method === "POST") {
  const formData = await Astro.request.formData();
  const newTitle = formData.get("title") as string;
  const content = formData.get("content") as string;
  const message = formData.get("message") as string;

  if (!newTitle || !content) {
    error = "Title and content are required";
  } else {
    try {
      const response = await fetch(
        `http://localhost:3001/wiki/${username}/${reponame}/page/${encodeURIComponent(webPath)}`,
        {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: newTitle, content, message }),
        }
      );

      if (response.ok) {
        const data = await response.json();
        return Astro.redirect(`/${username}/${reponame}/wiki/${data.webPath}`);
      } else {
        const data = await response.json();
        error = data.error || "Failed to update page";
      }
    } catch (e: any) {
      error = e.message;
    }
  }
}
---

<Layout title={`Edit ${wikiPage.name} · Wiki · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki`}>Wiki</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(webPath)}`}>{wikiPage.name}</a>
    <span class="sep">/</span>
    <span class="current">Edit</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    <h1>Edit Wiki Page</h1>

    {error && <div class="alert alert-error">{error}</div>}

    <form method="POST" class="form">
      <div class="form-group">
        <label for="title">Page Title</label>
        <input
          type="text"
          id="title"
          name="title"
          value={wikiPage.name}
          required
          autofocus
        />
      </div>

      <div class="form-group">
        <label for="content">Content (Markdown)</label>
        <textarea
          id="content"
          name="content"
          rows="20"
          required
        >{wikiPage.content}</textarea>
      </div>

      <div class="form-group">
        <label for="message">Commit Message (optional)</label>
        <input
          type="text"
          id="message"
          name="message"
          placeholder={`Update ${wikiPage.name}`}
        />
      </div>

      <div class="form-actions">
        <button type="submit" class="btn">Save Changes</button>
        <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(webPath)}`} class="btn btn-secondary">Cancel</a>
      </div>
    </form>
  </div>
</Layout>

<style>
  .form {
    max-width: 800px;
  }

  .alert {
    padding: 1rem;
    margin-bottom: 1rem;
    border: 2px solid #000;
  }

  .alert-error {
    background: #fee;
  }
</style>
```

### 5. Wiki pages list

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/_pages.astro` (NEW)

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { wikiExists } from "../../../../lib/git";
import { listWikiPages, webPathToUrlPath } from "../../../../lib/wiki";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

if (!await wikiExists(username!, reponame!)) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

const pages = await listWikiPages(username!, reponame!);
---

<Layout title={`Pages · Wiki · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki`}>Wiki</a>
    <span class="sep">/</span>
    <span class="current">Pages</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    <div class="header-row">
      <h1>Wiki Pages ({pages.length})</h1>
      <a href={`/${username}/${reponame}/wiki/_new`} class="btn">New Page</a>
    </div>

    {pages.length === 0 ? (
      <p>No wiki pages yet.</p>
    ) : (
      <table class="table">
        <thead>
          <tr>
            <th>Page</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {pages.map((page) => (
            <tr>
              <td>
                <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(page.webPath)}`}>
                  {page.name}
                </a>
              </td>
              <td>
                <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(page.webPath)}/_edit`}>Edit</a>
                {" · "}
                <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(page.webPath)}/_history`}>History</a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </div>
</Layout>

<style>
  .header-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
  }

  .table {
    width: 100%;
    border-collapse: collapse;
  }

  .table th,
  .table td {
    padding: 0.75rem;
    border: 1px solid #000;
    text-align: left;
  }

  .table th {
    background: #f0f0f0;
    font-weight: bold;
  }
</style>
```

### 6. Wiki page history

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/wiki/[page]/_history.astro` (NEW)

```astro
---
import Layout from "../../../../../layouts/Layout.astro";
import Header from "../../../../../components/Header.astro";
import { sql } from "../../../../../lib/db";
import { wikiExists } from "../../../../../lib/git";
import { getWikiPage, getWikiPageHistory, webPathToUrlPath, type WikiPath } from "../../../../../lib/wiki";
import type { User, Repository } from "../../../../../lib/types";

const { user: username, repo: reponame, page } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

if (!await wikiExists(username!, reponame!)) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

const webPath = (page || "Home") as WikiPath;
const wikiPage = await getWikiPage(username!, reponame!, webPath);

if (!wikiPage) {
  return Astro.redirect(`/${username}/${reponame}/wiki`);
}

const history = await getWikiPageHistory(username!, reponame!, webPath);

function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleString();
}
---

<Layout title={`History · ${wikiPage.name} · Wiki · ${username}/${reponame} · plue`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki`}>Wiki</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/wiki/${webPathToUrlPath(webPath)}`}>{wikiPage.name}</a>
    <span class="sep">/</span>
    <span class="current">History</span>
  </div>

  <nav class="repo-nav">
    <a href={`/${username}/${reponame}`}>Code</a>
    <a href={`/${username}/${reponame}/issues`}>Issues</a>
    <a href={`/${username}/${reponame}/wiki`} class="active">Wiki</a>
  </nav>

  <div class="container">
    <h1>Page History: {wikiPage.name}</h1>

    {history.length === 0 ? (
      <p>No history available.</p>
    ) : (
      <div class="commits">
        {history.map((commit) => (
          <div class="commit">
            <div class="commit-header">
              <code class="commit-hash">{commit.shortHash}</code>
              <span class="commit-author">{commit.authorName}</span>
              <span class="commit-date">{formatDate(commit.timestamp)}</span>
            </div>
            <div class="commit-message">{commit.message}</div>
          </div>
        ))}
      </div>
    )}
  </div>
</Layout>

<style>
  .commits {
    margin-top: 2rem;
  }

  .commit {
    border: 1px solid #000;
    padding: 1rem;
    margin-bottom: 1rem;
  }

  .commit-header {
    display: flex;
    gap: 1rem;
    align-items: center;
    margin-bottom: 0.5rem;
  }

  .commit-hash {
    font-family: monospace;
    background: #f0f0f0;
    padding: 0.25rem 0.5rem;
  }

  .commit-author {
    font-weight: bold;
  }

  .commit-date {
    color: #666;
    font-size: 0.875rem;
  }

  .commit-message {
    font-size: 0.875rem;
  }
</style>
```

### 7. Add Wiki link to repository navigation

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/index.astro`

Update the repo navigation to include Wiki link:

```astro
<nav class="repo-nav">
  <a href={`/${username}/${reponame}`} class="active">Code</a>
  <a href={`/${username}/${reponame}/issues`}>
    Issues
    {Number(issueCount) > 0 && <span class="badge">{issueCount}</span>}
  </a>
  <a href={`/${username}/${reponame}/commits/${defaultBranch}`}>Commits</a>
  <a href={`/${username}/${reponame}/wiki`}>Wiki</a> {/* NEW */}
</nav>
```

Apply this same change to all repository pages:
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/issues/index.astro`
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/issues/new.astro`
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/issues/[number].astro`
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/commits/[branch].astro`
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/tree/[...path].astro`
- `/Users/williamcory/plue/ui/pages/[user]/[repo]/blob/[...path].astro`

## Implementation Checklist

### Phase 1: Git & Path Infrastructure
- [ ] Add `default_wiki_branch` column to repositories table
- [ ] Run database migration
- [ ] Add wiki repository functions to `ui/lib/git.ts`:
  - [ ] `getWikiRepoPath()`
  - [ ] `getWikiCloneUrl()`
  - [ ] `initWikiRepo()`
  - [ ] `wikiExists()`
  - [ ] `deleteWikiRepo()`
- [ ] Create `ui/lib/wiki.ts` with path conversion utilities:
  - [ ] `validateWikiPath()`
  - [ ] `webPathToGitPath()`
  - [ ] `gitPathToWebPath()`
  - [ ] `webPathToTitle()`
  - [ ] `titleToWebPath()`
  - [ ] `webPathToUrlPath()`

### Phase 2: Wiki CRUD Operations
- [ ] Implement in `ui/lib/wiki.ts`:
  - [ ] `listWikiPages()` - get all wiki pages
  - [ ] `getWikiPage()` - get single page content
  - [ ] `createWikiPage()` - create new page
  - [ ] `updateWikiPage()` - edit existing page
  - [ ] `deleteWikiPage()` - delete page
  - [ ] `getWikiPageHistory()` - get page revision history
- [ ] Test path conversion edge cases (spaces, dashes, special chars)

### Phase 3: API Endpoints
- [ ] Create `server/routes/wiki.ts`
- [ ] Implement endpoints:
  - [ ] `POST /:user/:repo/init` - initialize wiki
  - [ ] `GET /:user/:repo/pages` - list all pages
  - [ ] `GET /:user/:repo/page/:path` - get page
  - [ ] `POST /:user/:repo/page` - create page
  - [ ] `PUT /:user/:repo/page/:path` - update page
  - [ ] `DELETE /:user/:repo/page/:path` - delete page
  - [ ] `GET /:user/:repo/page/:path/history` - page history
  - [ ] `DELETE /:user/:repo` - delete wiki
- [ ] Add validation with Zod schemas
- [ ] Mount wiki routes in `server/routes/index.ts`
- [ ] Test API endpoints with curl/Postman

### Phase 4: UI Pages
- [ ] Create wiki page directory structure
- [ ] Implement pages:
  - [ ] `ui/pages/[user]/[repo]/wiki/index.astro` - wiki home
  - [ ] `ui/pages/[user]/[repo]/wiki/[...page].astro` - page view
  - [ ] `ui/pages/[user]/[repo]/wiki/_new.astro` - new page
  - [ ] `ui/pages/[user]/[repo]/wiki/[page]/_edit.astro` - edit page
  - [ ] `ui/pages/[user]/[repo]/wiki/_pages.astro` - page list
  - [ ] `ui/pages/[user]/[repo]/wiki/[page]/_history.astro` - page history
- [ ] Add Wiki link to repository navigation in all repo pages
- [ ] Test special pages (_Sidebar, _Footer)
- [ ] Test markdown rendering

### Phase 5: Special Pages & Polish
- [ ] Implement `_Sidebar.md` support
- [ ] Implement `_Footer.md` support
- [ ] Add raw file viewing
- [ ] Add page delete confirmation
- [ ] Add empty state for new wikis
- [ ] Add error handling for invalid page names
- [ ] Test responsive layout
- [ ] Add keyboard shortcuts for edit/save

### Phase 6: Testing & Documentation
- [ ] Test wiki initialization
- [ ] Test page CRUD operations
- [ ] Test special characters in page names
- [ ] Test concurrent edits (git conflicts)
- [ ] Test empty wiki state
- [ ] Test markdown rendering edge cases
- [ ] Document wiki features in README
- [ ] Create example wiki pages

## Reference: Gitea Implementation

The implementation is based on Gitea's wiki system:

**Models** (`gitea/models/repo/wiki.go`):
- Wiki path: `{owner}/{repo}.wiki.git`
- Error types: `ErrWikiAlreadyExist`, `ErrWikiReservedName`, `ErrWikiInvalidFileName`

**Services** (`gitea/services/wiki/wiki.go`):
- `InitWiki()` - creates bare git repository
- `updateWikiPage()` - shared logic for add/edit
- `AddWikiPage()` - creates new page
- `EditWikiPage()` - updates existing page
- `DeleteWikiPage()` - removes page
- Uses temporary git clone for operations
- Commits directly to wiki repository

**Path Handling** (`gitea/services/wiki/wiki_path.go`):
- Web path: URL-encoded with dash conversion
- Git path: space-preserved with `.md` extension
- Dash marker (`.-`): prevents dash-space conversion
- Reserved names: `_pages`, `_new`, `_edit`, `raw`

**Web Routes** (`gitea/routers/web/repo/wiki.go`):
- `Wiki()` - main wiki handler with action routing
- `WikiPost()` - handles create/edit/delete via action param
- `WikiPages()` - lists all pages
- `WikiRevision()` - shows page history
- `WikiRaw()` - serves raw files
- Special rendering for `_Sidebar` and `_Footer`

**API Routes** (`gitea/routers/api/v1/repo/wiki.go`):
- `ListWikiPages()` - GET all pages
- `GetWikiPage()` - GET single page
- `NewWikiPage()` - POST create page
- `EditWikiPage()` - PATCH update page
- `DeleteWikiPage()` - DELETE page
- `ListPageRevisions()` - GET page history
- Content encoded as base64

## Notes

- Wiki uses `master` branch by default (Gitea convention)
- Each wiki is a completely separate git repository
- Path conversion handles URL encoding, spaces, and special characters
- Special pages (`_Sidebar`, `_Footer`) are not shown in page lists
- Markdown rendering reuses existing `ui/lib/markdown.ts`
- All git operations use temporary clones for safety
- Commit messages can be customized or auto-generated
- Wiki can be deleted entirely, removing the git repository

## Future Enhancements

After basic implementation, consider:
- Wiki search integration
- Image/file uploads
- Subdirectory support
- Wiki templates
- Table of contents auto-generation
- Wiki export (PDF, HTML)
- Wiki import from other systems
- Collaborative editing with conflict detection
- Wiki analytics (most viewed pages)
