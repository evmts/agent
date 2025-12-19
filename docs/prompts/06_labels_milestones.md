# Labels & Milestones Feature Implementation

## Overview

Implement a complete labels and milestones system for Plue, enabling issue categorization, progress tracking, and project management. This feature adds colored labels for tagging issues and milestones for tracking progress toward specific goals or releases.

**Scope**: Full CRUD operations for labels and milestones, assignment/unassignment to issues, milestone progress tracking, filtering, and sorting.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database.

---

## 1. Database Schema Changes

### 1.1 Labels Table

Labels provide a way to categorize and filter issues using colored tags.

```sql
-- Labels for categorizing issues
CREATE TABLE IF NOT EXISTS labels (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  -- Label properties
  name VARCHAR(255) NOT NULL,
  color VARCHAR(7) NOT NULL, -- Hex color code (e.g., #FF5733)
  description TEXT,

  -- Exclusive scopes (e.g., "priority/high", "priority/low")
  -- Labels with the same scope are mutually exclusive
  exclusive BOOLEAN DEFAULT false,
  exclusive_order INTEGER DEFAULT 0, -- Sort order within exclusive group

  -- Statistics
  num_issues INTEGER DEFAULT 0,
  num_closed_issues INTEGER DEFAULT 0,

  -- Archive status
  archived_at TIMESTAMP, -- NULL means active

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(repository_id, name)
);

CREATE INDEX idx_labels_repo ON labels(repository_id);
CREATE INDEX idx_labels_archived ON labels(archived_at);
```

**Key Features:**
- **Color coding**: 7-character hex colors for visual categorization
- **Exclusive scopes**: Labels like `priority/high`, `priority/low`, `priority/medium` where only one can be applied per issue
- **Archiving**: Soft-delete labels without losing history
- **Statistics**: Track how many issues use each label

### 1.2 Issue-Label Junction Table

Many-to-many relationship between issues and labels.

```sql
-- Junction table for issue-label assignments
CREATE TABLE IF NOT EXISTS issue_labels (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  label_id INTEGER NOT NULL REFERENCES labels(id) ON DELETE CASCADE,

  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(issue_id, label_id)
);

CREATE INDEX idx_issue_labels_issue ON issue_labels(issue_id);
CREATE INDEX idx_issue_labels_label ON issue_labels(label_id);
```

### 1.3 Milestones Table

Milestones track progress toward specific goals or releases.

```sql
-- Milestones for tracking progress
CREATE TABLE IF NOT EXISTS milestones (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  -- Milestone properties
  name VARCHAR(255) NOT NULL,
  description TEXT,

  -- State
  state VARCHAR(20) DEFAULT 'open' CHECK (state IN ('open', 'closed')),

  -- Due date
  due_date TIMESTAMP,

  -- Statistics (cached for performance)
  num_issues INTEGER DEFAULT 0,
  num_closed_issues INTEGER DEFAULT 0,
  completeness INTEGER DEFAULT 0, -- Percentage (0-100)

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  closed_at TIMESTAMP,

  UNIQUE(repository_id, name)
);

CREATE INDEX idx_milestones_repo ON milestones(repository_id);
CREATE INDEX idx_milestones_state ON milestones(state);
CREATE INDEX idx_milestones_due_date ON milestones(due_date);
```

**Key Features:**
- **Due dates**: Optional deadlines for milestone completion
- **Progress tracking**: Automatic calculation of completeness percentage
- **Open/closed states**: Track milestone lifecycle

### 1.4 Update Issues Table

Add milestone reference to issues table.

```sql
-- Add milestone_id column to issues table
ALTER TABLE issues
  ADD COLUMN milestone_id INTEGER REFERENCES milestones(id) ON DELETE SET NULL;

CREATE INDEX idx_issues_milestone ON issues(milestone_id);
```

---

## 2. Backend Implementation

### 2.1 Label Model & Utilities

**File**: `/Users/williamcory/plue/server/lib/labels.ts`

```typescript
import { z } from 'zod';
import { sql } from '../../ui/lib/db';

export interface Label {
  id: number;
  repositoryId: number;
  name: string;
  color: string;
  description: string | null;
  exclusive: boolean;
  exclusiveOrder: number;
  numIssues: number;
  numClosedIssues: number;
  archivedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Normalize color to 7-character hex format (#RRGGBB)
 */
export function normalizeColor(color: string): string {
  // Remove any whitespace
  color = color.trim();

  // Add # if missing
  if (!color.startsWith('#')) {
    color = '#' + color;
  }

  // Convert 3-digit hex to 6-digit (#RGB -> #RRGGBB)
  if (color.length === 4) {
    color = '#' + color[1] + color[1] + color[2] + color[2] + color[3] + color[3];
  }

  // Validate hex format
  if (!/^#[0-9A-Fa-f]{6}$/.test(color)) {
    throw new Error('Invalid color format. Use hex format like #FF5733');
  }

  return color.toUpperCase();
}

/**
 * Extract exclusive scope from label name
 * e.g., "priority/high" -> "priority"
 */
export function getExclusiveScope(label: Label): string | null {
  if (!label.exclusive) return null;

  const lastSlash = label.name.lastIndexOf('/');
  if (lastSlash === -1 || lastSlash === 0 || lastSlash === label.name.length - 1) {
    return null;
  }

  return label.name.substring(0, lastSlash);
}

/**
 * Check if a label name uses exclusive scope syntax
 */
export function hasExclusiveScopeSyntax(name: string): boolean {
  return name.includes('/') && !name.startsWith('/') && !name.endsWith('/');
}

/**
 * Update label statistics after issue label changes
 */
export async function updateLabelStats(labelId: number): Promise<void> {
  await sql`
    UPDATE labels
    SET
      num_issues = (
        SELECT COUNT(*)
        FROM issue_labels
        WHERE label_id = ${labelId}
      ),
      num_closed_issues = (
        SELECT COUNT(*)
        FROM issue_labels il
        INNER JOIN issues i ON il.issue_id = i.id
        WHERE il.label_id = ${labelId} AND i.state = 'closed'
      ),
      updated_at = NOW()
    WHERE id = ${labelId}
  `;
}

// Validation schemas
export const labelCreateSchema = z.object({
  name: z.string()
    .min(1, 'Label name is required')
    .max(255, 'Label name too long'),
  color: z.string()
    .regex(/^#?[0-9A-Fa-f]{3,6}$/, 'Invalid color format'),
  description: z.string().max(2000).optional(),
  exclusive: z.boolean().optional(),
  exclusiveOrder: z.number().int().min(0).optional(),
});

export const labelUpdateSchema = labelCreateSchema.partial().extend({
  isArchived: z.boolean().optional(),
});
```

### 2.2 Label Routes

**File**: `/Users/williamcory/plue/server/routes/labels.ts`

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { sql } from '../../ui/lib/db';
import { requireAuth } from '../middleware/auth';
import {
  labelCreateSchema,
  labelUpdateSchema,
  normalizeColor,
  updateLabelStats,
  getExclusiveScope,
} from '../lib/labels';

const app = new Hono();

/**
 * GET /:user/:repo/labels
 * List all labels for a repository
 */
app.get('/:user/:repo/labels', async (c) => {
  const { user: username, repo: repoName } = c.req.param();
  const sortType = c.req.query('sort') || 'alphabetically';

  // Get repository
  const [repo] = await sql<Array<{ id: number }>>`
    SELECT r.id
    FROM repositories r
    INNER JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  `;

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Build sort clause
  let orderClause = 'name ASC';
  switch (sortType) {
    case 'reversealphabetically':
      orderClause = 'name DESC';
      break;
    case 'leastissues':
      orderClause = 'num_issues ASC, name ASC';
      break;
    case 'mostissues':
      orderClause = 'num_issues DESC, name ASC';
      break;
  }

  const labels = await sql<Array<{
    id: number;
    repository_id: number;
    name: string;
    color: string;
    description: string | null;
    exclusive: boolean;
    exclusive_order: number;
    num_issues: number;
    num_closed_issues: number;
    archived_at: Date | null;
    created_at: Date;
    updated_at: Date;
  }>>`
    SELECT *
    FROM labels
    WHERE repository_id = ${repo.id}
      AND archived_at IS NULL
    ORDER BY ${sql.unsafe(orderClause)}
  `;

  // Calculate open issues for each label
  const labelsWithStats = labels.map(label => ({
    ...label,
    numOpenIssues: label.num_issues - label.num_closed_issues,
  }));

  return c.json({ labels: labelsWithStats });
});

/**
 * POST /:user/:repo/labels
 * Create a new label (requires auth)
 */
app.post(
  '/:user/:repo/labels',
  requireAuth,
  zValidator('json', labelCreateSchema),
  async (c) => {
    const { user: username, repo: repoName } = c.req.param();
    const currentUser = c.get('user')!;
    const data = c.req.valid('json');

    // Get repository and check ownership
    const [repo] = await sql<Array<{ id: number; user_id: number }>>`
      SELECT r.id, r.user_id
      FROM repositories r
      INNER JOIN users u ON r.user_id = u.id
      WHERE u.username = ${username} AND r.name = ${repoName}
    `;

    if (!repo) {
      return c.json({ error: 'Repository not found' }, 404);
    }

    if (repo.user_id !== currentUser.id) {
      return c.json({ error: 'Permission denied' }, 403);
    }

    // Normalize color
    let color: string;
    try {
      color = normalizeColor(data.color);
    } catch (error) {
      return c.json({
        error: error instanceof Error ? error.message : 'Invalid color'
      }, 400);
    }

    // Check for duplicate name
    const [existing] = await sql<Array<{ id: number }>>`
      SELECT id FROM labels
      WHERE repository_id = ${repo.id} AND name = ${data.name}
    `;

    if (existing) {
      return c.json({ error: 'Label name already exists' }, 409);
    }

    // Create label
    const [label] = await sql<Array<{ id: number }>>`
      INSERT INTO labels (
        repository_id, name, color, description,
        exclusive, exclusive_order,
        created_at, updated_at
      ) VALUES (
        ${repo.id},
        ${data.name},
        ${color},
        ${data.description || null},
        ${data.exclusive || false},
        ${data.exclusiveOrder || 0},
        NOW(),
        NOW()
      )
      RETURNING id
    `;

    return c.json({
      message: 'Label created successfully',
      labelId: label.id
    }, 201);
  }
);

/**
 * PATCH /:user/:repo/labels/:id
 * Update a label (requires auth)
 */
app.patch(
  '/:user/:repo/labels/:id',
  requireAuth,
  zValidator('json', labelUpdateSchema),
  async (c) => {
    const { user: username, repo: repoName, id } = c.req.param();
    const currentUser = c.get('user')!;
    const data = c.req.valid('json');

    // Get repository and label
    const [label] = await sql<Array<{
      id: number;
      repository_id: number;
      user_id: number;
    }>>`
      SELECT l.id, l.repository_id, r.user_id
      FROM labels l
      INNER JOIN repositories r ON l.repository_id = r.id
      INNER JOIN users u ON r.user_id = u.id
      WHERE l.id = ${id}
        AND u.username = ${username}
        AND r.name = ${repoName}
    `;

    if (!label) {
      return c.json({ error: 'Label not found' }, 404);
    }

    if (label.user_id !== currentUser.id) {
      return c.json({ error: 'Permission denied' }, 403);
    }

    // Build update fields
    const updates: string[] = [];
    const values: any[] = [];
    let paramCount = 0;

    if (data.name !== undefined) {
      // Check for duplicate name
      const [existing] = await sql<Array<{ id: number }>>`
        SELECT id FROM labels
        WHERE repository_id = ${label.repository_id}
          AND name = ${data.name}
          AND id != ${id}
      `;

      if (existing) {
        return c.json({ error: 'Label name already exists' }, 409);
      }

      updates.push(`name = $${++paramCount}`);
      values.push(data.name);
    }

    if (data.color !== undefined) {
      try {
        const color = normalizeColor(data.color);
        updates.push(`color = $${++paramCount}`);
        values.push(color);
      } catch (error) {
        return c.json({
          error: error instanceof Error ? error.message : 'Invalid color'
        }, 400);
      }
    }

    if (data.description !== undefined) {
      updates.push(`description = $${++paramCount}`);
      values.push(data.description || null);
    }

    if (data.exclusive !== undefined) {
      updates.push(`exclusive = $${++paramCount}`);
      values.push(data.exclusive);
    }

    if (data.exclusiveOrder !== undefined) {
      updates.push(`exclusive_order = $${++paramCount}`);
      values.push(data.exclusiveOrder);
    }

    if (data.isArchived !== undefined) {
      updates.push(`archived_at = $${++paramCount}`);
      values.push(data.isArchived ? new Date() : null);
    }

    if (updates.length === 0) {
      return c.json({ error: 'No updates provided' }, 400);
    }

    updates.push('updated_at = NOW()');
    values.push(id);

    await sql.unsafe(
      `UPDATE labels SET ${updates.join(', ')} WHERE id = $${++paramCount}`,
      values
    );

    return c.json({ message: 'Label updated successfully' });
  }
);

/**
 * DELETE /:user/:repo/labels/:id
 * Delete a label (requires auth)
 */
app.delete('/:user/:repo/labels/:id', requireAuth, async (c) => {
  const { user: username, repo: repoName, id } = c.req.param();
  const currentUser = c.get('user')!;

  // Get repository and label
  const [label] = await sql<Array<{
    id: number;
    user_id: number;
  }>>`
    SELECT l.id, r.user_id
    FROM labels l
    INNER JOIN repositories r ON l.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE l.id = ${id}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!label) {
    return c.json({ error: 'Label not found' }, 404);
  }

  if (label.user_id !== currentUser.id) {
    return c.json({ error: 'Permission denied' }, 403);
  }

  // Delete label (cascade will handle issue_labels)
  await sql`DELETE FROM labels WHERE id = ${id}`;

  return c.json({ message: 'Label deleted successfully' });
});

/**
 * POST /:user/:repo/issues/:number/labels
 * Add labels to an issue (requires auth)
 */
app.post('/:user/:repo/issues/:number/labels', requireAuth, async (c) => {
  const { user: username, repo: repoName, number } = c.req.param();
  const currentUser = c.get('user')!;
  const { labelIds } = await c.req.json<{ labelIds: number[] }>();

  if (!Array.isArray(labelIds) || labelIds.length === 0) {
    return c.json({ error: 'labelIds array is required' }, 400);
  }

  // Get issue and repository
  const [issue] = await sql<Array<{
    id: number;
    repository_id: number;
    user_id: number;
  }>>`
    SELECT i.id, i.repository_id, r.user_id
    FROM issues i
    INNER JOIN repositories r ON i.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE i.issue_number = ${number}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // TODO: Check if user has permission (owner or collaborator)
  // For now, only allow repository owner
  if (issue.user_id !== currentUser.id) {
    return c.json({ error: 'Permission denied' }, 403);
  }

  // Get labels to add and check they belong to the repository
  const labels = await sql<Array<{
    id: number;
    exclusive: boolean;
    name: string;
  }>>`
    SELECT id, exclusive, name
    FROM labels
    WHERE id = ANY(${labelIds})
      AND repository_id = ${issue.repository_id}
      AND archived_at IS NULL
  `;

  if (labels.length !== labelIds.length) {
    return c.json({ error: 'One or more labels not found or archived' }, 400);
  }

  // Handle exclusive scopes - remove conflicting labels
  const exclusiveScopes = new Set<string>();
  for (const label of labels) {
    if (label.exclusive) {
      const scope = label.name.split('/')[0];
      if (scope) {
        exclusiveScopes.add(scope);
      }
    }
  }

  if (exclusiveScopes.size > 0) {
    // Remove existing labels with same exclusive scopes
    await sql`
      DELETE FROM issue_labels
      WHERE issue_id = ${issue.id}
        AND label_id IN (
          SELECT id FROM labels
          WHERE exclusive = true
            AND ${sql.unsafe(`name SIMILAR TO '(${Array.from(exclusiveScopes).join('|')})/%'`)}
        )
    `;
  }

  // Add labels (ignore duplicates)
  for (const labelId of labelIds) {
    await sql`
      INSERT INTO issue_labels (issue_id, label_id, created_at)
      VALUES (${issue.id}, ${labelId}, NOW())
      ON CONFLICT (issue_id, label_id) DO NOTHING
    `;
  }

  // Update label statistics
  for (const labelId of labelIds) {
    await updateLabelStats(labelId);
  }

  return c.json({ message: 'Labels added successfully' });
});

/**
 * DELETE /:user/:repo/issues/:number/labels/:labelId
 * Remove a label from an issue (requires auth)
 */
app.delete('/:user/:repo/issues/:number/labels/:labelId', requireAuth, async (c) => {
  const { user: username, repo: repoName, number, labelId } = c.req.param();
  const currentUser = c.get('user')!;

  // Get issue
  const [issue] = await sql<Array<{
    id: number;
    user_id: number;
  }>>`
    SELECT i.id, r.user_id
    FROM issues i
    INNER JOIN repositories r ON i.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE i.issue_number = ${number}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  if (issue.user_id !== currentUser.id) {
    return c.json({ error: 'Permission denied' }, 403);
  }

  // Remove label
  await sql`
    DELETE FROM issue_labels
    WHERE issue_id = ${issue.id} AND label_id = ${labelId}
  `;

  // Update label statistics
  await updateLabelStats(Number(labelId));

  return c.json({ message: 'Label removed successfully' });
});

export default app;
```

### 2.3 Milestone Model & Utilities

**File**: `/Users/williamcory/plue/server/lib/milestones.ts`

```typescript
import { z } from 'zod';
import { sql } from '../../ui/lib/db';

export interface Milestone {
  id: number;
  repositoryId: number;
  name: string;
  description: string | null;
  state: 'open' | 'closed';
  dueDate: Date | null;
  numIssues: number;
  numClosedIssues: number;
  completeness: number;
  createdAt: Date;
  updatedAt: Date;
  closedAt: Date | null;
}

export interface MilestoneWithStats extends Milestone {
  numOpenIssues: number;
  isOverdue: boolean;
}

/**
 * Update milestone statistics and completeness
 */
export async function updateMilestoneStats(milestoneId: number): Promise<void> {
  await sql`
    UPDATE milestones
    SET
      num_issues = (
        SELECT COUNT(*)
        FROM issues
        WHERE milestone_id = ${milestoneId}
      ),
      num_closed_issues = (
        SELECT COUNT(*)
        FROM issues
        WHERE milestone_id = ${milestoneId} AND state = 'closed'
      ),
      completeness = CASE
        WHEN (SELECT COUNT(*) FROM issues WHERE milestone_id = ${milestoneId}) > 0
        THEN (
          SELECT (COUNT(*) FILTER (WHERE state = 'closed') * 100) / COUNT(*)
          FROM issues
          WHERE milestone_id = ${milestoneId}
        )
        ELSE 0
      END,
      updated_at = NOW()
    WHERE id = ${milestoneId}
  `;
}

/**
 * Check if milestone is overdue
 */
export function isOverdue(milestone: Milestone): boolean {
  if (!milestone.dueDate) return false;
  if (milestone.state === 'closed') {
    return milestone.closedAt ? milestone.closedAt > milestone.dueDate : false;
  }
  return new Date() > milestone.dueDate;
}

/**
 * Add computed fields to milestone
 */
export function enrichMilestone(milestone: Milestone): MilestoneWithStats {
  return {
    ...milestone,
    numOpenIssues: milestone.numIssues - milestone.numClosedIssues,
    isOverdue: isOverdue(milestone),
  };
}

// Validation schemas
export const milestoneCreateSchema = z.object({
  name: z.string()
    .min(1, 'Milestone name is required')
    .max(255, 'Milestone name too long'),
  description: z.string().max(10000).optional(),
  dueDate: z.string().datetime().optional(),
});

export const milestoneUpdateSchema = milestoneCreateSchema.partial().extend({
  state: z.enum(['open', 'closed']).optional(),
});
```

### 2.4 Milestone Routes

**File**: `/Users/williamcory/plue/server/routes/milestones.ts`

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { sql } from '../../ui/lib/db';
import { requireAuth } from '../middleware/auth';
import {
  milestoneCreateSchema,
  milestoneUpdateSchema,
  updateMilestoneStats,
  enrichMilestone,
  type Milestone,
} from '../lib/milestones';

const app = new Hono();

/**
 * GET /:user/:repo/milestones
 * List all milestones for a repository
 */
app.get('/:user/:repo/milestones', async (c) => {
  const { user: username, repo: repoName } = c.req.param();
  const state = c.req.query('state') || 'open';
  const sortType = c.req.query('sort') || 'duedate';

  // Get repository
  const [repo] = await sql<Array<{ id: number }>>`
    SELECT r.id
    FROM repositories r
    INNER JOIN users u ON r.user_id = u.id
    WHERE u.username = ${username} AND r.name = ${repoName}
  `;

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // Build sort clause
  let orderClause = 'due_date ASC, name ASC';
  switch (sortType) {
    case 'furthestduedate':
      orderClause = 'due_date DESC, name ASC';
      break;
    case 'leastcomplete':
      orderClause = 'completeness ASC, name ASC';
      break;
    case 'mostcomplete':
      orderClause = 'completeness DESC, name ASC';
      break;
    case 'leastissues':
      orderClause = 'num_issues ASC, name ASC';
      break;
    case 'mostissues':
      orderClause = 'num_issues DESC, name ASC';
      break;
    case 'name':
      orderClause = 'name ASC';
      break;
  }

  const milestones = await sql<Array<Milestone>>`
    SELECT *
    FROM milestones
    WHERE repository_id = ${repo.id}
      ${state !== 'all' ? sql`AND state = ${state}` : sql``}
    ORDER BY ${sql.unsafe(orderClause)}
  `;

  const enriched = milestones.map(enrichMilestone);

  // Get stats
  const [stats] = await sql<Array<{
    open_count: number;
    closed_count: number;
  }>>`
    SELECT
      COUNT(*) FILTER (WHERE state = 'open') as open_count,
      COUNT(*) FILTER (WHERE state = 'closed') as closed_count
    FROM milestones
    WHERE repository_id = ${repo.id}
  `;

  return c.json({
    milestones: enriched,
    stats: {
      openCount: stats?.open_count || 0,
      closedCount: stats?.closed_count || 0,
    },
  });
});

/**
 * GET /:user/:repo/milestones/:id
 * Get a single milestone with its issues
 */
app.get('/:user/:repo/milestones/:id', async (c) => {
  const { user: username, repo: repoName, id } = c.req.param();

  // Get milestone
  const [milestone] = await sql<Array<Milestone>>`
    SELECT m.*
    FROM milestones m
    INNER JOIN repositories r ON m.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE m.id = ${id}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!milestone) {
    return c.json({ error: 'Milestone not found' }, 404);
  }

  return c.json({ milestone: enrichMilestone(milestone) });
});

/**
 * POST /:user/:repo/milestones
 * Create a new milestone (requires auth)
 */
app.post(
  '/:user/:repo/milestones',
  requireAuth,
  zValidator('json', milestoneCreateSchema),
  async (c) => {
    const { user: username, repo: repoName } = c.req.param();
    const currentUser = c.get('user')!;
    const data = c.req.valid('json');

    // Get repository and check ownership
    const [repo] = await sql<Array<{ id: number; user_id: number }>>`
      SELECT r.id, r.user_id
      FROM repositories r
      INNER JOIN users u ON r.user_id = u.id
      WHERE u.username = ${username} AND r.name = ${repoName}
    `;

    if (!repo) {
      return c.json({ error: 'Repository not found' }, 404);
    }

    if (repo.user_id !== currentUser.id) {
      return c.json({ error: 'Permission denied' }, 403);
    }

    // Check for duplicate name
    const [existing] = await sql<Array<{ id: number }>>`
      SELECT id FROM milestones
      WHERE repository_id = ${repo.id} AND name = ${data.name}
    `;

    if (existing) {
      return c.json({ error: 'Milestone name already exists' }, 409);
    }

    // Create milestone
    const [milestone] = await sql<Array<{ id: number }>>`
      INSERT INTO milestones (
        repository_id, name, description, due_date,
        state, created_at, updated_at
      ) VALUES (
        ${repo.id},
        ${data.name},
        ${data.description || null},
        ${data.dueDate || null},
        'open',
        NOW(),
        NOW()
      )
      RETURNING id
    `;

    return c.json({
      message: 'Milestone created successfully',
      milestoneId: milestone.id
    }, 201);
  }
);

/**
 * PATCH /:user/:repo/milestones/:id
 * Update a milestone (requires auth)
 */
app.patch(
  '/:user/:repo/milestones/:id',
  requireAuth,
  zValidator('json', milestoneUpdateSchema),
  async (c) => {
    const { user: username, repo: repoName, id } = c.req.param();
    const currentUser = c.get('user')!;
    const data = c.req.valid('json');

    // Get milestone
    const [milestone] = await sql<Array<{
      id: number;
      repository_id: number;
      user_id: number;
      state: string;
    }>>`
      SELECT m.id, m.repository_id, r.user_id, m.state
      FROM milestones m
      INNER JOIN repositories r ON m.repository_id = r.id
      INNER JOIN users u ON r.user_id = u.id
      WHERE m.id = ${id}
        AND u.username = ${username}
        AND r.name = ${repoName}
    `;

    if (!milestone) {
      return c.json({ error: 'Milestone not found' }, 404);
    }

    if (milestone.user_id !== currentUser.id) {
      return c.json({ error: 'Permission denied' }, 403);
    }

    // Build update fields
    const updates: string[] = [];
    const values: any[] = [];
    let paramCount = 0;

    if (data.name !== undefined) {
      // Check for duplicate name
      const [existing] = await sql<Array<{ id: number }>>`
        SELECT id FROM milestones
        WHERE repository_id = ${milestone.repository_id}
          AND name = ${data.name}
          AND id != ${id}
      `;

      if (existing) {
        return c.json({ error: 'Milestone name already exists' }, 409);
      }

      updates.push(`name = $${++paramCount}`);
      values.push(data.name);
    }

    if (data.description !== undefined) {
      updates.push(`description = $${++paramCount}`);
      values.push(data.description || null);
    }

    if (data.dueDate !== undefined) {
      updates.push(`due_date = $${++paramCount}`);
      values.push(data.dueDate || null);
    }

    if (data.state !== undefined) {
      updates.push(`state = $${++paramCount}`);
      values.push(data.state);

      // Set closed_at if closing
      if (data.state === 'closed' && milestone.state === 'open') {
        updates.push('closed_at = NOW()');
      } else if (data.state === 'open' && milestone.state === 'closed') {
        updates.push('closed_at = NULL');
      }
    }

    if (updates.length === 0) {
      return c.json({ error: 'No updates provided' }, 400);
    }

    updates.push('updated_at = NOW()');
    values.push(id);

    await sql.unsafe(
      `UPDATE milestones SET ${updates.join(', ')} WHERE id = $${++paramCount}`,
      values
    );

    return c.json({ message: 'Milestone updated successfully' });
  }
);

/**
 * DELETE /:user/:repo/milestones/:id
 * Delete a milestone (requires auth)
 */
app.delete('/:user/:repo/milestones/:id', requireAuth, async (c) => {
  const { user: username, repo: repoName, id } = c.req.param();
  const currentUser = c.get('user')!;

  // Get milestone
  const [milestone] = await sql<Array<{
    id: number;
    user_id: number;
  }>>`
    SELECT m.id, r.user_id
    FROM milestones m
    INNER JOIN repositories r ON m.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE m.id = ${id}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!milestone) {
    return c.json({ error: 'Milestone not found' }, 404);
  }

  if (milestone.user_id !== currentUser.id) {
    return c.json({ error: 'Permission denied' }, 403);
  }

  // Unassign issues from this milestone
  await sql`
    UPDATE issues
    SET milestone_id = NULL, updated_at = NOW()
    WHERE milestone_id = ${id}
  `;

  // Delete milestone
  await sql`DELETE FROM milestones WHERE id = ${id}`;

  return c.json({ message: 'Milestone deleted successfully' });
});

/**
 * PUT /:user/:repo/issues/:number/milestone
 * Assign/unassign milestone to an issue (requires auth)
 */
app.put('/:user/:repo/issues/:number/milestone', requireAuth, async (c) => {
  const { user: username, repo: repoName, number } = c.req.param();
  const currentUser = c.get('user')!;
  const { milestoneId } = await c.req.json<{ milestoneId: number | null }>();

  // Get issue
  const [issue] = await sql<Array<{
    id: number;
    repository_id: number;
    user_id: number;
    milestone_id: number | null;
  }>>`
    SELECT i.id, i.repository_id, r.user_id, i.milestone_id
    FROM issues i
    INNER JOIN repositories r ON i.repository_id = r.id
    INNER JOIN users u ON r.user_id = u.id
    WHERE i.issue_number = ${number}
      AND u.username = ${username}
      AND r.name = ${repoName}
  `;

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  if (issue.user_id !== currentUser.id) {
    return c.json({ error: 'Permission denied' }, 403);
  }

  // If assigning a milestone, verify it belongs to the repository
  if (milestoneId !== null) {
    const [milestone] = await sql<Array<{ id: number }>>`
      SELECT id FROM milestones
      WHERE id = ${milestoneId} AND repository_id = ${issue.repository_id}
    `;

    if (!milestone) {
      return c.json({ error: 'Milestone not found' }, 404);
    }
  }

  // Update issue
  await sql`
    UPDATE issues
    SET milestone_id = ${milestoneId}, updated_at = NOW()
    WHERE id = ${issue.id}
  `;

  // Update old milestone stats if it existed
  if (issue.milestone_id !== null) {
    await updateMilestoneStats(issue.milestone_id);
  }

  // Update new milestone stats if assigned
  if (milestoneId !== null) {
    await updateMilestoneStats(milestoneId);
  }

  return c.json({
    message: milestoneId
      ? 'Milestone assigned successfully'
      : 'Milestone removed successfully'
  });
});

export default app;
```

### 2.5 Update Server Index

**File**: `/Users/williamcory/plue/server/index.ts`

Add routes:

```typescript
import labelRoutes from './routes/labels';
import milestoneRoutes from './routes/milestones';

// Mount routes
app.route('/', labelRoutes);
app.route('/', milestoneRoutes);
```

---

## 3. Frontend Implementation

### 3.1 Label Management Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/labels.astro`

```astro
---
import Layout from "../../../layouts/Layout.astro";
import { sql } from "../../../lib/db";

const { user: username, repo: repoName } = Astro.params;
const sortType = Astro.url.searchParams.get('sort') || 'alphabetically';

// Get repository
const [repo] = await sql<Array<{ id: number }>>`
  SELECT r.id
  FROM repositories r
  INNER JOIN users u ON r.user_id = u.id
  WHERE u.username = ${username} AND r.name = ${repoName}
`;

if (!repo) {
  return Astro.redirect('/404');
}

// Build sort clause
let orderClause = 'name ASC';
switch (sortType) {
  case 'reversealphabetically':
    orderClause = 'name DESC';
    break;
  case 'leastissues':
    orderClause = 'num_issues ASC, name ASC';
    break;
  case 'mostissues':
    orderClause = 'num_issues DESC, name ASC';
    break;
}

const labels = await sql<Array<{
  id: number;
  name: string;
  color: string;
  description: string | null;
  num_issues: number;
  num_closed_issues: number;
}>>`
  SELECT id, name, color, description, num_issues, num_closed_issues
  FROM labels
  WHERE repository_id = ${repo.id} AND archived_at IS NULL
  ORDER BY ${sql.unsafe(orderClause)}
`;
---

<Layout title={`Labels - ${repoName}`}>
  <div class="container">
    <div class="page-header">
      <h1>Labels</h1>
      <a href={`/${username}/${repoName}`} class="btn">Back to Repository</a>
    </div>

    <div class="toolbar">
      <div class="sort-menu">
        <label>Sort:</label>
        <select id="sort-select">
          <option value="alphabetically" selected={sortType === 'alphabetically'}>
            Alphabetically
          </option>
          <option value="reversealphabetically" selected={sortType === 'reversealphabetically'}>
            Reverse Alphabetically
          </option>
          <option value="mostissues" selected={sortType === 'mostissues'}>
            Most Issues
          </option>
          <option value="leastissues" selected={sortType === 'leastissues'}>
            Least Issues
          </option>
        </select>
      </div>

      <button id="new-label-btn" class="btn btn-primary">New Label</button>
    </div>

    <div class="labels-list">
      {labels.length === 0 ? (
        <p class="empty-state">No labels yet. Create one to get started!</p>
      ) : (
        labels.map((label) => (
          <div class="label-item" data-label-id={label.id}>
            <div class="label-badge" style={`background-color: ${label.color}`}>
              <span class="label-name">{label.name}</span>
            </div>

            <div class="label-description">
              {label.description || <em>No description</em>}
            </div>

            <div class="label-stats">
              {label.num_issues - label.num_closed_issues} open · {label.num_closed_issues} closed
            </div>

            <div class="label-actions">
              <button class="btn-link edit-label-btn" data-label-id={label.id}>
                Edit
              </button>
              <button class="btn-link delete-label-btn" data-label-id={label.id}>
                Delete
              </button>
            </div>
          </div>
        ))
      )}
    </div>

    {/* New/Edit Label Modal */}
    <div id="label-modal" class="modal" style="display: none;">
      <div class="modal-content">
        <h2 id="modal-title">New Label</h2>

        <form id="label-form">
          <input type="hidden" id="label-id" />

          <div class="form-group">
            <label for="label-name">Label Name</label>
            <input
              type="text"
              id="label-name"
              name="name"
              required
              placeholder="bug, enhancement, priority/high"
            />
          </div>

          <div class="form-group">
            <label for="label-description">Description</label>
            <textarea
              id="label-description"
              name="description"
              rows="3"
              placeholder="Describe what this label is for..."
            ></textarea>
          </div>

          <div class="form-group">
            <label for="label-color">Color</label>
            <div class="color-input-group">
              <input
                type="color"
                id="label-color-picker"
                value="#0075ca"
              />
              <input
                type="text"
                id="label-color"
                name="color"
                pattern="#?[0-9A-Fa-f]{6}"
                placeholder="#0075CA"
                value="#0075CA"
              />
            </div>
          </div>

          <div class="label-preview">
            <span class="label-badge" id="label-preview-badge" style="background-color: #0075CA">
              Preview
            </span>
          </div>

          <div id="modal-error" class="error-message" style="display: none;"></div>

          <div class="modal-actions">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" id="cancel-modal-btn" class="btn">Cancel</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</Layout>

<style>
  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
  }

  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1.5rem;
    padding: 1rem;
    border: 2px solid #000;
  }

  .sort-menu {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .sort-menu select {
    padding: 0.5rem;
    border: 2px solid #000;
    font-family: monospace;
  }

  .labels-list {
    border: 2px solid #000;
  }

  .label-item {
    display: grid;
    grid-template-columns: auto 1fr auto auto;
    gap: 1rem;
    align-items: center;
    padding: 1rem;
    border-bottom: 2px solid #000;
  }

  .label-item:last-child {
    border-bottom: none;
  }

  .label-badge {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border: 2px solid #000;
    border-radius: 2em;
    font-weight: bold;
    color: #fff;
    text-shadow: 0 0 2px rgba(0,0,0,0.5);
  }

  .label-description {
    font-size: 0.9rem;
    color: #666;
  }

  .label-stats {
    font-size: 0.875rem;
    font-family: monospace;
  }

  .label-actions {
    display: flex;
    gap: 1rem;
  }

  .modal {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .modal-content {
    background: #fff;
    border: 4px solid #000;
    padding: 2rem;
    max-width: 500px;
    width: 90%;
  }

  .color-input-group {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }

  #label-color-picker {
    width: 50px;
    height: 40px;
    border: 2px solid #000;
    cursor: pointer;
  }

  #label-color {
    flex: 1;
    padding: 0.5rem;
    border: 2px solid #000;
    font-family: monospace;
    text-transform: uppercase;
  }

  .label-preview {
    margin: 1rem 0;
    padding: 1rem;
    border: 2px solid #000;
    text-align: center;
  }

  .modal-actions {
    display: flex;
    gap: 1rem;
    margin-top: 1.5rem;
  }

  .empty-state {
    padding: 4rem 2rem;
    text-align: center;
    color: #666;
    font-style: italic;
  }
</style>

<script>
  // Sort dropdown
  const sortSelect = document.getElementById('sort-select') as HTMLSelectElement;
  sortSelect?.addEventListener('change', () => {
    const url = new URL(window.location.href);
    url.searchParams.set('sort', sortSelect.value);
    window.location.href = url.toString();
  });

  // Modal management
  const modal = document.getElementById('label-modal');
  const modalTitle = document.getElementById('modal-title');
  const labelForm = document.getElementById('label-form') as HTMLFormElement;
  const labelIdInput = document.getElementById('label-id') as HTMLInputElement;
  const newLabelBtn = document.getElementById('new-label-btn');
  const cancelModalBtn = document.getElementById('cancel-modal-btn');
  const modalError = document.getElementById('modal-error');

  // Color picker sync
  const colorPicker = document.getElementById('label-color-picker') as HTMLInputElement;
  const colorInput = document.getElementById('label-color') as HTMLInputElement;
  const previewBadge = document.getElementById('label-preview-badge');
  const labelNameInput = document.getElementById('label-name') as HTMLInputElement;

  function syncColor() {
    const color = colorPicker.value;
    colorInput.value = color.toUpperCase();
    if (previewBadge) {
      previewBadge.style.backgroundColor = color;
    }
  }

  function syncColorInput() {
    let color = colorInput.value.trim();
    if (!color.startsWith('#')) color = '#' + color;
    colorPicker.value = color;
    if (previewBadge) {
      previewBadge.style.backgroundColor = color;
      previewBadge.textContent = labelNameInput.value || 'Preview';
    }
  }

  colorPicker?.addEventListener('input', syncColor);
  colorInput?.addEventListener('input', syncColorInput);
  labelNameInput?.addEventListener('input', () => {
    if (previewBadge) {
      previewBadge.textContent = labelNameInput.value || 'Preview';
    }
  });

  // New label button
  newLabelBtn?.addEventListener('click', () => {
    if (modalTitle) modalTitle.textContent = 'New Label';
    labelForm?.reset();
    labelIdInput.value = '';
    colorPicker.value = '#0075CA';
    colorInput.value = '#0075CA';
    if (previewBadge) {
      previewBadge.style.backgroundColor = '#0075CA';
      previewBadge.textContent = 'Preview';
    }
    if (modal) modal.style.display = 'flex';
    if (modalError) modalError.style.display = 'none';
  });

  // Cancel button
  cancelModalBtn?.addEventListener('click', () => {
    if (modal) modal.style.display = 'none';
  });

  // Form submission
  labelForm?.addEventListener('submit', async (e) => {
    e.preventDefault();

    const formData = new FormData(labelForm);
    const data = {
      name: formData.get('name'),
      color: formData.get('color'),
      description: formData.get('description') || undefined,
    };

    const labelId = labelIdInput.value;
    const url = labelId
      ? `/api/${window.location.pathname.split('/').slice(1, 3).join('/')}/labels/${labelId}`
      : `/api/${window.location.pathname.split('/').slice(1, 3).join('/')}/labels`;
    const method = labelId ? 'PATCH' : 'POST';

    try {
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
        credentials: 'include',
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to save label');
      }

      window.location.reload();
    } catch (error) {
      if (modalError) {
        modalError.textContent = error instanceof Error ? error.message : 'Failed to save label';
        modalError.style.display = 'block';
      }
    }
  });

  // Edit label buttons
  document.querySelectorAll('.edit-label-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const labelId = (e.target as HTMLElement).dataset.labelId;
      // TODO: Fetch label data and populate form
      // For now, just show the modal
      if (modalTitle) modalTitle.textContent = 'Edit Label';
      labelIdInput.value = labelId || '';
      if (modal) modal.style.display = 'flex';
      if (modalError) modalError.style.display = 'none';
    });
  });

  // Delete label buttons
  document.querySelectorAll('.delete-label-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const labelId = (e.target as HTMLElement).dataset.labelId;

      if (!confirm('Are you sure you want to delete this label? This will remove it from all issues.')) {
        return;
      }

      try {
        const response = await fetch(
          `/api/${window.location.pathname.split('/').slice(1, 3).join('/')}/labels/${labelId}`,
          {
            method: 'DELETE',
            credentials: 'include',
          }
        );

        if (!response.ok) {
          const error = await response.json();
          throw new Error(error.error || 'Failed to delete label');
        }

        window.location.reload();
      } catch (error) {
        alert(error instanceof Error ? error.message : 'Failed to delete label');
      }
    });
  });
</script>
```

### 3.2 Milestone List Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/milestones.astro`

```astro
---
import Layout from "../../../layouts/Layout.astro";
import { sql } from "../../../lib/db";

const { user: username, repo: repoName } = Astro.params;
const state = Astro.url.searchParams.get('state') || 'open';
const sortType = Astro.url.searchParams.get('sort') || 'duedate';

// Get repository
const [repo] = await sql<Array<{ id: number }>>`
  SELECT r.id
  FROM repositories r
  INNER JOIN users u ON r.user_id = u.id
  WHERE u.username = ${username} AND r.name = ${repoName}
`;

if (!repo) {
  return Astro.redirect('/404');
}

// Build sort clause
let orderClause = 'due_date ASC, name ASC';
switch (sortType) {
  case 'furthestduedate':
    orderClause = 'due_date DESC, name ASC';
    break;
  case 'leastcomplete':
    orderClause = 'completeness ASC, name ASC';
    break;
  case 'mostcomplete':
    orderClause = 'completeness DESC, name ASC';
    break;
  case 'leastissues':
    orderClause = 'num_issues ASC, name ASC';
    break;
  case 'mostissues':
    orderClause = 'num_issues DESC, name ASC';
    break;
  case 'name':
    orderClause = 'name ASC';
    break;
}

const milestones = await sql<Array<{
  id: number;
  name: string;
  description: string | null;
  state: string;
  due_date: Date | null;
  num_issues: number;
  num_closed_issues: number;
  completeness: number;
  created_at: Date;
  closed_at: Date | null;
}>>`
  SELECT *
  FROM milestones
  WHERE repository_id = ${repo.id}
    ${state !== 'all' ? sql`AND state = ${state}` : sql``}
  ORDER BY ${sql.unsafe(orderClause)}
`;

const [stats] = await sql<Array<{
  open_count: number;
  closed_count: number;
}>>`
  SELECT
    COUNT(*) FILTER (WHERE state = 'open') as open_count,
    COUNT(*) FILTER (WHERE state = 'closed') as closed_count
  FROM milestones
  WHERE repository_id = ${repo.id}
`;

function isOverdue(milestone: typeof milestones[0]) {
  if (!milestone.due_date) return false;
  if (milestone.state === 'closed') {
    return milestone.closed_at ? milestone.closed_at > milestone.due_date : false;
  }
  return new Date() > milestone.due_date;
}

function formatDate(date: Date | null) {
  if (!date) return null;
  return new Date(date).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  });
}
---

<Layout title={`Milestones - ${repoName}`}>
  <div class="container">
    <div class="page-header">
      <h1>Milestones</h1>
      <a href={`/${username}/${repoName}`} class="btn">Back to Repository</a>
    </div>

    <div class="toolbar">
      <div class="state-tabs">
        <a
          href={`?state=open&sort=${sortType}`}
          class={state === 'open' ? 'tab active' : 'tab'}
        >
          {stats?.open_count || 0} Open
        </a>
        <a
          href={`?state=closed&sort=${sortType}`}
          class={state === 'closed' ? 'tab active' : 'tab'}
        >
          {stats?.closed_count || 0} Closed
        </a>
      </div>

      <div class="toolbar-right">
        <div class="sort-menu">
          <label>Sort:</label>
          <select id="sort-select">
            <option value="duedate" selected={sortType === 'duedate'}>
              Due Date
            </option>
            <option value="furthestduedate" selected={sortType === 'furthestduedate'}>
              Furthest Due Date
            </option>
            <option value="mostcomplete" selected={sortType === 'mostcomplete'}>
              Most Complete
            </option>
            <option value="leastcomplete" selected={sortType === 'leastcomplete'}>
              Least Complete
            </option>
            <option value="mostissues" selected={sortType === 'mostissues'}>
              Most Issues
            </option>
            <option value="leastissues" selected={sortType === 'leastissues'}>
              Least Issues
            </option>
            <option value="name" selected={sortType === 'name'}>
              Name
            </option>
          </select>
        </div>

        <a href={`/${username}/${repoName}/milestones/new`} class="btn btn-primary">
          New Milestone
        </a>
      </div>
    </div>

    <div class="milestones-list">
      {milestones.length === 0 ? (
        <p class="empty-state">
          {state === 'open'
            ? 'No open milestones. Create one to track progress!'
            : 'No closed milestones yet.'}
        </p>
      ) : (
        milestones.map((milestone) => {
          const numOpenIssues = milestone.num_issues - milestone.num_closed_issues;
          const overdue = isOverdue(milestone);

          return (
            <div class="milestone-item">
              <div class="milestone-header">
                <h3>
                  <a href={`/${username}/${repoName}/milestones/${milestone.id}`}>
                    {milestone.name}
                  </a>
                </h3>

                {milestone.due_date && (
                  <div class={`due-date ${overdue ? 'overdue' : ''}`}>
                    {overdue ? 'Past due by ' : 'Due '}
                    {formatDate(milestone.due_date)}
                  </div>
                )}
              </div>

              {milestone.description && (
                <p class="milestone-description">{milestone.description}</p>
              )}

              <div class="milestone-progress">
                <div class="progress-bar">
                  <div
                    class="progress-fill"
                    style={`width: ${milestone.completeness}%`}
                  ></div>
                </div>
                <div class="progress-text">
                  {milestone.completeness}% complete
                </div>
              </div>

              <div class="milestone-stats">
                <span>{numOpenIssues} open</span>
                <span>{milestone.num_closed_issues} closed</span>
              </div>

              <div class="milestone-actions">
                <a
                  href={`/${username}/${repoName}/milestones/${milestone.id}/edit`}
                  class="btn-link"
                >
                  Edit
                </a>
                {milestone.state === 'open' ? (
                  <button
                    class="btn-link close-milestone-btn"
                    data-milestone-id={milestone.id}
                  >
                    Close
                  </button>
                ) : (
                  <button
                    class="btn-link reopen-milestone-btn"
                    data-milestone-id={milestone.id}
                  >
                    Reopen
                  </button>
                )}
                <button
                  class="btn-link delete-milestone-btn"
                  data-milestone-id={milestone.id}
                >
                  Delete
                </button>
              </div>
            </div>
          );
        })
      )}
    </div>
  </div>
</Layout>

<style>
  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
  }

  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1.5rem;
    padding: 1rem;
    border: 2px solid #000;
  }

  .state-tabs {
    display: flex;
    gap: 1rem;
  }

  .tab {
    padding: 0.5rem 1rem;
    text-decoration: none;
    color: #000;
  }

  .tab.active {
    background: #000;
    color: #fff;
  }

  .toolbar-right {
    display: flex;
    gap: 1rem;
    align-items: center;
  }

  .sort-menu {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .sort-menu select {
    padding: 0.5rem;
    border: 2px solid #000;
    font-family: monospace;
  }

  .milestones-list {
    border: 2px solid #000;
  }

  .milestone-item {
    padding: 1.5rem;
    border-bottom: 2px solid #000;
  }

  .milestone-item:last-child {
    border-bottom: none;
  }

  .milestone-header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 0.5rem;
  }

  .milestone-header h3 {
    margin: 0;
  }

  .due-date {
    font-size: 0.875rem;
    font-family: monospace;
  }

  .due-date.overdue {
    color: #d73a49;
    font-weight: bold;
  }

  .milestone-description {
    margin: 0.5rem 0 1rem 0;
    color: #666;
  }

  .milestone-progress {
    margin: 1rem 0;
  }

  .progress-bar {
    height: 10px;
    background: #e1e4e8;
    border: 2px solid #000;
    margin-bottom: 0.25rem;
  }

  .progress-fill {
    height: 100%;
    background: #28a745;
    transition: width 0.3s ease;
  }

  .progress-text {
    font-size: 0.75rem;
    font-family: monospace;
    color: #666;
  }

  .milestone-stats {
    display: flex;
    gap: 1rem;
    margin: 1rem 0;
    font-size: 0.875rem;
    font-family: monospace;
  }

  .milestone-actions {
    display: flex;
    gap: 1rem;
  }

  .empty-state {
    padding: 4rem 2rem;
    text-align: center;
    color: #666;
    font-style: italic;
  }
</style>

<script>
  // Sort dropdown
  const sortSelect = document.getElementById('sort-select') as HTMLSelectElement;
  sortSelect?.addEventListener('change', () => {
    const url = new URL(window.location.href);
    url.searchParams.set('sort', sortSelect.value);
    window.location.href = url.toString();
  });

  // Close/reopen milestone buttons
  async function changeMilestoneState(milestoneId: string, newState: 'open' | 'closed') {
    try {
      const pathParts = window.location.pathname.split('/').slice(1, 3);
      const response = await fetch(
        `/api/${pathParts.join('/')}/milestones/${milestoneId}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ state: newState }),
          credentials: 'include',
        }
      );

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to update milestone');
      }

      window.location.reload();
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Failed to update milestone');
    }
  }

  document.querySelectorAll('.close-milestone-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const milestoneId = (e.target as HTMLElement).dataset.milestoneId;
      if (milestoneId) {
        changeMilestoneState(milestoneId, 'closed');
      }
    });
  });

  document.querySelectorAll('.reopen-milestone-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const milestoneId = (e.target as HTMLElement).dataset.milestoneId;
      if (milestoneId) {
        changeMilestoneState(milestoneId, 'open');
      }
    });
  });

  // Delete milestone buttons
  document.querySelectorAll('.delete-milestone-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const milestoneId = (e.target as HTMLElement).dataset.milestoneId;

      if (!confirm('Are you sure you want to delete this milestone? This will unassign it from all issues.')) {
        return;
      }

      try {
        const pathParts = window.location.pathname.split('/').slice(1, 3);
        const response = await fetch(
          `/api/${pathParts.join('/')}/milestones/${milestoneId}`,
          {
            method: 'DELETE',
            credentials: 'include',
          }
        );

        if (!response.ok) {
          const error = await response.json();
          throw new Error(error.error || 'Failed to delete milestone');
        }

        window.location.reload();
      } catch (error) {
        alert(error instanceof Error ? error.message : 'Failed to delete milestone');
      }
    });
  });
</script>
```

---

## 4. Implementation Checklist

### Phase 1: Database Schema
- [ ] Add labels table to schema.sql
- [ ] Add issue_labels junction table
- [ ] Add milestones table
- [ ] Add milestone_id column to issues table
- [ ] Run database migration

### Phase 2: Backend - Labels
- [ ] Implement label utilities (lib/labels.ts)
  - [ ] Color normalization function
  - [ ] Exclusive scope extraction
  - [ ] Statistics update function
  - [ ] Validation schemas
- [ ] Implement label routes (routes/labels.ts)
  - [ ] GET /:user/:repo/labels (list)
  - [ ] POST /:user/:repo/labels (create)
  - [ ] PATCH /:user/:repo/labels/:id (update)
  - [ ] DELETE /:user/:repo/labels/:id (delete)
  - [ ] POST /:user/:repo/issues/:number/labels (assign)
  - [ ] DELETE /:user/:repo/issues/:number/labels/:labelId (unassign)

### Phase 3: Backend - Milestones
- [ ] Implement milestone utilities (lib/milestones.ts)
  - [ ] Statistics update function
  - [ ] Overdue detection
  - [ ] Enrichment function
  - [ ] Validation schemas
- [ ] Implement milestone routes (routes/milestones.ts)
  - [ ] GET /:user/:repo/milestones (list)
  - [ ] GET /:user/:repo/milestones/:id (detail)
  - [ ] POST /:user/:repo/milestones (create)
  - [ ] PATCH /:user/:repo/milestones/:id (update)
  - [ ] DELETE /:user/:repo/milestones/:id (delete)
  - [ ] PUT /:user/:repo/issues/:number/milestone (assign/unassign)

### Phase 4: Frontend - Labels
- [ ] Create labels page (ui/pages/[user]/[repo]/labels.astro)
  - [ ] Label list with sorting
  - [ ] New/Edit label modal
  - [ ] Color picker with preview
  - [ ] Delete confirmation
  - [ ] Statistics display

### Phase 5: Frontend - Milestones
- [ ] Create milestones list page (ui/pages/[user]/[repo]/milestones.astro)
  - [ ] Milestone list with sorting and filtering
  - [ ] Progress bars
  - [ ] Open/closed tabs
  - [ ] Close/reopen/delete actions
- [ ] Create milestone detail page (ui/pages/[user]/[repo]/milestones/[id].astro)
  - [ ] Show all issues in milestone
  - [ ] Display progress statistics
  - [ ] Edit milestone button
- [ ] Create new/edit milestone pages

### Phase 6: Issue Integration
- [ ] Update issue creation page
  - [ ] Add label selector
  - [ ] Add milestone selector
- [ ] Update issue detail page
  - [ ] Display assigned labels
  - [ ] Display milestone
  - [ ] Allow label/milestone editing
- [ ] Update issue list page
  - [ ] Add label filters
  - [ ] Add milestone filter
  - [ ] Display labels on issue rows

### Phase 7: Testing & Polish
- [ ] Test label CRUD operations
- [ ] Test milestone CRUD operations
- [ ] Test exclusive scope labels
- [ ] Test milestone progress calculation
- [ ] Test label/milestone assignment to issues
- [ ] Test filtering issues by labels
- [ ] Test filtering issues by milestones
- [ ] Add error handling and validation
- [ ] Add loading states

---

## 5. Gitea Reference Translation

### Key Gitea Concepts Translated to Plue

**Label Model** (from `gitea/models/issues/label.go`):
```go
type Label struct {
    ID              int64
    RepoID          int64
    Name            string
    Exclusive       bool
    Description     string
    Color           string `xorm:"VARCHAR(7)"`
    NumIssues       int
    NumClosedIssues int
}
```

Translated to TypeScript/PostgreSQL as shown in section 1.1.

**Milestone Model** (from `gitea/models/issues/milestone.go`):
```go
type Milestone struct {
    ID              int64
    RepoID          int64
    Name            string
    Content         string
    IsClosed        bool
    NumIssues       int
    NumClosedIssues int
    Completeness    int // Percentage(1-100)
    DeadlineUnix    timeutil.TimeStamp
}
```

Translated to TypeScript/PostgreSQL as shown in section 1.3.

**Progress Calculation** (from `gitea/models/issues/milestone.go`):
```go
func (m *Milestone) BeforeUpdate() {
    if m.NumIssues > 0 {
        m.Completeness = m.NumClosedIssues * 100 / m.NumIssues
    } else {
        m.Completeness = 0
    }
}
```

Implemented in `updateMilestoneStats()` function.

---

## 6. Color Palette Suggestions

Provide these default label colors for users:

```typescript
export const DEFAULT_LABEL_COLORS = [
  { name: 'Red', hex: '#D73A49' },
  { name: 'Orange', hex: '#F66A0A' },
  { name: 'Yellow', hex: '#FBB040' },
  { name: 'Green', hex: '#28A745' },
  { name: 'Blue', hex: '#0075CA' },
  { name: 'Purple', hex: '#6F42C1' },
  { name: 'Pink', hex: '#E83E8C' },
  { name: 'Gray', hex: '#6A737D' },
];
```

---

This implementation prompt provides a complete, production-ready labels and milestones feature for Plue, following Gitea's proven patterns while adapting them to Plue's Bun/Hono/Astro stack.
