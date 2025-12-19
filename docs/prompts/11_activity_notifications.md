# Activity & Notifications Feature Implementation

## Overview

Implement a comprehensive activity feed and notification system for Plue, tracking user actions across repositories and providing real-time notifications for issues, PRs, comments, and mentions. This includes activity feeds on dashboards, user contribution heatmaps, repository activity feeds, and in-app notifications.

**Scope**: Activity tracking, notification management, watch/unwatch repositories, contribution graphs, dashboard feeds, notification preferences.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database.

---

## 1. Database Schema Changes

### 1.1 Actions Table (Activity Feed)

```sql
-- User actions for activity feeds
CREATE TABLE IF NOT EXISTS actions (
  id SERIAL PRIMARY KEY,

  -- Actor and recipient
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- Receiver of the feed
  act_user_id BIGINT NOT NULL REFERENCES users(id),                -- Actor who performed action

  -- Action details
  op_type INTEGER NOT NULL,  -- See ActionType enum below
  repo_id BIGINT REFERENCES repositories(id) ON DELETE CASCADE,
  comment_id BIGINT REFERENCES comments(id) ON DELETE SET NULL,

  -- Metadata
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  is_private BOOLEAN NOT NULL DEFAULT false,
  ref_name VARCHAR(255),  -- Branch/tag name for git operations
  content TEXT,           -- JSON or pipe-delimited data (e.g., "123|Issue Title" or commit JSON)

  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX idx_actions_user_id ON actions(user_id);
CREATE INDEX idx_actions_act_user_id ON actions(act_user_id);
CREATE INDEX idx_actions_repo_id ON actions(repo_id);
CREATE INDEX idx_actions_user_repo ON actions(repo_id, user_id, is_deleted);
CREATE INDEX idx_actions_created ON actions(created_at, user_id, is_deleted);
CREATE INDEX idx_actions_act_user_created ON actions(act_user_id, repo_id, created_at, user_id, is_deleted);
```

**ActionType Enum** (stored as INTEGER):
```typescript
enum ActionType {
  CreateRepo = 1,
  RenameRepo = 2,
  StarRepo = 3,
  WatchRepo = 4,
  CommitRepo = 5,
  CreateIssue = 6,
  CreatePullRequest = 7,
  TransferRepo = 8,
  PushTag = 9,
  CommentIssue = 10,
  MergePullRequest = 11,
  CloseIssue = 12,
  ReopenIssue = 13,
  ClosePullRequest = 14,
  ReopenPullRequest = 15,
  DeleteTag = 16,
  DeleteBranch = 17,
  PublishRelease = 24,
  AutoMergePullRequest = 27
}
```

### 1.2 Notifications Table

```sql
-- In-app notifications
CREATE TABLE IF NOT EXISTS notifications (
  id SERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repo_id BIGINT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  -- Status and source
  status SMALLINT NOT NULL DEFAULT 1,  -- 1=unread, 2=read, 3=pinned
  source SMALLINT NOT NULL DEFAULT 1,  -- 1=issue, 2=pull_request, 3=commit, 4=repository

  -- Related entities
  issue_id BIGINT REFERENCES issues(id) ON DELETE CASCADE,
  comment_id BIGINT REFERENCES comments(id) ON DELETE SET NULL,
  commit_id VARCHAR(64),

  -- Updated by (who triggered the notification)
  updated_by BIGINT NOT NULL REFERENCES users(id),

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_repo_id ON notifications(repo_id);
CREATE INDEX idx_notifications_issue_id ON notifications(issue_id);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_notifications_user_status_updated ON notifications(user_id, status, updated_at);
```

**NotificationStatus Enum**:
```typescript
enum NotificationStatus {
  Unread = 1,
  Read = 2,
  Pinned = 3
}
```

**NotificationSource Enum**:
```typescript
enum NotificationSource {
  Issue = 1,
  PullRequest = 2,
  Commit = 3,
  Repository = 4
}
```

### 1.3 Repository Watches Table

```sql
-- Repository watch status
CREATE TABLE IF NOT EXISTS watches (
  id SERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repo_id BIGINT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  mode SMALLINT NOT NULL DEFAULT 1,  -- 0=none, 1=normal, 2=dont, 3=auto

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(user_id, repo_id)
);

CREATE INDEX idx_watches_user_id ON watches(user_id);
CREATE INDEX idx_watches_repo_id ON watches(repo_id);
```

**WatchMode Enum**:
```typescript
enum WatchMode {
  None = 0,      // Not watching
  Normal = 1,    // Watching (manual)
  Dont = 2,      // Explicitly not watching
  Auto = 3       // Auto-watch from changes
}
```

### 1.4 Issue Watches Table (for granular issue subscriptions)

```sql
-- Issue-level watch/subscribe
CREATE TABLE IF NOT EXISTS issue_watches (
  id SERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  issue_id BIGINT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  is_watching BOOLEAN NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(user_id, issue_id)
);

CREATE INDEX idx_issue_watches_user_id ON issue_watches(user_id);
CREATE INDEX idx_issue_watches_issue_id ON issue_watches(issue_id);
```

### 1.5 Add to Repositories Table

```sql
-- Add watch count to repositories table
ALTER TABLE repositories ADD COLUMN num_watches INTEGER DEFAULT 0;

CREATE INDEX idx_repositories_num_watches ON repositories(num_watches);
```

---

## 2. Backend API (Hono)

### 2.1 Activity Feed Service (`server/services/activity.ts`)

```typescript
import { db } from "../../db/index";
import type { User } from "../../db/schema";

export enum ActionType {
  CreateRepo = 1,
  RenameRepo = 2,
  StarRepo = 3,
  WatchRepo = 4,
  CommitRepo = 5,
  CreateIssue = 6,
  CreatePullRequest = 7,
  TransferRepo = 8,
  PushTag = 9,
  CommentIssue = 10,
  MergePullRequest = 11,
  CloseIssue = 12,
  ReopenIssue = 13,
  ClosePullRequest = 14,
  ReopenPullRequest = 15,
  DeleteTag = 16,
  DeleteBranch = 17,
  PublishRelease = 24,
  AutoMergePullRequest = 27,
}

interface CreateActionParams {
  actUserId: number;
  opType: ActionType;
  repoId: number;
  commentId?: number;
  refName?: string;
  content?: string;
  isPrivate?: boolean;
}

/**
 * Create an action and notify all watchers of the repository.
 * This creates multiple action records:
 * - One for the actor
 * - One for the repo owner (if org)
 * - One for each watcher
 */
export async function notifyWatchers(params: CreateActionParams) {
  const { actUserId, opType, repoId, commentId, refName, content, isPrivate } = params;

  // Get repository details
  const [repo] = await db.sql`
    SELECT r.*, u.id as owner_id, u.username as owner_name
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE r.id = ${repoId}
  `;

  if (!repo) {
    throw new Error(`Repository ${repoId} not found`);
  }

  // Truncate content if too long (PostgreSQL TEXT limit)
  let truncatedContent = content || "";
  if (truncatedContent.length > 65535) {
    truncatedContent = truncatedContent.substring(0, 65535);
  }

  const baseAction = {
    act_user_id: actUserId,
    op_type: opType,
    repo_id: repoId,
    comment_id: commentId || null,
    ref_name: refName || null,
    content: truncatedContent,
    is_private: isPrivate || repo.is_public === false,
    is_deleted: false,
  };

  // Insert action for actor
  await db.sql`
    INSERT INTO actions (user_id, act_user_id, op_type, repo_id, comment_id, ref_name, content, is_private, is_deleted)
    VALUES (${actUserId}, ${baseAction.act_user_id}, ${baseAction.op_type}, ${baseAction.repo_id},
            ${baseAction.comment_id}, ${baseAction.ref_name}, ${baseAction.content},
            ${baseAction.is_private}, ${baseAction.is_deleted})
  `;

  // Insert action for repository owner if different from actor
  if (repo.owner_id !== actUserId) {
    await db.sql`
      INSERT INTO actions (user_id, act_user_id, op_type, repo_id, comment_id, ref_name, content, is_private, is_deleted)
      VALUES (${repo.owner_id}, ${baseAction.act_user_id}, ${baseAction.op_type}, ${baseAction.repo_id},
              ${baseAction.comment_id}, ${baseAction.ref_name}, ${baseAction.content},
              ${baseAction.is_private}, ${baseAction.is_deleted})
    `;
  }

  // Get watchers (mode 1 or 3, not 0 or 2)
  const watchers = await db.sql`
    SELECT user_id
    FROM watches
    WHERE repo_id = ${repoId}
    AND mode IN (1, 3)
  `;

  // Insert action for each watcher
  for (const watcher of watchers) {
    if (watcher.user_id === actUserId) continue; // Skip actor

    await db.sql`
      INSERT INTO actions (user_id, act_user_id, op_type, repo_id, comment_id, ref_name, content, is_private, is_deleted)
      VALUES (${watcher.user_id}, ${baseAction.act_user_id}, ${baseAction.op_type}, ${baseAction.repo_id},
              ${baseAction.comment_id}, ${baseAction.ref_name}, ${baseAction.content},
              ${baseAction.is_private}, ${baseAction.is_deleted})
    `;
  }
}

interface GetFeedsOptions {
  userId: number;
  actorId?: number;      // Viewing user (for permission checks)
  repoId?: number;       // Filter by repository
  onlyPerformedBy?: boolean;  // Only actions by userId
  includePrivate?: boolean;
  includeDeleted?: boolean;
  limit?: number;
  offset?: number;
}

/**
 * Get activity feed for a user
 */
export async function getFeeds(options: GetFeedsOptions) {
  const {
    userId,
    actorId,
    repoId,
    onlyPerformedBy = false,
    includePrivate = false,
    includeDeleted = false,
    limit = 20,
    offset = 0,
  } = options;

  let query = db.sql`
    SELECT
      a.*,
      u.username as act_user_name,
      u.display_name as act_user_display_name,
      r.name as repo_name,
      r.user_id as repo_owner_id,
      owner.username as repo_owner_name
    FROM actions a
    JOIN users u ON a.act_user_id = u.id
    LEFT JOIN repositories r ON a.repo_id = r.id
    LEFT JOIN users owner ON r.user_id = owner.id
    WHERE a.user_id = ${userId}
  `;

  if (!includePrivate) {
    query = db.sql`${query} AND a.is_private = false`;
  }

  if (!includeDeleted) {
    query = db.sql`${query} AND a.is_deleted = false`;
  }

  if (onlyPerformedBy) {
    query = db.sql`${query} AND a.act_user_id = ${userId}`;
  }

  if (repoId) {
    query = db.sql`${query} AND a.repo_id = ${repoId}`;
  }

  query = db.sql`
    ${query}
    ORDER BY a.created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  return await query;
}

/**
 * Get user heatmap data for contribution graph
 * Groups actions by day and counts contributions
 */
export async function getUserHeatmapData(userId: number, days: number = 366) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  const data = await db.sql`
    SELECT
      DATE_TRUNC('day', created_at) as timestamp,
      COUNT(*) as contributions
    FROM actions
    WHERE act_user_id = ${userId}
    AND created_at > ${cutoff.toISOString()}
    AND is_deleted = false
    GROUP BY DATE_TRUNC('day', created_at)
    ORDER BY timestamp
  `;

  return data;
}
```

### 2.2 Notification Service (`server/services/notifications.ts`)

```typescript
import { db } from "../../db/index";

export enum NotificationStatus {
  Unread = 1,
  Read = 2,
  Pinned = 3,
}

export enum NotificationSource {
  Issue = 1,
  PullRequest = 2,
  Commit = 3,
  Repository = 4,
}

interface CreateNotificationParams {
  userId: number;
  repoId: number;
  issueId?: number;
  commentId?: number;
  commitId?: string;
  source: NotificationSource;
  updatedBy: number;
}

/**
 * Create or update a notification for a user
 */
export async function createOrUpdateIssueNotification(
  issueId: number,
  commentId: number | null,
  updatedBy: number,
  receiverId?: number
) {
  // Get issue details
  const [issue] = await db.sql`
    SELECT i.*, r.id as repo_id, r.is_public
    FROM issues i
    JOIN repositories r ON i.repository_id = r.id
    WHERE i.id = ${issueId}
  `;

  if (!issue) {
    throw new Error(`Issue ${issueId} not found`);
  }

  const source = NotificationSource.Issue; // Update if PR

  // Determine who to notify
  let toNotify: number[] = [];

  if (receiverId) {
    toNotify = [receiverId];
  } else {
    // Get issue watchers
    const issueWatchers = await db.sql`
      SELECT user_id FROM issue_watches
      WHERE issue_id = ${issueId} AND is_watching = true
    `;

    // Get repo watchers
    const repoWatchers = await db.sql`
      SELECT user_id FROM watches
      WHERE repo_id = ${issue.repo_id} AND mode IN (1, 3)
    `;

    // Get issue participants (author + commenters)
    const participants = await db.sql`
      SELECT DISTINCT author_id as user_id FROM comments WHERE issue_id = ${issueId}
      UNION
      SELECT author_id as user_id FROM issues WHERE id = ${issueId}
    `;

    // Combine all
    const allNotifyIds = new Set([
      ...issueWatchers.map((w: any) => w.user_id),
      ...repoWatchers.map((w: any) => w.user_id),
      ...participants.map((p: any) => p.user_id),
    ]);

    // Remove the person who triggered the notification
    allNotifyIds.delete(updatedBy);

    // Remove explicit unwatchers
    const unwatchers = await db.sql`
      SELECT user_id FROM issue_watches
      WHERE issue_id = ${issueId} AND is_watching = false
    `;
    unwatchers.forEach((u: any) => allNotifyIds.delete(u.user_id));

    toNotify = Array.from(allNotifyIds);
  }

  // Create or update notifications
  for (const userId of toNotify) {
    const [existing] = await db.sql`
      SELECT id, status FROM notifications
      WHERE user_id = ${userId} AND issue_id = ${issueId}
    `;

    if (existing) {
      // Update existing notification
      if (existing.status === NotificationStatus.Read) {
        // Mark as unread and update comment
        await db.sql`
          UPDATE notifications
          SET status = ${NotificationStatus.Unread},
              comment_id = ${commentId},
              updated_by = ${updatedBy},
              updated_at = NOW()
          WHERE id = ${existing.id}
        `;
      } else {
        // Just update the updatedBy
        await db.sql`
          UPDATE notifications
          SET updated_by = ${updatedBy}, updated_at = NOW()
          WHERE id = ${existing.id}
        `;
      }
    } else {
      // Create new notification
      await db.sql`
        INSERT INTO notifications (user_id, repo_id, issue_id, comment_id, source, status, updated_by)
        VALUES (${userId}, ${issue.repo_id}, ${issueId}, ${commentId}, ${source}, ${NotificationStatus.Unread}, ${updatedBy})
      `;
    }
  }
}

/**
 * Get notifications for a user
 */
export async function getNotifications(
  userId: number,
  status?: NotificationStatus,
  limit: number = 20,
  offset: number = 0
) {
  let query = db.sql`
    SELECT
      n.*,
      r.name as repo_name,
      r.user_id as repo_owner_id,
      owner.username as repo_owner_name,
      i.title as issue_title,
      i.issue_number,
      c.body as comment_body,
      u.username as updated_by_username
    FROM notifications n
    JOIN repositories r ON n.repo_id = r.id
    JOIN users owner ON r.user_id = owner.id
    LEFT JOIN issues i ON n.issue_id = i.id
    LEFT JOIN comments c ON n.comment_id = c.id
    LEFT JOIN users u ON n.updated_by = u.id
    WHERE n.user_id = ${userId}
  `;

  if (status !== undefined) {
    query = db.sql`${query} AND n.status = ${status}`;
  }

  query = db.sql`
    ${query}
    ORDER BY n.updated_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  return await query;
}

/**
 * Mark notification as read
 */
export async function setNotificationStatus(
  notificationId: number,
  userId: number,
  status: NotificationStatus
) {
  const [notification] = await db.sql`
    UPDATE notifications
    SET status = ${status}, updated_at = NOW()
    WHERE id = ${notificationId} AND user_id = ${userId}
    RETURNING *
  `;

  return notification;
}

/**
 * Mark all notifications as read
 */
export async function markAllAsRead(userId: number) {
  await db.sql`
    UPDATE notifications
    SET status = ${NotificationStatus.Read}, updated_at = NOW()
    WHERE user_id = ${userId} AND status = ${NotificationStatus.Unread}
  `;
}

/**
 * Get unread notification count
 */
export async function getUnreadCount(userId: number): Promise<number> {
  const [result] = await db.sql`
    SELECT COUNT(*) as count
    FROM notifications
    WHERE user_id = ${userId} AND status = ${NotificationStatus.Unread}
  `;

  return result?.count || 0;
}
```

### 2.3 Watch Service (`server/services/watch.ts`)

```typescript
import { db } from "../../db/index";

export enum WatchMode {
  None = 0,
  Normal = 1,
  Dont = 2,
  Auto = 3,
}

/**
 * Watch or unwatch a repository
 */
export async function watchRepo(userId: number, repoId: number, doWatch: boolean) {
  const [existing] = await db.sql`
    SELECT id, mode FROM watches
    WHERE user_id = ${userId} AND repo_id = ${repoId}
  `;

  const targetMode = doWatch ? WatchMode.Normal : WatchMode.None;

  if (existing) {
    if (existing.mode === targetMode) {
      return; // Already in desired state
    }

    const oldMode = existing.mode;
    const newMode = targetMode;

    await db.sql`
      UPDATE watches
      SET mode = ${newMode}, updated_at = NOW()
      WHERE id = ${existing.id}
    `;

    // Update watch count
    const isWatching = (mode: WatchMode) => mode === WatchMode.Normal || mode === WatchMode.Auto;
    if (isWatching(newMode) && !isWatching(oldMode)) {
      await db.sql`UPDATE repositories SET num_watches = num_watches + 1 WHERE id = ${repoId}`;
    } else if (!isWatching(newMode) && isWatching(oldMode)) {
      await db.sql`UPDATE repositories SET num_watches = num_watches - 1 WHERE id = ${repoId}`;
    }
  } else if (targetMode !== WatchMode.None) {
    await db.sql`
      INSERT INTO watches (user_id, repo_id, mode)
      VALUES (${userId}, ${repoId}, ${targetMode})
    `;

    await db.sql`UPDATE repositories SET num_watches = num_watches + 1 WHERE id = ${repoId}`;
  }
}

/**
 * Check if user is watching a repository
 */
export async function isWatching(userId: number, repoId: number): Promise<boolean> {
  const [watch] = await db.sql`
    SELECT mode FROM watches
    WHERE user_id = ${userId} AND repo_id = ${repoId}
  `;

  if (!watch) return false;
  return watch.mode === WatchMode.Normal || watch.mode === WatchMode.Auto;
}

/**
 * Get watchers of a repository
 */
export async function getWatchers(repoId: number) {
  return await db.sql`
    SELECT u.id, u.username, u.display_name
    FROM watches w
    JOIN users u ON w.user_id = u.id
    WHERE w.repo_id = ${repoId} AND w.mode IN (${WatchMode.Normal}, ${WatchMode.Auto})
  `;
}

/**
 * Watch/unwatch an issue
 */
export async function watchIssue(userId: number, issueId: number, doWatch: boolean) {
  const [existing] = await db.sql`
    SELECT id FROM issue_watches
    WHERE user_id = ${userId} AND issue_id = ${issueId}
  `;

  if (existing) {
    await db.sql`
      UPDATE issue_watches
      SET is_watching = ${doWatch}, updated_at = NOW()
      WHERE id = ${existing.id}
    `;
  } else {
    await db.sql`
      INSERT INTO issue_watches (user_id, issue_id, is_watching)
      VALUES (${userId}, ${issueId}, ${doWatch})
    `;
  }
}
```

### 2.4 API Routes (`server/routes/activity.ts`)

```typescript
import { Hono } from "hono";
import { getFeeds, getUserHeatmapData } from "../services/activity";
import {
  getNotifications,
  setNotificationStatus,
  markAllAsRead,
  getUnreadCount,
  NotificationStatus
} from "../services/notifications";
import { watchRepo, watchIssue, isWatching } from "../services/watch";

const app = new Hono();

// Get activity feed for current user or specific user
app.get("/feeds/:username?", async (c) => {
  const username = c.req.param("username");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = parseInt(c.req.query("offset") || "0");
  const onlyPerformedBy = c.req.query("onlyPerformedBy") === "true";

  // TODO: Get current user from session
  const currentUserId = 1; // Placeholder

  let targetUserId = currentUserId;
  if (username) {
    const [user] = await db.sql`SELECT id FROM users WHERE username = ${username}`;
    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }
    targetUserId = user.id;
  }

  const feeds = await getFeeds({
    userId: targetUserId,
    actorId: currentUserId,
    onlyPerformedBy,
    includePrivate: targetUserId === currentUserId,
    limit,
    offset,
  });

  return c.json({ feeds });
});

// Get user contribution heatmap
app.get("/heatmap/:username", async (c) => {
  const username = c.req.param("username");
  const [user] = await db.sql`SELECT id FROM users WHERE username = ${username}`;

  if (!user) {
    return c.json({ error: "User not found" }, 404);
  }

  const data = await getUserHeatmapData(user.id);
  return c.json({ heatmap: data });
});

// Get notifications
app.get("/notifications", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const status = c.req.query("status");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = parseInt(c.req.query("offset") || "0");

  let statusFilter: NotificationStatus | undefined;
  if (status === "read") statusFilter = NotificationStatus.Read;
  if (status === "unread") statusFilter = NotificationStatus.Unread;
  if (status === "pinned") statusFilter = NotificationStatus.Pinned;

  const notifications = await getNotifications(currentUserId, statusFilter, limit, offset);
  return c.json({ notifications });
});

// Get unread count
app.get("/notifications/count", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const count = await getUnreadCount(currentUserId);
  return c.json({ count });
});

// Mark notification as read/unread/pinned
app.post("/notifications/:id/status", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const notificationId = parseInt(c.req.param("id"));
  const { status } = await c.req.json();

  const notification = await setNotificationStatus(notificationId, currentUserId, status);
  return c.json({ notification });
});

// Mark all as read
app.post("/notifications/mark-all-read", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  await markAllAsRead(currentUserId);
  return c.json({ success: true });
});

// Watch/unwatch repository
app.post("/repos/:owner/:repo/watch", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const { owner, repo } = c.req.param();
  const { watch } = await c.req.json();

  const [repository] = await db.sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await watchRepo(currentUserId, repository.id, watch);
  return c.json({ success: true });
});

// Check watch status
app.get("/repos/:owner/:repo/watch", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const { owner, repo } = c.req.param();

  const [repository] = await db.sql`
    SELECT r.id FROM repositories r
    JOIN users u ON r.user_id = u.id
    WHERE u.username = ${owner} AND r.name = ${repo}
  `;

  if (!repository) {
    return c.json({ error: "Repository not found" }, 404);
  }

  const watching = await isWatching(currentUserId, repository.id);
  return c.json({ watching });
});

// Watch/unwatch issue
app.post("/issues/:id/watch", async (c) => {
  const currentUserId = 1; // TODO: Get from session
  const issueId = parseInt(c.req.param("id"));
  const { watch } = await c.req.json();

  await watchIssue(currentUserId, issueId, watch);
  return c.json({ success: true });
});

export default app;
```

---

## 3. Frontend UI (Astro)

### 3.1 Dashboard Activity Feed (`ui/pages/dashboard.astro`)

```astro
---
import Layout from "../layouts/Layout.astro";
import Header from "../components/Header.astro";
import ActivityFeed from "../components/ActivityFeed.astro";
import { sql } from "../lib/db";

// TODO: Get current user from session
const currentUserId = 1;

const [user] = await sql`SELECT * FROM users WHERE id = ${currentUserId}`;

const feeds = await sql`
  SELECT
    a.*,
    u.username as act_user_name,
    u.display_name as act_user_display_name,
    r.name as repo_name,
    owner.username as repo_owner_name
  FROM actions a
  JOIN users u ON a.act_user_id = u.id
  LEFT JOIN repositories r ON a.repo_id = r.id
  LEFT JOIN users owner ON r.user_id = owner.id
  WHERE a.user_id = ${currentUserId}
  AND a.is_deleted = false
  ORDER BY a.created_at DESC
  LIMIT 50
`;

const unreadCount = await sql`
  SELECT COUNT(*) as count FROM notifications
  WHERE user_id = ${currentUserId} AND status = 1
`;
---

<Layout title="Dashboard · plue">
  <Header currentPath="/dashboard" unreadCount={unreadCount[0].count} />
  <div class="container">
    <div class="dashboard-header">
      <h1 class="page-title">Dashboard</h1>
      <a href="/notifications" class="btn">
        Notifications {unreadCount[0].count > 0 && `(${unreadCount[0].count})`}
      </a>
    </div>

    <div class="dashboard-grid">
      <div class="main-content">
        <h2 class="section-title">Recent Activity</h2>
        <ActivityFeed feeds={feeds} />
      </div>

      <aside class="sidebar">
        <div class="sidebar-section">
          <h3>Your repositories</h3>
          <!-- List user repos -->
        </div>
      </aside>
    </div>
  </div>
</Layout>

<style>
  .dashboard-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
  }

  .dashboard-grid {
    display: grid;
    grid-template-columns: 1fr 300px;
    gap: 24px;
  }

  @media (max-width: 768px) {
    .dashboard-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
```

### 3.2 Activity Feed Component (`ui/components/ActivityFeed.astro`)

```astro
---
interface Props {
  feeds: any[];
}

const { feeds } = Astro.props;

function formatActionType(opType: number): string {
  const types: Record<number, string> = {
    1: "created repository",
    5: "pushed to",
    6: "opened issue",
    7: "opened pull request",
    10: "commented on issue",
    11: "merged pull request",
    12: "closed issue",
    13: "reopened issue",
    24: "published release",
  };
  return types[opType] || "performed action on";
}

function formatTimestamp(date: string): string {
  const d = new Date(date);
  const now = new Date();
  const diff = now.getTime() - d.getTime();
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days} day${days > 1 ? 's' : ''} ago`;
  if (hours > 0) return `${hours} hour${hours > 1 ? 's' : ''} ago`;
  if (minutes > 0) return `${minutes} minute${minutes > 1 ? 's' : ''} ago`;
  return 'just now';
}
---

<div class="activity-feed">
  {feeds.length === 0 ? (
    <div class="empty-state">
      <p>No recent activity</p>
    </div>
  ) : (
    <ul class="feed-list">
      {feeds.map((feed) => {
        const actionText = formatActionType(feed.op_type);
        const repoPath = `${feed.repo_owner_name}/${feed.repo_name}`;

        return (
          <li class="feed-item">
            <div class="feed-icon">
              <!-- Icon based on action type -->
              <span class="icon">•</span>
            </div>
            <div class="feed-content">
              <div class="feed-header">
                <strong>{feed.act_user_display_name || feed.act_user_name}</strong>
                {" "}{actionText}{" "}
                <a href={`/${repoPath}`}>{repoPath}</a>
              </div>
              <div class="feed-meta">
                {formatTimestamp(feed.created_at)}
              </div>
            </div>
          </li>
        );
      })}
    </ul>
  )}
</div>

<style>
  .activity-feed {
    border: 1px solid var(--border);
    background: var(--bg-secondary);
  }

  .feed-list {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .feed-item {
    display: flex;
    gap: 12px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
  }

  .feed-item:last-child {
    border-bottom: none;
  }

  .feed-icon {
    flex-shrink: 0;
    width: 24px;
    height: 24px;
  }

  .feed-content {
    flex: 1;
    min-width: 0;
  }

  .feed-header {
    font-size: 14px;
    line-height: 1.5;
  }

  .feed-meta {
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 4px;
  }

  .empty-state {
    padding: 48px 16px;
    text-align: center;
    color: var(--text-muted);
  }
</style>
```

### 3.3 User Profile with Heatmap (`ui/pages/[user]/index.astro`)

Update the existing user profile page to include contribution heatmap:

```astro
---
import Layout from "../../layouts/Layout.astro";
import Header from "../../components/Header.astro";
import RepoCard from "../../components/RepoCard.astro";
import ContributionGraph from "../../components/ContributionGraph.astro";
import { sql } from "../../lib/db";
import type { User, Repository } from "../../lib/types";

const { user: username } = Astro.params;

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];

if (!user) {
  return Astro.redirect("/404");
}

const repos = await sql`
  SELECT r.*, u.username
  FROM repositories r
  JOIN users u ON r.user_id = u.id
  WHERE r.user_id = ${user.id} AND r.is_public = true
  ORDER BY r.updated_at DESC
` as Repository[];

// Get heatmap data
const heatmapData = await sql`
  SELECT
    DATE_TRUNC('day', created_at) as timestamp,
    COUNT(*) as contributions
  FROM actions
  WHERE act_user_id = ${user.id}
  AND created_at > NOW() - INTERVAL '366 days'
  AND is_deleted = false
  GROUP BY DATE_TRUNC('day', created_at)
  ORDER BY timestamp
`;
---

<Layout title={`${user.username} · plue`}>
  <Header />
  <div class="container">
    <div class="user-profile mb-3">
      <h1 class="page-title">{user.display_name || user.username}</h1>
      {user.bio && <p class="bio">{user.bio}</p>}
    </div>

    <div class="contribution-section mb-3">
      <h2 class="mb-2">Contribution Activity</h2>
      <ContributionGraph data={heatmapData} />
    </div>

    <h2 class="mb-2">Repositories</h2>

    {repos.length === 0 ? (
      <div class="empty-state">
        <p>No repositories yet</p>
      </div>
    ) : (
      <ul class="repo-list">
        {repos.map((repo) => (
          <RepoCard repo={repo} showUser={false} />
        ))}
      </ul>
    )}
  </div>
</Layout>

<style>
  .user-profile {
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border);
  }

  .bio {
    margin-top: 8px;
  }

  .contribution-section {
    padding: 16px;
    border: 1px solid var(--border);
    background: var(--bg-secondary);
  }
</style>
```

### 3.4 Contribution Heatmap Component (`ui/components/ContributionGraph.astro`)

```astro
---
interface Props {
  data: Array<{ timestamp: string; contributions: number }>;
}

const { data } = Astro.props;

// Calculate total contributions
const total = data.reduce((sum, d) => sum + Number(d.contributions), 0);
---

<div class="contribution-graph">
  <div class="graph-header">
    <span class="total-contributions">{total} contributions in the last year</span>
  </div>
  <div class="graph-container" id="heatmap-container">
    <!-- Heatmap will be rendered client-side -->
  </div>
  <div class="graph-legend">
    <span>Less</span>
    <div class="legend-colors">
      <span class="legend-box level-0"></span>
      <span class="legend-box level-1"></span>
      <span class="legend-box level-2"></span>
      <span class="legend-box level-3"></span>
      <span class="legend-box level-4"></span>
    </div>
    <span>More</span>
  </div>
</div>

<script define:vars={{ data }}>
  // Simple heatmap rendering
  const container = document.getElementById('heatmap-container');

  // Group data by week
  const weeks = [];
  let currentWeek = [];

  // Fill in missing days with 0 contributions
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - 365);

  const dataMap = new Map();
  data.forEach(d => {
    const date = new Date(d.timestamp);
    const key = date.toISOString().split('T')[0];
    dataMap.set(key, Number(d.contributions));
  });

  for (let i = 0; i < 365; i++) {
    const date = new Date(startDate);
    date.setDate(startDate.getDate() + i);
    const key = date.toISOString().split('T')[0];
    const contributions = dataMap.get(key) || 0;

    currentWeek.push({ date, contributions });

    if (currentWeek.length === 7) {
      weeks.push(currentWeek);
      currentWeek = [];
    }
  }

  if (currentWeek.length > 0) {
    weeks.push(currentWeek);
  }

  // Determine color level based on contributions
  function getLevel(contributions) {
    if (contributions === 0) return 0;
    if (contributions < 3) return 1;
    if (contributions < 6) return 2;
    if (contributions < 10) return 3;
    return 4;
  }

  // Render heatmap
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width', weeks.length * 14);
  svg.setAttribute('height', 7 * 14);

  weeks.forEach((week, weekIndex) => {
    week.forEach((day, dayIndex) => {
      const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x', weekIndex * 14);
      rect.setAttribute('y', dayIndex * 14);
      rect.setAttribute('width', 12);
      rect.setAttribute('height', 12);
      rect.setAttribute('class', `heatmap-cell level-${getLevel(day.contributions)}`);
      rect.setAttribute('data-date', day.date.toISOString().split('T')[0]);
      rect.setAttribute('data-contributions', day.contributions);

      // Tooltip on hover
      rect.addEventListener('mouseenter', (e) => {
        const tooltip = document.createElement('div');
        tooltip.className = 'heatmap-tooltip';
        tooltip.textContent = `${day.contributions} contributions on ${day.date.toLocaleDateString()}`;
        tooltip.style.position = 'fixed';
        tooltip.style.left = e.clientX + 10 + 'px';
        tooltip.style.top = e.clientY + 10 + 'px';
        document.body.appendChild(tooltip);
        rect._tooltip = tooltip;
      });

      rect.addEventListener('mouseleave', () => {
        if (rect._tooltip) {
          rect._tooltip.remove();
        }
      });

      svg.appendChild(rect);
    });
  });

  container.appendChild(svg);
</script>

<style>
  .contribution-graph {
    padding: 16px;
  }

  .graph-header {
    margin-bottom: 16px;
    font-size: 14px;
    color: var(--text-muted);
  }

  .graph-container {
    overflow-x: auto;
    margin-bottom: 8px;
  }

  :global(.heatmap-cell) {
    fill: #eee;
    stroke: #fff;
    stroke-width: 2;
  }

  :global(.heatmap-cell.level-0) { fill: #ebedf0; }
  :global(.heatmap-cell.level-1) { fill: #9be9a8; }
  :global(.heatmap-cell.level-2) { fill: #40c463; }
  :global(.heatmap-cell.level-3) { fill: #30a14e; }
  :global(.heatmap-cell.level-4) { fill: #216e39; }

  :global(.heatmap-tooltip) {
    background: #000;
    color: #fff;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    pointer-events: none;
    z-index: 1000;
  }

  .graph-legend {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 12px;
    color: var(--text-muted);
  }

  .legend-colors {
    display: flex;
    gap: 2px;
  }

  .legend-box {
    width: 12px;
    height: 12px;
    border: 1px solid #fff;
  }

  .legend-box.level-0 { background: #ebedf0; }
  .legend-box.level-1 { background: #9be9a8; }
  .legend-box.level-2 { background: #40c463; }
  .legend-box.level-3 { background: #30a14e; }
  .legend-box.level-4 { background: #216e39; }
</style>
```

### 3.5 Notifications Page (`ui/pages/notifications.astro`)

```astro
---
import Layout from "../layouts/Layout.astro";
import Header from "../components/Header.astro";
import { sql } from "../lib/db";

// TODO: Get current user from session
const currentUserId = 1;

const status = Astro.url.searchParams.get("status") || "unread";
const statusFilter = status === "read" ? 2 : status === "pinned" ? 3 : 1;

const notifications = await sql`
  SELECT
    n.*,
    r.name as repo_name,
    owner.username as repo_owner_name,
    i.title as issue_title,
    i.issue_number,
    c.body as comment_body,
    u.username as updated_by_username
  FROM notifications n
  JOIN repositories r ON n.repo_id = r.id
  JOIN users owner ON r.user_id = owner.id
  LEFT JOIN issues i ON n.issue_id = i.id
  LEFT JOIN comments c ON n.comment_id = c.id
  LEFT JOIN users u ON n.updated_by = u.id
  WHERE n.user_id = ${currentUserId}
  AND n.status = ${statusFilter}
  ORDER BY n.updated_at DESC
`;

const unreadCount = await sql`
  SELECT COUNT(*) as count FROM notifications
  WHERE user_id = ${currentUserId} AND status = 1
`;
---

<Layout title="Notifications · plue">
  <Header currentPath="/notifications" unreadCount={unreadCount[0].count} />
  <div class="container">
    <div class="notifications-header">
      <h1 class="page-title">Notifications</h1>
      <form method="POST" action="/api/notifications/mark-all-read">
        <button type="submit" class="btn btn-secondary">Mark all as read</button>
      </form>
    </div>

    <div class="notification-filters">
      <a
        href="/notifications?status=unread"
        class={status === 'unread' ? 'active' : ''}
      >
        Unread {unreadCount[0].count > 0 && `(${unreadCount[0].count})`}
      </a>
      <a
        href="/notifications?status=read"
        class={status === 'read' ? 'active' : ''}
      >
        Read
      </a>
      <a
        href="/notifications?status=pinned"
        class={status === 'pinned' ? 'active' : ''}
      >
        Pinned
      </a>
    </div>

    {notifications.length === 0 ? (
      <div class="empty-state">
        <p>No notifications</p>
      </div>
    ) : (
      <ul class="notification-list">
        {notifications.map((notification) => {
          const repoPath = `${notification.repo_owner_name}/${notification.repo_name}`;
          const issueUrl = `/${repoPath}/issues/${notification.issue_number}`;

          return (
            <li class="notification-item" data-id={notification.id}>
              <div class="notification-icon">
                {notification.source === 1 && <span>📋</span>}
                {notification.source === 2 && <span>🔀</span>}
              </div>
              <div class="notification-content">
                <div class="notification-title">
                  <a href={issueUrl}>{notification.issue_title}</a>
                </div>
                <div class="notification-meta">
                  <a href={`/${repoPath}`}>{repoPath}</a>
                  {" · "}
                  Updated by {notification.updated_by_username}
                  {" · "}
                  <time>{new Date(notification.updated_at).toLocaleDateString()}</time>
                </div>
              </div>
              <div class="notification-actions">
                <button
                  class="mark-read-btn"
                  data-id={notification.id}
                  data-status={notification.status === 1 ? 2 : 1}
                >
                  {notification.status === 1 ? 'Mark read' : 'Mark unread'}
                </button>
              </div>
            </li>
          );
        })}
      </ul>
    )}
  </div>
</Layout>

<script>
  document.querySelectorAll('.mark-read-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = btn.getAttribute('data-id');
      const status = btn.getAttribute('data-status');

      const response = await fetch(`/api/notifications/${id}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: parseInt(status) })
      });

      if (response.ok) {
        window.location.reload();
      }
    });
  });
</script>

<style>
  .notifications-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
  }

  .notification-filters {
    display: flex;
    gap: 16px;
    margin-bottom: 16px;
    border-bottom: 1px solid var(--border);
    padding-bottom: 8px;
  }

  .notification-filters a {
    padding: 8px 12px;
    text-decoration: none;
    color: var(--text-muted);
    border-bottom: 2px solid transparent;
  }

  .notification-filters a.active {
    color: var(--text);
    border-bottom-color: var(--primary);
  }

  .notification-list {
    list-style: none;
    margin: 0;
    padding: 0;
    border: 1px solid var(--border);
  }

  .notification-item {
    display: flex;
    gap: 12px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    background: var(--bg-secondary);
  }

  .notification-item:last-child {
    border-bottom: none;
  }

  .notification-icon {
    flex-shrink: 0;
    width: 24px;
    height: 24px;
    font-size: 20px;
  }

  .notification-content {
    flex: 1;
    min-width: 0;
  }

  .notification-title {
    font-size: 14px;
    font-weight: 500;
    margin-bottom: 4px;
  }

  .notification-meta {
    font-size: 12px;
    color: var(--text-muted);
  }

  .notification-actions {
    flex-shrink: 0;
  }

  .mark-read-btn {
    padding: 4px 8px;
    font-size: 12px;
    border: 1px solid var(--border);
    background: transparent;
    cursor: pointer;
  }

  .mark-read-btn:hover {
    background: var(--bg);
  }
</style>
```

### 3.6 Watch Button Component (`ui/components/WatchButton.astro`)

```astro
---
interface Props {
  repoId: number;
  isWatching: boolean;
  watchCount: number;
}

const { repoId, isWatching, watchCount } = Astro.props;
---

<div class="watch-button-container">
  <button
    class="watch-btn"
    data-repo-id={repoId}
    data-watching={isWatching}
  >
    <span class="icon">{isWatching ? '👁' : '👁‍🗨'}</span>
    <span class="text">{isWatching ? 'Unwatch' : 'Watch'}</span>
    <span class="count">{watchCount}</span>
  </button>
</div>

<script>
  document.querySelectorAll('.watch-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const repoId = btn.getAttribute('data-repo-id');
      const isWatching = btn.getAttribute('data-watching') === 'true';

      // Extract owner and repo name from current URL
      const pathParts = window.location.pathname.split('/');
      const owner = pathParts[1];
      const repo = pathParts[2];

      const response = await fetch(`/api/repos/${owner}/${repo}/watch`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ watch: !isWatching })
      });

      if (response.ok) {
        window.location.reload();
      }
    });
  });
</script>

<style>
  .watch-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border: 1px solid var(--border);
    background: var(--bg-secondary);
    cursor: pointer;
    font-size: 14px;
  }

  .watch-btn:hover {
    background: var(--bg);
  }

  .count {
    padding: 2px 6px;
    background: var(--bg);
    border-radius: 10px;
    font-size: 12px;
  }
</style>
```

---

## 4. Integration Points

### 4.1 Trigger Activity Actions

Integrate `notifyWatchers()` into existing endpoints:

**When creating an issue** (`server/routes/issues.ts`):
```typescript
import { notifyWatchers, ActionType } from "../services/activity";
import { createOrUpdateIssueNotification } from "../services/notifications";

// After creating issue
await notifyWatchers({
  actUserId: currentUserId,
  opType: ActionType.CreateIssue,
  repoId: repository.id,
  content: `${issue.issue_number}|${issue.title}`,
});

// Create notifications
await createOrUpdateIssueNotification(issue.id, null, currentUserId);
```

**When commenting on an issue**:
```typescript
await notifyWatchers({
  actUserId: currentUserId,
  opType: ActionType.CommentIssue,
  repoId: repository.id,
  commentId: comment.id,
  content: `${issue.issue_number}|${comment.body.substring(0, 200)}`,
});

await createOrUpdateIssueNotification(issue.id, comment.id, currentUserId);
```

**When closing/reopening an issue**:
```typescript
await notifyWatchers({
  actUserId: currentUserId,
  opType: isClosed ? ActionType.CloseIssue : ActionType.ReopenIssue,
  repoId: repository.id,
  content: `${issue.issue_number}|`,
});
```

### 4.2 Update Header Component

Add notification count badge to header:

```astro
---
interface Props {
  unreadCount?: number;
}

const { unreadCount = 0 } = Astro.props;
---

<header>
  <!-- ... existing header content ... -->
  <nav>
    <a href="/dashboard">Dashboard</a>
    <a href="/notifications">
      Notifications
      {unreadCount > 0 && <span class="badge">{unreadCount}</span>}
    </a>
  </nav>
</header>

<style>
  .badge {
    display: inline-block;
    min-width: 18px;
    padding: 2px 6px;
    background: var(--primary);
    color: white;
    border-radius: 10px;
    font-size: 12px;
    font-weight: bold;
    text-align: center;
  }
</style>
```

---

## 5. Implementation Checklist

### Phase 1: Database & Backend (Week 1)
- [ ] Add `actions` table to `db/schema.sql`
- [ ] Add `notifications` table
- [ ] Add `watches` table
- [ ] Add `issue_watches` table
- [ ] Add `num_watches` column to `repositories`
- [ ] Run database migration
- [ ] Create `server/services/activity.ts`
  - [ ] Implement `notifyWatchers()`
  - [ ] Implement `getFeeds()`
  - [ ] Implement `getUserHeatmapData()`
- [ ] Create `server/services/notifications.ts`
  - [ ] Implement `createOrUpdateIssueNotification()`
  - [ ] Implement `getNotifications()`
  - [ ] Implement `setNotificationStatus()`
  - [ ] Implement `markAllAsRead()`
  - [ ] Implement `getUnreadCount()`
- [ ] Create `server/services/watch.ts`
  - [ ] Implement `watchRepo()`
  - [ ] Implement `isWatching()`
  - [ ] Implement `getWatchers()`
  - [ ] Implement `watchIssue()`
- [ ] Create API routes in `server/routes/activity.ts`
  - [ ] GET `/api/feeds/:username?`
  - [ ] GET `/api/heatmap/:username`
  - [ ] GET `/api/notifications`
  - [ ] GET `/api/notifications/count`
  - [ ] POST `/api/notifications/:id/status`
  - [ ] POST `/api/notifications/mark-all-read`
  - [ ] POST `/api/repos/:owner/:repo/watch`
  - [ ] GET `/api/repos/:owner/:repo/watch`
  - [ ] POST `/api/issues/:id/watch`

### Phase 2: Frontend UI (Week 2)
- [ ] Create `ui/pages/dashboard.astro`
- [ ] Create `ui/components/ActivityFeed.astro`
- [ ] Update `ui/pages/[user]/index.astro` with heatmap
- [ ] Create `ui/components/ContributionGraph.astro`
- [ ] Create `ui/pages/notifications.astro`
- [ ] Create `ui/components/WatchButton.astro`
- [ ] Update `ui/components/Header.astro` with notification badge
- [ ] Add notification count API call to header

### Phase 3: Integration (Week 3)
- [ ] Integrate activity tracking into issue creation
- [ ] Integrate activity tracking into issue comments
- [ ] Integrate activity tracking into issue close/reopen
- [ ] Integrate notification creation for new issues
- [ ] Integrate notification creation for comments
- [ ] Add watch button to repository pages
- [ ] Add subscribe/unsubscribe button to issue pages
- [ ] Test notification flow end-to-end
- [ ] Test activity feed rendering
- [ ] Test contribution graph rendering

### Phase 4: Polish & Optimization (Week 4)
- [ ] Add proper icons for different action types
- [ ] Implement real-time notification updates (polling or WebSocket)
- [ ] Add notification preferences page
- [ ] Add email notification support (optional)
- [ ] Optimize database queries with proper indexes
- [ ] Add pagination to activity feeds
- [ ] Add filters to activity feeds (by type, repo, date)
- [ ] Add search to notifications
- [ ] Implement notification grouping (e.g., "5 new comments on issue #123")
- [ ] Add tests for activity and notification services

---

## 6. Testing Strategy

### 6.1 Unit Tests

Test activity service:
```typescript
import { test, expect } from "bun:test";
import { notifyWatchers, ActionType } from "./activity";

test("notifyWatchers creates actions for watchers", async () => {
  // Setup: Create repo with watchers
  // Execute: Create action
  await notifyWatchers({
    actUserId: 1,
    opType: ActionType.CreateIssue,
    repoId: 1,
    content: "1|Test Issue",
  });

  // Verify: Check actions were created
  const actions = await db.sql`SELECT * FROM actions WHERE repo_id = 1`;
  expect(actions.length).toBeGreaterThan(0);
});
```

### 6.2 Integration Tests

Test notification flow:
```typescript
test("creating issue generates notification for watchers", async () => {
  // Create a watcher
  await watchRepo(2, 1, true);

  // Create an issue
  const response = await fetch("/api/repos/user/repo/issues", {
    method: "POST",
    body: JSON.stringify({ title: "Test", body: "Body" }),
  });

  // Check notification was created
  const notifications = await getNotifications(2, NotificationStatus.Unread);
  expect(notifications.length).toBe(1);
});
```

### 6.3 Manual Testing Checklist

- [ ] Create issue and verify activity appears in feed
- [ ] Comment on issue and verify notification sent to watchers
- [ ] Watch/unwatch repository
- [ ] Subscribe/unsubscribe from issue
- [ ] Mark notification as read/unread
- [ ] Mark all notifications as read
- [ ] View contribution heatmap
- [ ] Click on heatmap cell and see tooltip
- [ ] View activity feed on dashboard
- [ ] View user profile activity feed
- [ ] View repository activity feed

---

## 7. Reference Code from Gitea

### Key Gitea Files Referenced

1. **Action Model**: `gitea/models/activities/action.go`
   - ActionType enum (27 types)
   - Action struct with user, repo, comment relations
   - Complex indexing strategy for performance

2. **Notification Model**: `gitea/models/activities/notification.go`
   - NotificationStatus and NotificationSource enums
   - Notification struct with issue/PR/commit support
   - `CreateOrUpdateIssueNotifications` logic

3. **Watch Model**: `gitea/models/repo/watch.go`
   - WatchMode enum (None, Normal, Dont, Auto)
   - Watch struct with user-repo unique constraint
   - Auto-watch on changes feature

4. **Feed Service**: `gitea/services/feed/feed.go`
   - `NotifyWatchers` creates batch actions
   - Permission checking per watcher
   - Handles organization repos specially

5. **Notification Router**: `gitea/routers/web/user/notification.go`
   - Pagination and filtering
   - Mark read/unread endpoints
   - Subscriptions view

6. **Heatmap**: `gitea/models/activities/user_heatmap.go`
   - Groups actions by 15-minute intervals
   - Supports different SQL dialects
   - Returns last 366 days

---

## 8. TypeScript Type Definitions

Create `server/types/activity.ts`:

```typescript
export enum ActionType {
  CreateRepo = 1,
  RenameRepo = 2,
  StarRepo = 3,
  WatchRepo = 4,
  CommitRepo = 5,
  CreateIssue = 6,
  CreatePullRequest = 7,
  TransferRepo = 8,
  PushTag = 9,
  CommentIssue = 10,
  MergePullRequest = 11,
  CloseIssue = 12,
  ReopenIssue = 13,
  ClosePullRequest = 14,
  ReopenPullRequest = 15,
  DeleteTag = 16,
  DeleteBranch = 17,
  PublishRelease = 24,
  AutoMergePullRequest = 27,
}

export enum NotificationStatus {
  Unread = 1,
  Read = 2,
  Pinned = 3,
}

export enum NotificationSource {
  Issue = 1,
  PullRequest = 2,
  Commit = 3,
  Repository = 4,
}

export enum WatchMode {
  None = 0,
  Normal = 1,
  Dont = 2,
  Auto = 3,
}

export interface Action {
  id: number;
  user_id: number;
  act_user_id: number;
  op_type: ActionType;
  repo_id: number;
  comment_id?: number;
  is_deleted: boolean;
  is_private: boolean;
  ref_name?: string;
  content?: string;
  created_at: Date;
}

export interface Notification {
  id: number;
  user_id: number;
  repo_id: number;
  status: NotificationStatus;
  source: NotificationSource;
  issue_id?: number;
  comment_id?: number;
  commit_id?: string;
  updated_by: number;
  created_at: Date;
  updated_at: Date;
}

export interface Watch {
  id: number;
  user_id: number;
  repo_id: number;
  mode: WatchMode;
  created_at: Date;
  updated_at: Date;
}

export interface HeatmapData {
  timestamp: Date;
  contributions: number;
}
```

---

## 9. Security Considerations

1. **Permission Checks**: Always verify user has access to private repos before showing activity
2. **Privacy Settings**: Respect user's "keep activity private" setting (add to users table)
3. **Rate Limiting**: Limit notification creation to prevent spam
4. **SQL Injection**: Use parameterized queries (already using tagged templates)
5. **XSS Prevention**: Sanitize user content in activity feed
6. **Authorization**: Verify user owns notification before marking read/unread

---

## 10. Performance Optimizations

1. **Indexes**: Critical indexes already defined in schema
2. **Batch Inserts**: Use batch inserts when creating actions for multiple watchers
3. **Caching**: Cache unread count in user session
4. **Pagination**: Always paginate activity feeds and notifications
5. **Denormalization**: Store frequently accessed data (usernames, repo names) in action records
6. **Background Jobs**: Move activity/notification creation to background queue for high-traffic repos

---

## Summary

This implementation provides a complete activity tracking and notification system similar to GitHub/Gitea, including:

- **Activity Feeds**: Track 15+ action types across repositories
- **Notifications**: In-app notifications for issues, PRs, and comments
- **Watch System**: Repository and issue-level watching
- **Contribution Graph**: GitHub-style heatmap showing user activity
- **Dashboard**: Personalized activity feed for logged-in users
- **Real-time Updates**: Notification badges and counts

The system is designed to be performant with proper indexing, scalable with pagination, and extensible for future action types. All code follows Plue's tech stack: Bun runtime, Hono API, Astro frontend, and PostgreSQL database.
