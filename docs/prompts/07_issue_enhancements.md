# Issue Enhancements Implementation

A comprehensive guide to implementing advanced issue features for Plue, including templates, reactions, multiple assignees, dependencies, locking, and pinning. This implementation is based on Gitea's battle-tested issue system, adapted for Plue's tech stack.

## Tech Stack
- Runtime: Bun
- Backend: Hono API server
- Frontend: Astro v5 (SSR)
- Database: PostgreSQL
- Validation: Zod v4

## Features Overview

1. **Issue Templates** - YAML/Markdown templates in `.github/ISSUE_TEMPLATE/`
2. **Emoji Reactions** - React to issues and comments with emojis
3. **Multiple Assignees** - Assign multiple users to an issue
4. **Issue Dependencies** - Block/blocked-by relationships between issues
5. **Issue Locking** - Prevent further comments (maintainers only)
6. **Issue Pinning** - Pin important issues to the top of the list

---

## 1. Database Schema Changes

### 1.1 Reactions Table

```sql
-- Emoji reactions on issues and comments
CREATE TABLE IF NOT EXISTS reactions (
  id SERIAL PRIMARY KEY,
  type VARCHAR(50) NOT NULL,  -- emoji type ('+1', '-1', 'laugh', 'hooray', 'confused', 'heart', 'rocket', 'eyes')
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  comment_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,  -- NULL for issue reactions
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(type, issue_id, comment_id, user_id)  -- One reaction per user per type per target
);

CREATE INDEX idx_reactions_issue ON reactions(issue_id);
CREATE INDEX idx_reactions_comment ON reactions(comment_id);
CREATE INDEX idx_reactions_user ON reactions(user_id);
```

### 1.2 Issue Assignees Table

```sql
-- Multiple assignees support (replaces single assignee_id)
CREATE TABLE IF NOT EXISTS issue_assignees (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  assignee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(issue_id, assignee_id)
);

CREATE INDEX idx_issue_assignees_issue ON issue_assignees(issue_id);
CREATE INDEX idx_issue_assignees_user ON issue_assignees(assignee_id);
```

### 1.3 Issue Dependencies Table

```sql
-- Issue blocks/blocked-by relationships
CREATE TABLE IF NOT EXISTS issue_dependencies (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,  -- The issue that is blocked
  dependency_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,  -- The blocking issue
  user_id INTEGER NOT NULL REFERENCES users(id),  -- Who created the dependency
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(issue_id, dependency_id)
);

CREATE INDEX idx_issue_dependencies_issue ON issue_dependencies(issue_id);
CREATE INDEX idx_issue_dependencies_dependency ON issue_dependencies(dependency_id);
```

### 1.4 Issue Pins Table

```sql
-- Pinned issues
CREATE TABLE IF NOT EXISTS issue_pins (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  pin_order INTEGER NOT NULL DEFAULT 0,  -- Order of pinned issues (lower = higher priority)
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, issue_id)
);

CREATE INDEX idx_issue_pins_repo ON issue_pins(repository_id);
CREATE INDEX idx_issue_pins_order ON issue_pins(repository_id, pin_order);
```

### 1.5 Update Issues Table

```sql
-- Add new columns to issues table
ALTER TABLE issues ADD COLUMN IF NOT EXISTS is_locked BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE issues ADD COLUMN IF NOT EXISTS locked_at TIMESTAMP;
ALTER TABLE issues ADD COLUMN IF NOT EXISTS locked_by INTEGER REFERENCES users(id);
```

### 1.6 Migration Script

Create `/Users/williamcory/plue/db/migrations/002_issue_enhancements.sql`:

```sql
-- Run all the CREATE TABLE statements above
-- This migration adds reactions, assignees, dependencies, and pinning
```

---

## 2. TypeScript Type Definitions

Add to `/Users/williamcory/plue/ui/lib/types.ts`:

```typescript
// Reaction types (GitHub-compatible emoji set)
export type ReactionType = '+1' | '-1' | 'laugh' | 'hooray' | 'confused' | 'heart' | 'rocket' | 'eyes';

export interface Reaction {
  id: number;
  type: ReactionType;
  issue_id: number;
  comment_id: number | null;
  user_id: number;
  user?: User;
  created_at: Date;
}

export interface IssueAssignee {
  id: number;
  issue_id: number;
  assignee_id: number;
  assignee?: User;
  created_at: Date;
}

export interface IssueDependency {
  id: number;
  issue_id: number;  // Issue that is blocked
  dependency_id: number;  // Issue that blocks
  user_id: number;
  issue?: Issue;  // The blocking issue details
  created_at: Date;
  updated_at: Date;
}

export interface IssuePin {
  id: number;
  repository_id: number;
  issue_id: number;
  pin_order: number;
  created_at: Date;
}

// Issue template types
export interface IssueTemplate {
  name: string;
  description?: string;
  title?: string;
  labels?: string[];
  assignees?: string[];
  body: IssueTemplateField[];
}

export type IssueTemplateField =
  | { type: 'markdown'; attributes: { value: string } }
  | { type: 'textarea'; id: string; attributes: { label: string; description?: string; placeholder?: string }; validations?: { required?: boolean } }
  | { type: 'input'; id: string; attributes: { label: string; description?: string; placeholder?: string }; validations?: { required?: boolean } }
  | { type: 'dropdown'; id: string; attributes: { label: string; description?: string; options: string[] }; validations?: { required?: boolean } }
  | { type: 'checkboxes'; id: string; attributes: { label: string; description?: string; options: Array<{ label: string; required?: boolean }> }; validations?: { required?: boolean } };

export interface IssueTemplateConfig {
  blank_issues_enabled: boolean;
  contact_links?: Array<{
    name: string;
    url: string;
    about: string;
  }>;
}
```

---

## 3. Reaction System

### 3.1 Reaction Constants

Create `/Users/williamcory/plue/server/lib/reactions.ts`:

```typescript
import { z } from 'zod';

// GitHub-compatible reaction types
export const ALLOWED_REACTIONS = [
  '+1',      // 👍
  '-1',      // 👎
  'laugh',   // 😄
  'hooray',  // 🎉
  'confused', // 😕
  'heart',   // ❤️
  'rocket',  // 🚀
  'eyes'     // 👀
] as const;

export const ReactionSchema = z.object({
  type: z.enum(ALLOWED_REACTIONS),
  issue_id: z.number().int().positive(),
  comment_id: z.number().int().positive().optional(),
});

export type ReactionInput = z.infer<typeof ReactionSchema>;

// Map reaction type to emoji
export const REACTION_EMOJI: Record<string, string> = {
  '+1': '👍',
  '-1': '👎',
  'laugh': '😄',
  'hooray': '🎉',
  'confused': '😕',
  'heart': '❤️',
  'rocket': '🚀',
  'eyes': '👀',
};
```

### 3.2 Reaction API Endpoints

Add to `/Users/williamcory/plue/server/routes/reactions.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';
import { ReactionSchema, ALLOWED_REACTIONS } from '../lib/reactions';

const reactions = new Hono();

// GET /repos/:user/:repo/issues/:number/reactions
reactions.get('/:user/:repo/issues/:number/reactions', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Get reactions (issue-level only, comment_id is NULL)
  const reactions = await sql`
    SELECT r.*, u.username, u.display_name
    FROM reactions r
    JOIN users u ON r.user_id = u.id
    WHERE r.issue_id = ${issue.id} AND r.comment_id IS NULL
    ORDER BY r.created_at ASC
  `;

  return c.json(reactions);
});

// POST /repos/:user/:repo/issues/:number/reactions
reactions.post('/:user/:repo/issues/:number/reactions', async (c) => {
  const { user, repo, number } = c.req.param();
  const body = await c.req.json();

  // Validate
  const parsed = ReactionSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid reaction', details: parsed.error }, 400);
  }

  // Get current user (mock - replace with real auth)
  const userId = body.user_id || 1;

  // Get issue
  const [issue] = await sql`
    SELECT i.id, i.is_locked FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Check if issue is locked
  if (issue.is_locked) {
    return c.json({ error: 'Issue is locked' }, 403);
  }

  // Create reaction (or return existing)
  try {
    const [reaction] = await sql`
      INSERT INTO reactions (type, issue_id, user_id)
      VALUES (${parsed.data.type}, ${issue.id}, ${userId})
      ON CONFLICT (type, issue_id, comment_id, user_id) DO UPDATE
      SET created_at = reactions.created_at
      RETURNING *
    `;

    return c.json(reaction, 201);
  } catch (error) {
    return c.json({ error: 'Failed to create reaction' }, 500);
  }
});

// DELETE /repos/:user/:repo/issues/:number/reactions/:type
reactions.delete('/:user/:repo/issues/:number/reactions/:type', async (c) => {
  const { user, repo, number, type } = c.req.param();

  if (!ALLOWED_REACTIONS.includes(type as any)) {
    return c.json({ error: 'Invalid reaction type' }, 400);
  }

  // Get current user (mock - replace with real auth)
  const userId = c.req.query('user_id') || 1;

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Delete reaction
  await sql`
    DELETE FROM reactions
    WHERE type = ${type} AND issue_id = ${issue.id}
    AND comment_id IS NULL AND user_id = ${userId}
  `;

  return c.json({ success: true }, 200);
});

export default reactions;
```

### 3.3 Reaction UI Component

Create `/Users/williamcory/plue/ui/components/ReactionPicker.astro`:

```astro
---
import { REACTION_EMOJI } from '../../server/lib/reactions';

interface Props {
  issueId: number;
  commentId?: number;
  reactions: Array<{ type: string; count: number; users: string[]; userReacted: boolean }>;
}

const { issueId, commentId, reactions } = Astro.props;
---

<div class="reactions">
  {reactions.map(({ type, count, users, userReacted }) => (
    <button
      class:list={['reaction-button', { active: userReacted }]}
      data-type={type}
      data-issue-id={issueId}
      data-comment-id={commentId}
      title={users.join(', ')}
    >
      <span class="emoji">{REACTION_EMOJI[type]}</span>
      <span class="count">{count}</span>
    </button>
  ))}

  <button class="reaction-picker-trigger" aria-label="Add reaction">
    <span class="emoji">😊</span>
    <span class="plus">+</span>
  </button>
</div>

<style>
  .reactions {
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
    margin-top: 8px;
  }

  .reaction-button {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 8px;
    border: 1px solid var(--border);
    background: var(--bg);
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
  }

  .reaction-button:hover {
    background: var(--bg-hover);
  }

  .reaction-button.active {
    background: var(--primary-bg);
    border-color: var(--primary);
  }

  .reaction-picker-trigger {
    padding: 4px 6px;
    border: 1px solid var(--border);
    background: var(--bg);
    border-radius: 4px;
    cursor: pointer;
  }

  .reaction-picker-trigger:hover {
    background: var(--bg-hover);
  }

  .emoji {
    font-size: 14px;
    line-height: 1;
  }

  .plus {
    font-size: 10px;
    color: var(--text-muted);
  }

  .count {
    color: var(--text-muted);
    font-weight: 500;
  }
</style>

<script>
  // Client-side reaction handling
  document.querySelectorAll('.reaction-button').forEach(button => {
    button.addEventListener('click', async (e) => {
      const target = e.currentTarget as HTMLElement;
      const type = target.dataset.type;
      const issueId = target.dataset.issueId;
      const commentId = target.dataset.commentId;

      // Toggle reaction via API
      // TODO: Implement actual API call
      console.log('Toggle reaction:', { type, issueId, commentId });
    });
  });
</script>
```

---

## 4. Multiple Assignees

### 4.1 Assignee API Endpoints

Add to `/Users/williamcory/plue/server/routes/assignees.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';

const assignees = new Hono();

// POST /repos/:user/:repo/issues/:number/assignees
// Add assignees to an issue
assignees.post('/:user/:repo/issues/:number/assignees', async (c) => {
  const { user, repo, number } = c.req.param();
  const { assignees: assigneeUsernames } = await c.req.json();

  if (!Array.isArray(assigneeUsernames) || assigneeUsernames.length === 0) {
    return c.json({ error: 'Invalid assignees' }, 400);
  }

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Get user IDs
  const users = await sql`
    SELECT id, username FROM users WHERE username = ANY(${assigneeUsernames})
  `;

  if (users.length === 0) {
    return c.json({ error: 'No valid users found' }, 400);
  }

  // Insert assignees (ignore duplicates)
  for (const assignee of users) {
    await sql`
      INSERT INTO issue_assignees (issue_id, assignee_id)
      VALUES (${issue.id}, ${assignee.id})
      ON CONFLICT (issue_id, assignee_id) DO NOTHING
    `;
  }

  // Return updated assignees
  const updatedAssignees = await sql`
    SELECT u.id, u.username, u.display_name
    FROM issue_assignees ia
    JOIN users u ON ia.assignee_id = u.id
    WHERE ia.issue_id = ${issue.id}
  `;

  return c.json(updatedAssignees);
});

// DELETE /repos/:user/:repo/issues/:number/assignees
// Remove assignees from an issue
assignees.delete('/:user/:repo/issues/:number/assignees', async (c) => {
  const { user, repo, number } = c.req.param();
  const { assignees: assigneeUsernames } = await c.req.json();

  if (!Array.isArray(assigneeUsernames) || assigneeUsernames.length === 0) {
    return c.json({ error: 'Invalid assignees' }, 400);
  }

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Get user IDs
  const users = await sql`
    SELECT id FROM users WHERE username = ANY(${assigneeUsernames})
  `;

  // Remove assignees
  await sql`
    DELETE FROM issue_assignees
    WHERE issue_id = ${issue.id} AND assignee_id = ANY(${users.map(u => u.id)})
  `;

  return c.json({ success: true });
});

export default assignees;
```

### 4.2 Assignee Picker Component

Create `/Users/williamcory/plue/ui/components/AssigneePicker.astro`:

```astro
---
interface Props {
  assignees: Array<{ id: number; username: string; display_name: string | null }>;
  availableUsers: Array<{ id: number; username: string; display_name: string | null }>;
}

const { assignees, availableUsers } = Astro.props;
---

<div class="assignee-picker">
  <div class="assignee-list">
    {assignees.length === 0 ? (
      <p class="text-muted">No assignees</p>
    ) : (
      assignees.map(assignee => (
        <div class="assignee">
          <span>{assignee.username}</span>
          <button class="remove-btn" data-user-id={assignee.id}>×</button>
        </div>
      ))
    )}
  </div>

  <div class="assignee-add">
    <select class="assignee-select">
      <option value="">Add assignee...</option>
      {availableUsers.map(user => (
        <option value={user.id}>{user.username}</option>
      ))}
    </select>
  </div>
</div>

<style>
  .assignee-picker {
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
  }

  .assignee-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-bottom: 12px;
  }

  .assignee {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 8px;
    background: var(--bg-secondary);
    border-radius: 4px;
  }

  .remove-btn {
    background: none;
    border: none;
    color: var(--text-muted);
    cursor: pointer;
    font-size: 18px;
    padding: 0 4px;
  }

  .remove-btn:hover {
    color: var(--error);
  }

  .assignee-select {
    width: 100%;
  }
</style>
```

---

## 5. Issue Dependencies

### 5.1 Dependency Validation Helper

Create `/Users/williamcory/plue/server/lib/dependencies.ts`:

```typescript
import { sql } from '../../ui/lib/db';

/**
 * Check if creating a dependency would create a circular dependency
 */
export async function wouldCreateCircularDependency(
  issueId: number,
  dependencyId: number
): Promise<boolean> {
  // Check if dependency already blocks issue (would create A->B->A)
  const [existing] = await sql`
    SELECT 1 FROM issue_dependencies
    WHERE issue_id = ${dependencyId} AND dependency_id = ${issueId}
  `;

  return !!existing;
}

/**
 * Check if issue has open dependencies (blocks closing)
 */
export async function hasOpenDependencies(issueId: number): Promise<boolean> {
  const [result] = await sql`
    SELECT COUNT(*) as count
    FROM issue_dependencies dep
    JOIN issues blocking ON dep.dependency_id = blocking.id
    WHERE dep.issue_id = ${issueId} AND blocking.state = 'open'
  `;

  return result.count > 0;
}
```

### 5.2 Dependency API Endpoints

Add to `/Users/williamcory/plue/server/routes/dependencies.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';
import { wouldCreateCircularDependency, hasOpenDependencies } from '../lib/dependencies';

const dependencies = new Hono();

// GET /repos/:user/:repo/issues/:number/dependencies
// List issues that block this issue
dependencies.get('/:user/:repo/issues/:number/dependencies', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Get blocking issues
  const blockingIssues = await sql`
    SELECT
      i.id, i.issue_number, i.title, i.state, i.created_at,
      u.username as author_username
    FROM issue_dependencies dep
    JOIN issues i ON dep.dependency_id = i.id
    JOIN users u ON i.author_id = u.id
    WHERE dep.issue_id = ${issue.id}
    ORDER BY i.created_at DESC
  `;

  return c.json(blockingIssues);
});

// GET /repos/:user/:repo/issues/:number/blocks
// List issues blocked by this issue
dependencies.get('/:user/:repo/issues/:number/blocks', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue
  const [issue] = await sql`
    SELECT i.id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Get blocked issues
  const blockedIssues = await sql`
    SELECT
      i.id, i.issue_number, i.title, i.state, i.created_at,
      u.username as author_username
    FROM issue_dependencies dep
    JOIN issues i ON dep.issue_id = i.id
    JOIN users u ON i.author_id = u.id
    WHERE dep.dependency_id = ${issue.id}
    ORDER BY i.created_at DESC
  `;

  return c.json(blockedIssues);
});

// POST /repos/:user/:repo/issues/:number/dependencies
// Add a blocking issue
dependencies.post('/:user/:repo/issues/:number/dependencies', async (c) => {
  const { user, repo, number } = c.req.param();
  const { dependency_issue_number } = await c.req.json();

  // Get current user (mock)
  const userId = 1;

  // Get both issues
  const [issue, dependencyIssue] = await Promise.all([
    sql`
      SELECT i.id, i.repository_id FROM issues i
      JOIN repositories r ON i.repository_id = r.id
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
    `.then(rows => rows[0]),
    sql`
      SELECT i.id FROM issues i
      JOIN repositories r ON i.repository_id = r.id
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${dependency_issue_number}
    `.then(rows => rows[0])
  ]);

  if (!issue || !dependencyIssue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Check for circular dependency
  if (await wouldCreateCircularDependency(issue.id, dependencyIssue.id)) {
    return c.json({ error: 'Would create circular dependency' }, 400);
  }

  // Create dependency
  try {
    await sql`
      INSERT INTO issue_dependencies (issue_id, dependency_id, user_id)
      VALUES (${issue.id}, ${dependencyIssue.id}, ${userId})
    `;

    return c.json({ success: true }, 201);
  } catch (error) {
    return c.json({ error: 'Dependency already exists' }, 400);
  }
});

// DELETE /repos/:user/:repo/issues/:number/dependencies/:dependency_number
dependencies.delete('/:user/:repo/issues/:number/dependencies/:dependency_number', async (c) => {
  const { user, repo, number, dependency_number } = c.req.param();

  // Get both issues
  const [issue, dependencyIssue] = await Promise.all([
    sql`
      SELECT i.id FROM issues i
      JOIN repositories r ON i.repository_id = r.id
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
    `.then(rows => rows[0]),
    sql`
      SELECT i.id FROM issues i
      JOIN repositories r ON i.repository_id = r.id
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${dependency_number}
    `.then(rows => rows[0])
  ]);

  if (!issue || !dependencyIssue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Remove dependency
  await sql`
    DELETE FROM issue_dependencies
    WHERE issue_id = ${issue.id} AND dependency_id = ${dependencyIssue.id}
  `;

  return c.json({ success: true });
});

export default dependencies;
```

### 5.3 Dependencies UI Component

Create `/Users/williamcory/plue/ui/components/IssueDependencies.astro`:

```astro
---
interface Dependency {
  issue_number: number;
  title: string;
  state: string;
  author_username: string;
}

interface Props {
  blockedBy: Dependency[];
  blocking: Dependency[];
  repoUser: string;
  repoName: string;
}

const { blockedBy, blocking, repoUser, repoName } = Astro.props;
---

<div class="dependencies">
  <div class="dependency-section">
    <h3 class="section-title">Blocked by</h3>
    {blockedBy.length === 0 ? (
      <p class="text-muted text-sm">No blocking issues</p>
    ) : (
      <ul class="dependency-list">
        {blockedBy.map(dep => (
          <li>
            <a href={`/${repoUser}/${repoName}/issues/${dep.issue_number}`}>
              #{dep.issue_number} {dep.title}
            </a>
            <span class:list={['state', dep.state]}>{dep.state}</span>
          </li>
        ))}
      </ul>
    )}
  </div>

  <div class="dependency-section">
    <h3 class="section-title">Blocks</h3>
    {blocking.length === 0 ? (
      <p class="text-muted text-sm">Not blocking any issues</p>
    ) : (
      <ul class="dependency-list">
        {blocking.map(dep => (
          <li>
            <a href={`/${repoUser}/${repoName}/issues/${dep.issue_number}`}>
              #{dep.issue_number} {dep.title}
            </a>
            <span class:list={['state', dep.state]}>{dep.state}</span>
          </li>
        ))}
      </ul>
    )}
  </div>
</div>

<style>
  .dependencies {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
  }

  .section-title {
    font-size: 14px;
    font-weight: 600;
    margin-bottom: 8px;
  }

  .dependency-list {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  .dependency-list li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 0;
    border-bottom: 1px solid var(--border-light);
  }

  .dependency-list li:last-child {
    border-bottom: none;
  }

  .state {
    font-size: 12px;
    padding: 2px 6px;
    border-radius: 3px;
  }

  .state.open {
    background: var(--success-bg);
    color: var(--success);
  }

  .state.closed {
    background: var(--error-bg);
    color: var(--error);
  }
</style>
```

---

## 6. Issue Locking

### 6.1 Lock API Endpoints

Add to `/Users/williamcory/plue/server/routes/lock.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';

const lock = new Hono();

// PUT /repos/:user/:repo/issues/:number/lock
lock.put('/:user/:repo/issues/:number/lock', async (c) => {
  const { user, repo, number } = c.req.param();
  const { reason } = await c.req.json();

  // Get current user (mock)
  const userId = 1;

  // Get issue
  const [issue] = await sql`
    SELECT i.id, i.is_locked FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  if (issue.is_locked) {
    return c.json({ error: 'Issue already locked' }, 400);
  }

  // Lock issue
  await sql`
    UPDATE issues
    SET is_locked = true, locked_at = NOW(), locked_by = ${userId}
    WHERE id = ${issue.id}
  `;

  // TODO: Add comment about lock with reason

  return c.json({ success: true, reason });
});

// DELETE /repos/:user/:repo/issues/:number/lock
lock.delete('/:user/:repo/issues/:number/lock', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue
  const [issue] = await sql`
    SELECT i.id, i.is_locked FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  if (!issue.is_locked) {
    return c.json({ error: 'Issue not locked' }, 400);
  }

  // Unlock issue
  await sql`
    UPDATE issues
    SET is_locked = false, locked_at = NULL, locked_by = NULL
    WHERE id = ${issue.id}
  `;

  // TODO: Add comment about unlock

  return c.json({ success: true });
});

export default lock;
```

---

## 7. Issue Pinning

### 7.1 Pin API Endpoints

Add to `/Users/williamcory/plue/server/routes/pins.ts`:

```typescript
import { Hono } from 'hono';
import { sql } from '../../ui/lib/db';

const pins = new Hono();

const MAX_PINNED_ISSUES = 3;

// GET /repos/:user/:repo/issues/pinned
pins.get('/:user/:repo/issues/pinned', async (c) => {
  const { user, repo } = c.req.param();

  // Get repository
  const [repository] = await sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Get pinned issues
  const pinned = await sql`
    SELECT
      i.id, i.issue_number, i.title, i.state, i.created_at,
      u.username as author_username,
      ip.pin_order
    FROM issue_pins ip
    JOIN issues i ON ip.issue_id = i.id
    JOIN users u ON i.author_id = u.id
    WHERE ip.repository_id = ${repository.id}
    ORDER BY ip.pin_order ASC
  `;

  return c.json(pinned);
});

// POST /repos/:user/:repo/issues/:number/pin
pins.post('/:user/:repo/issues/:number/pin', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue with repo
  const [issue] = await sql`
    SELECT i.id, i.repository_id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Check max pins
  const [{ count }] = await sql`
    SELECT COUNT(*) as count FROM issue_pins WHERE repository_id = ${issue.repository_id}
  `;

  if (count >= MAX_PINNED_ISSUES) {
    return c.json({ error: `Maximum ${MAX_PINNED_ISSUES} pinned issues reached` }, 400);
  }

  // Get next pin order
  const [{ max_order }] = await sql`
    SELECT COALESCE(MAX(pin_order), 0) as max_order
    FROM issue_pins WHERE repository_id = ${issue.repository_id}
  `;

  // Pin issue
  try {
    await sql`
      INSERT INTO issue_pins (repository_id, issue_id, pin_order)
      VALUES (${issue.repository_id}, ${issue.id}, ${max_order + 1})
    `;

    return c.json({ success: true }, 201);
  } catch (error) {
    return c.json({ error: 'Issue already pinned' }, 400);
  }
});

// DELETE /repos/:user/:repo/issues/:number/pin
pins.delete('/:user/:repo/issues/:number/pin', async (c) => {
  const { user, repo, number } = c.req.param();

  // Get issue
  const [issue] = await sql`
    SELECT i.id, i.repository_id FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Unpin issue
  await sql`
    DELETE FROM issue_pins
    WHERE repository_id = ${issue.repository_id} AND issue_id = ${issue.id}
  `;

  // Reorder remaining pins
  await sql`
    WITH ordered AS (
      SELECT id, ROW_NUMBER() OVER (ORDER BY pin_order) as new_order
      FROM issue_pins
      WHERE repository_id = ${issue.repository_id}
    )
    UPDATE issue_pins
    SET pin_order = ordered.new_order
    FROM ordered
    WHERE issue_pins.id = ordered.id
  `;

  return c.json({ success: true });
});

// PATCH /repos/:user/:repo/issues/:number/pin/:position
// Move pinned issue to new position
pins.patch('/:user/:repo/issues/:number/pin/:position', async (c) => {
  const { user, repo, number, position } = c.req.param();
  const newPosition = parseInt(position);

  if (isNaN(newPosition) || newPosition < 1) {
    return c.json({ error: 'Invalid position' }, 400);
  }

  // Get issue and current pin
  const [result] = await sql`
    SELECT i.id, i.repository_id, ip.pin_order
    FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    JOIN users u ON r.user_id = u.id
    JOIN issue_pins ip ON ip.issue_id = i.id
    WHERE u.username = ${user} AND r.name = ${repo} AND i.issue_number = ${number}
  `;

  if (!result) {
    return c.json({ error: 'Pinned issue not found' }, 404);
  }

  const { id, repository_id, pin_order: currentOrder } = result;

  if (currentOrder === newPosition) {
    return c.json({ success: true });
  }

  // Shift other pins
  if (newPosition < currentOrder) {
    // Moving up, shift down
    await sql`
      UPDATE issue_pins
      SET pin_order = pin_order + 1
      WHERE repository_id = ${repository_id}
      AND pin_order >= ${newPosition}
      AND pin_order < ${currentOrder}
    `;
  } else {
    // Moving down, shift up
    await sql`
      UPDATE issue_pins
      SET pin_order = pin_order - 1
      WHERE repository_id = ${repository_id}
      AND pin_order > ${currentOrder}
      AND pin_order <= ${newPosition}
    `;
  }

  // Update pin position
  await sql`
    UPDATE issue_pins
    SET pin_order = ${newPosition}
    WHERE issue_id = ${id}
  `;

  return c.json({ success: true });
});

export default pins;
```

---

## 8. Issue Templates

### 8.1 Template Parser

Create `/Users/williamcory/plue/server/lib/issue-templates.ts`:

```typescript
import * as yaml from 'yaml';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

export interface IssueTemplate {
  name: string;
  description?: string;
  title?: string;
  labels?: string[];
  assignees?: string[];
  body: IssueTemplateField[];
}

export type IssueTemplateField =
  | { type: 'markdown'; attributes: { value: string } }
  | { type: 'textarea'; id: string; attributes: { label: string; description?: string; placeholder?: string }; validations?: { required?: boolean } }
  | { type: 'input'; id: string; attributes: { label: string; description?: string; placeholder?: string }; validations?: { required?: boolean } }
  | { type: 'dropdown'; id: string; attributes: { label: string; description?: string; options: string[] }; validations?: { required?: boolean } }
  | { type: 'checkboxes'; id: string; attributes: { label: string; description?: string; options: Array<{ label: string; required?: boolean }> }; validations?: { required?: boolean } };

export interface IssueTemplateConfig {
  blank_issues_enabled: boolean;
  contact_links?: Array<{
    name: string;
    url: string;
    about: string;
  }>;
}

/**
 * Load issue templates from .github/ISSUE_TEMPLATE directory
 */
export async function loadIssueTemplates(repoPath: string): Promise<{
  templates: IssueTemplate[];
  config: IssueTemplateConfig | null;
}> {
  const templateDir = join(repoPath, '.github', 'ISSUE_TEMPLATE');

  let templates: IssueTemplate[] = [];
  let config: IssueTemplateConfig | null = null;

  try {
    const files = await readdir(templateDir);

    for (const file of files) {
      const filePath = join(templateDir, file);
      const content = await readFile(filePath, 'utf-8');

      // Parse config.yml
      if (file === 'config.yml' || file === 'config.yaml') {
        try {
          config = yaml.parse(content);
        } catch (error) {
          console.error('Failed to parse config.yml:', error);
        }
        continue;
      }

      // Parse YAML templates
      if (file.endsWith('.yml') || file.endsWith('.yaml')) {
        try {
          const template = yaml.parse(content);
          templates.push(template);
        } catch (error) {
          console.error(`Failed to parse template ${file}:`, error);
        }
      }

      // Parse Markdown templates (legacy)
      if (file.endsWith('.md')) {
        try {
          templates.push(parseMarkdownTemplate(file, content));
        } catch (error) {
          console.error(`Failed to parse markdown template ${file}:`, error);
        }
      }
    }
  } catch (error) {
    // Directory doesn't exist or can't be read
    return { templates: [], config: null };
  }

  return { templates, config };
}

/**
 * Parse legacy Markdown issue template
 */
function parseMarkdownTemplate(filename: string, content: string): IssueTemplate {
  // Extract front matter if present
  const frontMatterMatch = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);

  let frontMatter: any = {};
  let body = content;

  if (frontMatterMatch) {
    frontMatter = yaml.parse(frontMatterMatch[1]);
    body = frontMatterMatch[2];
  }

  return {
    name: frontMatter.name || filename.replace(/\.md$/, ''),
    description: frontMatter.about,
    title: frontMatter.title,
    labels: frontMatter.labels,
    assignees: frontMatter.assignees,
    body: [
      {
        type: 'textarea',
        id: 'description',
        attributes: {
          label: 'Description',
          value: body.trim(),
        },
      },
    ],
  };
}

/**
 * Render template to initial issue body
 */
export function renderTemplate(template: IssueTemplate, data: Record<string, any>): string {
  let output = '';

  for (const field of template.body) {
    switch (field.type) {
      case 'markdown':
        output += field.attributes.value + '\n\n';
        break;

      case 'textarea':
      case 'input':
        if (data[field.id]) {
          output += `### ${field.attributes.label}\n${data[field.id]}\n\n`;
        }
        break;

      case 'dropdown':
        if (data[field.id]) {
          output += `### ${field.attributes.label}\n${data[field.id]}\n\n`;
        }
        break;

      case 'checkboxes':
        if (data[field.id]) {
          output += `### ${field.attributes.label}\n`;
          const selected = Array.isArray(data[field.id]) ? data[field.id] : [data[field.id]];
          for (const option of field.attributes.options) {
            const checked = selected.includes(option.label);
            output += `- [${checked ? 'x' : ' '}] ${option.label}\n`;
          }
          output += '\n';
        }
        break;
    }
  }

  return output.trim();
}
```

### 8.2 Template Selection Page

Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/issues/new.astro`:

```astro
---
import Layout from "../../../../layouts/Layout.astro";
import Header from "../../../../components/Header.astro";
import { sql } from "../../../../lib/db";
import { loadIssueTemplates } from "../../../../server/lib/issue-templates";
import type { User, Repository } from "../../../../lib/types";

const { user: username, repo: reponame } = Astro.params;
const templateName = Astro.url.searchParams.get("template");

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];

if (!repo) return Astro.redirect("/404");

// Load templates
const repoPath = `/path/to/repos/${username}/${reponame}`;
const { templates, config } = await loadIssueTemplates(repoPath);

// If no template selected, show template chooser
if (!templateName && templates.length > 0) {
  // Render template chooser UI
}

// Get selected template
const template = templates.find(t => t.name === templateName);

// Handle form submission
if (Astro.request.method === "POST") {
  const formData = await Astro.request.formData();
  const title = formData.get("title") as string;
  const body = formData.get("body") as string;

  // Create issue...
}
---

<!-- Template chooser or form UI -->
```

---

## 9. Implementation Checklist

### Phase 1: Database & Core APIs
- [ ] Run database migrations for all new tables
- [ ] Create TypeScript type definitions
- [ ] Implement reaction API endpoints
- [ ] Implement assignee API endpoints
- [ ] Implement dependency API endpoints
- [ ] Implement locking API endpoints
- [ ] Implement pinning API endpoints
- [ ] Add circular dependency validation
- [ ] Add open dependency validation for closing issues

### Phase 2: UI Components
- [ ] Build ReactionPicker component with emoji support
- [ ] Build AssigneePicker component with multi-select
- [ ] Build IssueDependencies component showing blocked/blocking
- [ ] Add lock/unlock buttons to issue page
- [ ] Add pin/unpin buttons to issue page (maintainers only)
- [ ] Update issue list page to show pinned issues at top
- [ ] Add visual indicators for locked issues
- [ ] Show assignee avatars on issue cards

### Phase 3: Issue Templates
- [ ] Implement template parser for YAML and Markdown
- [ ] Create template selection UI on /issues/new
- [ ] Render template form fields dynamically
- [ ] Parse and validate template form submissions
- [ ] Support config.yml for template configuration
- [ ] Add template preview in issue creation
- [ ] Document template syntax for users

### Phase 4: Integration & Polish
- [ ] Wire up all API routes to Hono server
- [ ] Add permission checks (read/write access)
- [ ] Implement real-time updates for reactions (optional)
- [ ] Add activity feed entries for all new actions
- [ ] Update issue search/filter to include dependencies
- [ ] Add keyboard shortcuts for reactions
- [ ] Add tests for circular dependency detection
- [ ] Add tests for template parsing
- [ ] Document all new API endpoints
- [ ] Create migration guide from current schema

### Phase 5: Advanced Features (Optional)
- [ ] Dependency graph visualization
- [ ] Bulk issue operations (assign, pin, lock)
- [ ] Issue template metrics and analytics
- [ ] Custom reaction types (beyond GitHub's 8)
- [ ] Dependency notification system
- [ ] Pin reordering via drag-and-drop

---

## 10. Reference Code from Gitea

### Gitea Model Structures (Go → TypeScript Translation)

**Reaction Model** (`models/issues/reaction.go`)
```go
type Reaction struct {
    ID               int64
    Type             string  // emoji type
    IssueID          int64
    CommentID        int64
    UserID           int64
    OriginalAuthorID int64
    OriginalAuthor   string
    User             *user_model.User
    CreatedUnix      timeutil.TimeStamp
}
```

**IssueDependency Model** (`models/issues/dependency.go`)
```go
type IssueDependency struct {
    ID           int64
    UserID       int64
    IssueID      int64
    DependencyID int64
    CreatedUnix  timeutil.TimeStamp
    UpdatedUnix  timeutil.TimeStamp
}
```

**IssuePin Model** (`models/issues/issue_pin.go`)
```go
type IssuePin struct {
    ID       int64
    RepoID   int64
    IssueID  int64
    IsPull   bool
    PinOrder int
}
```

**IssueAssignees Model** (`models/issues/assignees.go`)
```go
type IssueAssignees struct {
    ID         int64
    AssigneeID int64
    IssueID    int64
}
```

### Key Gitea Functions to Reference

1. **Circular Dependency Check** - `issueDepExists()` in `dependency.go`
2. **Pin Order Management** - `MovePin()` in `issue_pin.go`
3. **Reaction Validation** - `CreateReaction()` in `reaction.go`
4. **Lock/Unlock Logic** - `updateIssueLock()` in `issue_lock.go`

---

## 11. API Endpoint Summary

### Reactions
- `GET /repos/:user/:repo/issues/:number/reactions` - List reactions
- `POST /repos/:user/:repo/issues/:number/reactions` - Add reaction
- `DELETE /repos/:user/:repo/issues/:number/reactions/:type` - Remove reaction
- `GET /repos/:user/:repo/issues/:number/comments/:id/reactions` - Comment reactions
- `POST /repos/:user/:repo/issues/:number/comments/:id/reactions` - Add comment reaction

### Assignees
- `POST /repos/:user/:repo/issues/:number/assignees` - Add assignees
- `DELETE /repos/:user/:repo/issues/:number/assignees` - Remove assignees

### Dependencies
- `GET /repos/:user/:repo/issues/:number/dependencies` - List blocking issues
- `GET /repos/:user/:repo/issues/:number/blocks` - List blocked issues
- `POST /repos/:user/:repo/issues/:number/dependencies` - Add dependency
- `DELETE /repos/:user/:repo/issues/:number/dependencies/:id` - Remove dependency

### Locking
- `PUT /repos/:user/:repo/issues/:number/lock` - Lock issue
- `DELETE /repos/:user/:repo/issues/:number/lock` - Unlock issue

### Pinning
- `GET /repos/:user/:repo/issues/pinned` - List pinned issues
- `POST /repos/:user/:repo/issues/:number/pin` - Pin issue
- `DELETE /repos/:user/:repo/issues/:number/pin` - Unpin issue
- `PATCH /repos/:user/:repo/issues/:number/pin/:position` - Move pin

---

## 12. Example Issue Template

`.github/ISSUE_TEMPLATE/bug-report.yaml`:

```yaml
name: Bug Report
description: Found something broken? Report it here!
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to fill out this bug report!

  - type: textarea
    id: description
    attributes:
      label: Bug Description
      description: A clear description of the bug
      placeholder: When I click X, Y happens instead of Z
    validations:
      required: true

  - type: input
    id: version
    attributes:
      label: Version
      placeholder: v1.2.3
    validations:
      required: true

  - type: dropdown
    id: severity
    attributes:
      label: Severity
      options:
        - Critical
        - High
        - Medium
        - Low
    validations:
      required: true

  - type: checkboxes
    id: checklist
    attributes:
      label: Pre-flight checklist
      options:
        - label: I have searched for similar issues
          required: true
        - label: I have tested on the latest version
          required: true
```

---

## Testing Strategy

1. **Unit Tests**
   - Circular dependency detection
   - Pin order calculations
   - Template parsing and rendering
   - Reaction validation

2. **Integration Tests**
   - Create/delete reactions via API
   - Add/remove dependencies
   - Lock/unlock issues
   - Pin/unpin issues with order management

3. **E2E Tests**
   - Full issue creation flow with templates
   - Reaction workflow (add, remove, display)
   - Dependency workflow (create, validate, delete)
   - Pin management (pin, reorder, unpin)

---

## Notes

- All APIs assume mock authentication (user_id = 1). Replace with real auth when ready.
- Reaction types are GitHub-compatible for easy migration.
- Max pinned issues is configurable (default: 3).
- Issue templates support both YAML (preferred) and Markdown (legacy).
- Dependencies support same-repo only by default; cross-repo is optional.
- Locking requires write access to the repository.
- Consider rate limiting for reactions to prevent spam.

This implementation provides a solid foundation for advanced issue management while maintaining compatibility with GitHub's conventions where applicable.
