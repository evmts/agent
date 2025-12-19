# Repository Forking Implementation Prompt

## Overview

Add repository forking to Plue - the ability to create a copy of a repository under a user's namespace. This is a core Git forge feature essential for open-source collaboration workflows.

## Scope

**In scope:**
- Fork a repository to user's namespace
- Track fork relationships (parent/children)
- Fork count on repositories
- List forks of a repository

**Out of scope:**
- Starring
- Topics/tags
- Language statistics
- License detection
- Repository templates

## Database Schema Changes

Add to `/Users/williamcory/plue/db/schema.sql`:

```sql
-- Add fork tracking columns to repositories table
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS num_forks INTEGER DEFAULT 0;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS is_fork BOOLEAN DEFAULT false;
ALTER TABLE repositories ADD COLUMN IF NOT EXISTS fork_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL;

CREATE INDEX idx_repositories_fork_id ON repositories(fork_id);
CREATE INDEX idx_repositories_is_fork ON repositories(is_fork) WHERE is_fork = true;
```

## TypeScript Types

```typescript
// core/models/fork.ts
import { z } from 'zod';

export const ForkSchema = z.object({
  id: z.number(),
  name: z.string(),
  full_name: z.string(), // "user/repo"
  owner: z.object({
    id: z.number(),
    username: z.string(),
  }),
  is_fork: z.boolean(),
  fork_id: z.number().nullable(),
  num_forks: z.number(),
  created_at: z.string(),
});

export type Fork = z.infer<typeof ForkSchema>;
```

## Git Operations

Add to `/Users/williamcory/plue/ui/lib/git.ts`:

```typescript
import { $ } from 'bun';

const REPOS_DIR = process.env.REPOS_DIR || './repositories';

/**
 * Fork a repository by cloning it to a new location
 */
export async function forkRepository(
  sourceOwner: string,
  sourceRepo: string,
  targetOwner: string,
  targetRepo: string
): Promise<void> {
  const sourcePath = `${REPOS_DIR}/${sourceOwner}/${sourceRepo}.git`;
  const targetPath = `${REPOS_DIR}/${targetOwner}/${targetRepo}.git`;

  // Create target directory
  await $`mkdir -p ${REPOS_DIR}/${targetOwner}`;

  // Clone bare repository
  await $`git clone --bare ${sourcePath} ${targetPath}`;

  // Update description
  await Bun.write(
    `${targetPath}/description`,
    `Fork of ${sourceOwner}/${sourceRepo}`
  );
}

/**
 * Check if a fork already exists
 */
export async function forkExists(owner: string, repo: string): Promise<boolean> {
  const repoPath = `${REPOS_DIR}/${owner}/${repo}.git`;
  return await Bun.file(repoPath).exists();
}
```

## Database Operations

Create `/Users/williamcory/plue/db/forks.ts`:

```typescript
import { sql } from './index';

export async function createFork(
  userId: number,
  sourceRepoId: number,
  name: string,
  description: string | null
): Promise<number> {
  // Get source repo info
  const [source] = await sql`
    SELECT id, name, description, default_branch, is_public
    FROM repositories WHERE id = ${sourceRepoId}
  `;

  if (!source) throw new Error('Source repository not found');

  // Create fork record
  const [fork] = await sql`
    INSERT INTO repositories (
      user_id, name, description, is_public, default_branch,
      is_fork, fork_id, created_at
    ) VALUES (
      ${userId}, ${name}, ${description || source.description},
      ${source.is_public}, ${source.default_branch},
      true, ${sourceRepoId}, NOW()
    )
    RETURNING id
  `;

  // Increment fork count on source
  await sql`
    UPDATE repositories
    SET num_forks = num_forks + 1
    WHERE id = ${sourceRepoId}
  `;

  return fork.id;
}

export async function getForks(repoId: number): Promise<any[]> {
  return await sql`
    SELECT r.*, u.username as owner_username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.fork_id = ${repoId}
    ORDER BY r.created_at DESC
  `;
}

export async function getParentRepo(repoId: number): Promise<any | null> {
  const [repo] = await sql`
    SELECT r.*, u.username as owner_username
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.id = (SELECT fork_id FROM repositories WHERE id = ${repoId})
  `;
  return repo || null;
}

export async function userHasFork(userId: number, sourceRepoId: number): Promise<boolean> {
  const [result] = await sql`
    SELECT 1 FROM repositories
    WHERE user_id = ${userId} AND fork_id = ${sourceRepoId}
    LIMIT 1
  `;
  return !!result;
}
```

## API Routes

Create `/Users/williamcory/plue/server/routes/forks.ts`:

```typescript
import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { createFork, getForks, userHasFork } from '../../db/forks';
import { forkRepository, forkExists } from '../../ui/lib/git';

const app = new Hono();

// Create a fork
const CreateForkSchema = z.object({
  name: z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/),
});

app.post(
  '/:owner/:repo/forks',
  zValidator('json', CreateForkSchema),
  async (c) => {
    const { owner, repo } = c.req.param();
    const { name } = c.req.valid('json');
    const userId = c.get('userId'); // From auth middleware

    if (!userId) {
      return c.json({ error: 'Authentication required' }, 401);
    }

    // Get source repository
    const sourceRepo = await getRepoByOwnerAndName(owner, repo);
    if (!sourceRepo) {
      return c.json({ error: 'Repository not found' }, 404);
    }

    // Check if user already has a fork
    if (await userHasFork(userId, sourceRepo.id)) {
      return c.json({ error: 'You already have a fork of this repository' }, 409);
    }

    // Check if target repo exists
    const user = await getUserById(userId);
    if (await forkExists(user.username, name)) {
      return c.json({ error: 'Repository name already taken' }, 409);
    }

    // Create fork in git
    await forkRepository(owner, repo, user.username, name);

    // Create fork record in database
    const forkId = await createFork(userId, sourceRepo.id, name, null);

    return c.json({
      id: forkId,
      full_name: `${user.username}/${name}`,
      message: 'Fork created successfully'
    }, 201);
  }
);

// List forks of a repository
app.get('/:owner/:repo/forks', async (c) => {
  const { owner, repo } = c.req.param();

  const sourceRepo = await getRepoByOwnerAndName(owner, repo);
  if (!sourceRepo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const forks = await getForks(sourceRepo.id);

  return c.json({
    total_count: forks.length,
    forks: forks.map(f => ({
      id: f.id,
      name: f.name,
      full_name: `${f.owner_username}/${f.name}`,
      owner: {
        id: f.user_id,
        username: f.owner_username,
      },
      created_at: f.created_at,
    })),
  });
});

export default app;
```

## UI Components

### Fork Button Component

Create `/Users/williamcory/plue/ui/components/ForkButton.astro`:

```astro
---
interface Props {
  owner: string;
  repo: string;
  forkCount: number;
  userHasFork?: boolean;
  userForkUrl?: string;
}

const { owner, repo, forkCount, userHasFork, userForkUrl } = Astro.props;
---

<div class="fork-button">
  {userHasFork ? (
    <a href={userForkUrl} class="btn btn-secondary">
      View your fork
    </a>
  ) : (
    <button
      class="btn btn-primary"
      data-fork-owner={owner}
      data-fork-repo={repo}
      onclick="forkRepo(this)"
    >
      Fork
    </button>
  )}
  <span class="fork-count">{forkCount}</span>
</div>

<script>
async function forkRepo(button: HTMLButtonElement) {
  const owner = button.dataset.forkOwner;
  const repo = button.dataset.forkRepo;

  const name = prompt('Fork name:', repo);
  if (!name) return;

  button.disabled = true;
  button.textContent = 'Forking...';

  try {
    const res = await fetch(`/api/${owner}/${repo}/forks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name }),
    });

    if (!res.ok) {
      const error = await res.json();
      throw new Error(error.error || 'Fork failed');
    }

    const data = await res.json();
    window.location.href = `/${data.full_name}`;
  } catch (err) {
    alert(err.message);
    button.disabled = false;
    button.textContent = 'Fork';
  }
}
</script>

<style>
.fork-button {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
}

.fork-count {
  background: #000;
  color: #fff;
  padding: 0.25rem 0.5rem;
  font-size: 0.875rem;
}
</style>
```

### Fork Banner (shown on forked repos)

Create `/Users/williamcory/plue/ui/components/ForkBanner.astro`:

```astro
---
interface Props {
  parentOwner: string;
  parentRepo: string;
}

const { parentOwner, parentRepo } = Astro.props;
---

<div class="fork-banner">
  forked from <a href={`/${parentOwner}/${parentRepo}`}>{parentOwner}/{parentRepo}</a>
</div>

<style>
.fork-banner {
  background: #f0f0f0;
  padding: 0.5rem 1rem;
  font-size: 0.875rem;
  border-bottom: 1px solid #000;
}

.fork-banner a {
  color: #000;
  font-weight: bold;
}
</style>
```

### Forks Page

Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/forks.astro`:

```astro
---
import Layout from '../../../layouts/Layout.astro';
import { getForks, getRepoByOwnerAndName } from '../../../lib/db';

const { user, repo: repoName } = Astro.params;

const repository = await getRepoByOwnerAndName(user, repoName);
if (!repository) {
  return Astro.redirect('/404');
}

const forks = await getForks(repository.id);
---

<Layout title={`Forks · ${user}/${repoName}`}>
  <main>
    <h1>Forks of {user}/{repoName}</h1>

    {forks.length === 0 ? (
      <p>No forks yet.</p>
    ) : (
      <ul class="forks-list">
        {forks.map(fork => (
          <li>
            <a href={`/${fork.owner_username}/${fork.name}`}>
              {fork.owner_username}/{fork.name}
            </a>
            <span class="date">
              {new Date(fork.created_at).toLocaleDateString()}
            </span>
          </li>
        ))}
      </ul>
    )}
  </main>
</Layout>

<style>
.forks-list {
  list-style: none;
  padding: 0;
}

.forks-list li {
  padding: 1rem;
  border: 1px solid #000;
  margin-bottom: -1px;
  display: flex;
  justify-content: space-between;
}

.forks-list a {
  color: #000;
  font-weight: bold;
}

.date {
  color: #666;
}
</style>
```

## Update Repository Page

Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/index.astro` to include:

1. Fork button in header
2. Fork banner if repo is a fork
3. Fork count display

## Implementation Checklist

### Phase 1: Database
- [ ] Add fork columns to repositories table
- [ ] Create indexes
- [ ] Run migrations

### Phase 2: Backend
- [ ] Create db/forks.ts with CRUD operations
- [ ] Add forkRepository to ui/lib/git.ts
- [ ] Create server/routes/forks.ts
- [ ] Add routes to server/index.ts

### Phase 3: Frontend
- [ ] Create ForkButton.astro component
- [ ] Create ForkBanner.astro component
- [ ] Create forks.astro page
- [ ] Update repository index page with fork button
- [ ] Update repository index to show fork banner

### Phase 4: Testing
- [ ] Test forking a repository
- [ ] Test fork count increments
- [ ] Test viewing forks list
- [ ] Test fork banner displays correctly
- [ ] Test duplicate fork prevention

## Gitea Reference

Key files from Gitea used as reference:
- `models/repo/repo.go` - Fork tracking fields
- `services/repository/fork.go` - Fork creation logic
- `routers/web/repo/repo.go` - Fork API handler
