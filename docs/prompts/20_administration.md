# Administration Feature Implementation

## Overview

Implement a comprehensive administration panel for Plue that allows admin users to manage the platform, including user management, repository oversight, system settings, database maintenance, cron job monitoring, and system notices. This transforms Plue from a basic platform to a fully manageable system with proper administrative controls.

**Scope:**
- Admin dashboard with system statistics and health monitoring
- User management (list, create, edit, delete, suspend)
- Repository management (list, transfer, delete)
- Organization management (list, view)
- System settings (site configuration, registration policies)
- Database maintenance operations
- Cron job/scheduled task management
- System notices and announcements
- Admin middleware and authorization
- Statistics and monitoring pages

**Out of scope (future features):**
- Advanced authentication sources (LDAP, OAuth providers)
- Email template management
- Backup/restore functionality
- Advanced monitoring/metrics dashboards
- Webhook management
- Package registry management

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server with middleware
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL with `postgres` client
- **Validation**: Zod v4

## Database Schema Changes

### 1. Add admin role to users table

**File**: `/Users/williamcory/plue/db/schema.sql`

Update the existing `users` table to include admin flag:

```sql
-- Update users table to add admin role
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_restricted BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS prohibit_login BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS max_repo_creation INTEGER DEFAULT -1; -- -1 means unlimited
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

-- Create index for admin lookups
CREATE INDEX IF NOT EXISTS idx_users_admin ON users(is_admin) WHERE is_admin = true;
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active);
```

### 2. Create system_settings table

**File**: `/Users/williamcory/plue/db/schema.sql`

```sql
-- System settings (key-value store for admin configuration)
CREATE TABLE IF NOT EXISTS system_settings (
  id SERIAL PRIMARY KEY,
  setting_key VARCHAR(255) UNIQUE NOT NULL,
  setting_value TEXT,
  version INTEGER DEFAULT 1, -- for optimistic locking
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_settings_key ON system_settings(setting_key);

-- Insert default settings
INSERT INTO system_settings (setting_key, setting_value) VALUES
  ('site_name', 'Plue'),
  ('site_description', 'A brutalist GitHub clone'),
  ('disable_registration', 'false'),
  ('require_signin_view', 'false'),
  ('enable_captcha', 'false'),
  ('default_keep_email_private', 'false'),
  ('default_allow_create_organization', 'true'),
  ('default_enable_dependencies', 'true')
ON CONFLICT (setting_key) DO NOTHING;
```

### 3. Create notices table

**File**: `/Users/williamcory/plue/db/schema.sql`

```sql
-- System notices (admin announcements and error logs)
CREATE TABLE IF NOT EXISTS notices (
  id SERIAL PRIMARY KEY,
  type VARCHAR(50) DEFAULT 'info' CHECK (type IN ('info', 'warning', 'error', 'repository', 'task')),
  description TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notices_created ON notices(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notices_type ON notices(type);
```

### 4. Create cron_tasks table

**File**: `/Users/williamcory/plue/db/schema.sql`

```sql
-- Cron tasks (scheduled background jobs)
CREATE TABLE IF NOT EXISTS cron_tasks (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) UNIQUE NOT NULL,
  schedule VARCHAR(255) NOT NULL, -- cron expression
  enabled BOOLEAN DEFAULT true,
  last_run_at TIMESTAMP,
  next_run_at TIMESTAMP,
  last_status VARCHAR(50), -- 'success', 'failed', 'running'
  last_message TEXT,
  run_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cron_tasks_enabled ON cron_tasks(enabled);
CREATE INDEX IF NOT EXISTS idx_cron_tasks_next_run ON cron_tasks(next_run_at);

-- Insert default cron tasks
INSERT INTO cron_tasks (name, schedule, enabled) VALUES
  ('cleanup_old_sessions', '0 2 * * *', true),
  ('cleanup_old_snapshots', '0 3 * * *', true),
  ('cleanup_old_notices', '0 4 * * SUN', true),
  ('update_repository_stats', '*/15 * * * *', true),
  ('check_repo_stats', '0 * * * *', true)
ON CONFLICT (name) DO NOTHING;
```

### 5. Create admin_operations table (audit log)

**File**: `/Users/williamcory/plue/db/schema.sql`

```sql
-- Admin operations audit log
CREATE TABLE IF NOT EXISTS admin_operations (
  id SERIAL PRIMARY KEY,
  admin_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  operation VARCHAR(100) NOT NULL, -- 'user_create', 'user_delete', 'repo_delete', etc.
  target_type VARCHAR(50), -- 'user', 'repository', 'setting', etc.
  target_id INTEGER,
  details JSONB,
  ip_address INET,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_ops_admin ON admin_operations(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_ops_created ON admin_operations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_ops_operation ON admin_operations(operation);
```

## Backend Implementation

### 1. Admin middleware

**File**: `/Users/williamcory/plue/server/middleware/admin.ts`

```typescript
import { Context, Next } from "hono";
import sql from "../../db/client";

/**
 * Middleware to require admin privileges
 */
export async function requireAdmin(c: Context, next: Next) {
  // Get user from context (assumes auth middleware has run)
  const userId = c.get("userId");

  if (!userId) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  // Check if user is admin
  const [user] = await sql`
    SELECT is_admin, is_active, prohibit_login
    FROM users
    WHERE id = ${userId}
  `;

  if (!user || !user.is_admin || !user.is_active || user.prohibit_login) {
    return c.json({ error: "Forbidden - Admin access required" }, 403);
  }

  // Store admin user in context
  c.set("isAdmin", true);
  await next();
}

/**
 * Log admin operation for audit trail
 */
export async function logAdminOperation(
  adminId: number,
  operation: string,
  targetType: string | null,
  targetId: number | null,
  details: Record<string, any> | null,
  ipAddress: string | null
) {
  await sql`
    INSERT INTO admin_operations (admin_id, operation, target_type, target_id, details, ip_address)
    VALUES (${adminId}, ${operation}, ${targetType}, ${targetId}, ${JSON.stringify(details)}, ${ipAddress})
  `;
}
```

### 2. System settings service

**File**: `/Users/williamcory/plue/server/services/settings.ts`

```typescript
import sql from "../../db/client";
import { z } from "zod";

const SettingSchema = z.object({
  id: z.number(),
  setting_key: z.string(),
  setting_value: z.string(),
  version: z.number(),
  created_at: z.date(),
  updated_at: z.date(),
});

export type Setting = z.infer<typeof SettingSchema>;

/**
 * Get a system setting by key
 */
export async function getSetting(key: string): Promise<string | null> {
  const [setting] = await sql<Setting[]>`
    SELECT * FROM system_settings WHERE setting_key = ${key}
  `;
  return setting?.setting_value || null;
}

/**
 * Get all system settings as key-value object
 */
export async function getAllSettings(): Promise<Record<string, string>> {
  const settings = await sql<Setting[]>`
    SELECT setting_key, setting_value FROM system_settings
  `;

  return settings.reduce((acc, setting) => {
    acc[setting.setting_key] = setting.setting_value;
    return acc;
  }, {} as Record<string, string>);
}

/**
 * Update a system setting
 */
export async function updateSetting(key: string, value: string): Promise<void> {
  await sql`
    INSERT INTO system_settings (setting_key, setting_value)
    VALUES (${key}, ${value})
    ON CONFLICT (setting_key)
    DO UPDATE SET
      setting_value = ${value},
      version = system_settings.version + 1,
      updated_at = NOW()
  `;
}

/**
 * Update multiple settings at once
 */
export async function updateSettings(settings: Record<string, string>): Promise<void> {
  await sql.begin(async (sql) => {
    for (const [key, value] of Object.entries(settings)) {
      await sql`
        INSERT INTO system_settings (setting_key, setting_value)
        VALUES (${key}, ${value})
        ON CONFLICT (setting_key)
        DO UPDATE SET
          setting_value = ${value},
          version = system_settings.version + 1,
          updated_at = NOW()
      `;
    }
  });
}
```

### 3. System notices service

**File**: `/Users/williamcory/plue/server/services/notices.ts`

```typescript
import sql from "../../db/client";
import { z } from "zod";

const NoticeSchema = z.object({
  id: z.number(),
  type: z.enum(['info', 'warning', 'error', 'repository', 'task']),
  description: z.string(),
  created_at: z.date(),
});

export type Notice = z.infer<typeof NoticeSchema>;

/**
 * Create a system notice
 */
export async function createNotice(
  type: Notice['type'],
  description: string
): Promise<Notice> {
  const [notice] = await sql<Notice[]>`
    INSERT INTO notices (type, description)
    VALUES (${type}, ${description})
    RETURNING *
  `;
  return notice;
}

/**
 * Get paginated notices
 */
export async function getNotices(
  page = 1,
  pageSize = 50
): Promise<{ notices: Notice[]; total: number }> {
  const offset = (page - 1) * pageSize;

  const notices = await sql<Notice[]>`
    SELECT * FROM notices
    ORDER BY created_at DESC
    LIMIT ${pageSize} OFFSET ${offset}
  `;

  const [{ count }] = await sql<[{ count: number }]>`
    SELECT COUNT(*) as count FROM notices
  `;

  return { notices, total: Number(count) };
}

/**
 * Delete notices by IDs
 */
export async function deleteNotices(ids: number[]): Promise<void> {
  await sql`
    DELETE FROM notices WHERE id = ANY(${ids})
  `;
}

/**
 * Delete all notices
 */
export async function deleteAllNotices(): Promise<void> {
  await sql`DELETE FROM notices`;
}

/**
 * Delete old notices (older than specified days)
 */
export async function deleteOldNotices(days: number): Promise<void> {
  await sql`
    DELETE FROM notices
    WHERE created_at < NOW() - INTERVAL '${days} days'
  `;
}
```

### 4. Admin statistics service

**File**: `/Users/williamcory/plue/server/services/admin-stats.ts`

```typescript
import sql from "../../db/client";

export interface SystemStats {
  totalUsers: number;
  activeUsers: number;
  adminUsers: number;
  totalRepos: number;
  publicRepos: number;
  privateRepos: number;
  totalIssues: number;
  openIssues: number;
  closedIssues: number;
  totalComments: number;
  totalSessions: number;
  activeSessions: number;
  systemUptime: string;
  bunVersion: string;
  postgresVersion: string;
}

/**
 * Get comprehensive system statistics
 */
export async function getSystemStats(): Promise<SystemStats> {
  // User stats
  const [userStats] = await sql<[{
    total: number;
    active: number;
    admin: number;
  }]>`
    SELECT
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE is_active = true) as active,
      COUNT(*) FILTER (WHERE is_admin = true) as admin
    FROM users
  `;

  // Repository stats
  const [repoStats] = await sql<[{
    total: number;
    public: number;
    private: number;
  }]>`
    SELECT
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE is_public = true) as public,
      COUNT(*) FILTER (WHERE is_public = false) as private
    FROM repositories
  `;

  // Issue stats
  const [issueStats] = await sql<[{
    total: number;
    open: number;
    closed: number;
  }]>`
    SELECT
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE state = 'open') as open,
      COUNT(*) FILTER (WHERE state = 'closed') as closed
    FROM issues
  `;

  // Comment count
  const [{ count: commentCount }] = await sql<[{ count: number }]>`
    SELECT COUNT(*) as count FROM comments
  `;

  // Session stats
  const [sessionStats] = await sql<[{
    total: number;
    active: number;
  }]>`
    SELECT
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE time_archived IS NULL) as active
    FROM sessions
  `;

  // Postgres version
  const [{ version: postgresVersion }] = await sql<[{ version: string }]>`
    SELECT version() as version
  `;

  return {
    totalUsers: Number(userStats.total),
    activeUsers: Number(userStats.active),
    adminUsers: Number(userStats.admin),
    totalRepos: Number(repoStats.total),
    publicRepos: Number(repoStats.public),
    privateRepos: Number(repoStats.private),
    totalIssues: Number(issueStats.total),
    openIssues: Number(issueStats.open),
    closedIssues: Number(issueStats.closed),
    totalComments: Number(commentCount),
    totalSessions: Number(sessionStats.total),
    activeSessions: Number(sessionStats.active),
    systemUptime: process.uptime().toString(),
    bunVersion: Bun.version,
    postgresVersion: postgresVersion.split(' ')[1] || 'unknown',
  };
}

/**
 * Get runtime memory statistics
 */
export async function getMemoryStats() {
  const memUsage = process.memoryUsage();

  return {
    heapUsed: (memUsage.heapUsed / 1024 / 1024).toFixed(2) + ' MB',
    heapTotal: (memUsage.heapTotal / 1024 / 1024).toFixed(2) + ' MB',
    rss: (memUsage.rss / 1024 / 1024).toFixed(2) + ' MB',
    external: (memUsage.external / 1024 / 1024).toFixed(2) + ' MB',
  };
}
```

### 5. Admin routes

**File**: `/Users/williamcory/plue/server/routes/admin.ts`

```typescript
import { Hono } from "hono";
import { requireAdmin, logAdminOperation } from "../middleware/admin";
import { getSystemStats, getMemoryStats } from "../services/admin-stats";
import {
  getAllSettings,
  updateSettings
} from "../services/settings";
import {
  getNotices,
  deleteNotices,
  deleteAllNotices
} from "../services/notices";
import sql from "../../db/client";
import { z } from "zod";

const admin = new Hono();

// Apply admin middleware to all routes
admin.use("*", requireAdmin);

// ============================================================================
// Dashboard
// ============================================================================

/**
 * GET /api/admin/dashboard
 * Get admin dashboard statistics
 */
admin.get("/dashboard", async (c) => {
  const stats = await getSystemStats();
  const memory = await getMemoryStats();

  return c.json({
    stats,
    memory,
  });
});

// ============================================================================
// User Management
// ============================================================================

const UserSearchSchema = z.object({
  page: z.coerce.number().min(1).default(1),
  pageSize: z.coerce.number().min(1).max(100).default(50),
  search: z.string().optional(),
  isAdmin: z.enum(['true', 'false', 'all']).default('all'),
  isActive: z.enum(['true', 'false', 'all']).default('all'),
});

/**
 * GET /api/admin/users
 * List all users with filtering and pagination
 */
admin.get("/users", async (c) => {
  const query = UserSearchSchema.parse(c.req.query());
  const offset = (query.page - 1) * query.pageSize;

  let conditions = [];
  let params: any[] = [];

  if (query.search) {
    conditions.push(`(username ILIKE $${params.length + 1} OR display_name ILIKE $${params.length + 1})`);
    params.push(`%${query.search}%`);
  }

  if (query.isAdmin !== 'all') {
    conditions.push(`is_admin = $${params.length + 1}`);
    params.push(query.isAdmin === 'true');
  }

  if (query.isActive !== 'all') {
    conditions.push(`is_active = $${params.length + 1}`);
    params.push(query.isActive === 'true');
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const users = await sql.unsafe(`
    SELECT
      id, username, display_name, bio, is_admin, is_active,
      is_restricted, prohibit_login, created_at, last_login_at
    FROM users
    ${whereClause}
    ORDER BY created_at DESC
    LIMIT ${query.pageSize} OFFSET ${offset}
  `, params);

  const [{ count }] = await sql.unsafe<[{ count: number }]>(`
    SELECT COUNT(*) as count FROM users ${whereClause}
  `, params);

  return c.json({
    users,
    total: Number(count),
    page: query.page,
    pageSize: query.pageSize,
  });
});

const CreateUserSchema = z.object({
  username: z.string().min(1).max(255),
  display_name: z.string().max(255).optional(),
  bio: z.string().optional(),
  is_admin: z.boolean().default(false),
  is_active: z.boolean().default(true),
});

/**
 * POST /api/admin/users
 * Create a new user
 */
admin.post("/users", async (c) => {
  const data = CreateUserSchema.parse(await c.req.json());
  const adminId = c.get("userId");

  const [user] = await sql`
    INSERT INTO users (username, display_name, bio, is_admin, is_active)
    VALUES (${data.username}, ${data.display_name || null}, ${data.bio || null}, ${data.is_admin}, ${data.is_active})
    RETURNING id, username, display_name, bio, is_admin, is_active, created_at
  `;

  await logAdminOperation(
    adminId,
    "user_create",
    "user",
    user.id,
    { username: data.username },
    c.req.header("x-forwarded-for") || null
  );

  return c.json(user, 201);
});

const UpdateUserSchema = z.object({
  display_name: z.string().max(255).optional(),
  bio: z.string().optional(),
  is_admin: z.boolean().optional(),
  is_active: z.boolean().optional(),
  is_restricted: z.boolean().optional(),
  prohibit_login: z.boolean().optional(),
  max_repo_creation: z.number().optional(),
});

/**
 * PATCH /api/admin/users/:id
 * Update a user
 */
admin.patch("/users/:id", async (c) => {
  const userId = parseInt(c.req.param("id"));
  const data = UpdateUserSchema.parse(await c.req.json());
  const adminId = c.get("userId");

  // Prevent self-demotion
  if (userId === adminId && data.is_admin === false) {
    return c.json({ error: "Cannot remove your own admin privileges" }, 400);
  }

  const updates: string[] = [];
  const values: any[] = [];
  let paramIndex = 1;

  for (const [key, value] of Object.entries(data)) {
    if (value !== undefined) {
      updates.push(`${key} = $${paramIndex}`);
      values.push(value);
      paramIndex++;
    }
  }

  if (updates.length === 0) {
    return c.json({ error: "No fields to update" }, 400);
  }

  updates.push(`updated_at = NOW()`);
  values.push(userId);

  const [user] = await sql.unsafe(`
    UPDATE users
    SET ${updates.join(', ')}
    WHERE id = $${paramIndex}
    RETURNING id, username, display_name, bio, is_admin, is_active, is_restricted, prohibit_login, updated_at
  `, values);

  if (!user) {
    return c.json({ error: "User not found" }, 404);
  }

  await logAdminOperation(
    adminId,
    "user_update",
    "user",
    userId,
    data,
    c.req.header("x-forwarded-for") || null
  );

  return c.json(user);
});

/**
 * DELETE /api/admin/users/:id
 * Delete a user (soft delete by deactivating)
 */
admin.delete("/users/:id", async (c) => {
  const userId = parseInt(c.req.param("id"));
  const adminId = c.get("userId");

  // Prevent self-deletion
  if (userId === adminId) {
    return c.json({ error: "Cannot delete your own account" }, 400);
  }

  const [user] = await sql`
    UPDATE users
    SET is_active = false, prohibit_login = true, updated_at = NOW()
    WHERE id = ${userId}
    RETURNING id, username
  `;

  if (!user) {
    return c.json({ error: "User not found" }, 404);
  }

  await logAdminOperation(
    adminId,
    "user_delete",
    "user",
    userId,
    { username: user.username },
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true });
});

// ============================================================================
// Repository Management
// ============================================================================

/**
 * GET /api/admin/repositories
 * List all repositories
 */
admin.get("/repositories", async (c) => {
  const page = parseInt(c.req.query("page") || "1");
  const pageSize = parseInt(c.req.query("pageSize") || "50");
  const offset = (page - 1) * pageSize;

  const repos = await sql`
    SELECT
      r.id, r.name, r.description, r.is_public, r.created_at, r.updated_at,
      u.username as owner_username, u.id as owner_id
    FROM repositories r
    JOIN users u ON r.user_id = u.id
    ORDER BY r.created_at DESC
    LIMIT ${pageSize} OFFSET ${offset}
  `;

  const [{ count }] = await sql<[{ count: number }]>`
    SELECT COUNT(*) as count FROM repositories
  `;

  return c.json({
    repositories: repos,
    total: Number(count),
    page,
    pageSize,
  });
});

/**
 * DELETE /api/admin/repositories/:id
 * Delete a repository
 */
admin.delete("/repositories/:id", async (c) => {
  const repoId = parseInt(c.req.param("id"));
  const adminId = c.get("userId");

  const [repo] = await sql`
    SELECT id, name, user_id FROM repositories WHERE id = ${repoId}
  `;

  if (!repo) {
    return c.json({ error: "Repository not found" }, 404);
  }

  await sql`DELETE FROM repositories WHERE id = ${repoId}`;

  await logAdminOperation(
    adminId,
    "repository_delete",
    "repository",
    repoId,
    { name: repo.name, owner_id: repo.user_id },
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true });
});

// ============================================================================
// System Settings
// ============================================================================

/**
 * GET /api/admin/settings
 * Get all system settings
 */
admin.get("/settings", async (c) => {
  const settings = await getAllSettings();
  return c.json(settings);
});

const UpdateSettingsSchema = z.record(z.string());

/**
 * PATCH /api/admin/settings
 * Update system settings
 */
admin.patch("/settings", async (c) => {
  const settings = UpdateSettingsSchema.parse(await c.req.json());
  const adminId = c.get("userId");

  await updateSettings(settings);

  await logAdminOperation(
    adminId,
    "settings_update",
    "settings",
    null,
    settings,
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true });
});

// ============================================================================
// Notices
// ============================================================================

/**
 * GET /api/admin/notices
 * Get system notices
 */
admin.get("/notices", async (c) => {
  const page = parseInt(c.req.query("page") || "1");
  const pageSize = parseInt(c.req.query("pageSize") || "50");

  const { notices, total } = await getNotices(page, pageSize);

  return c.json({
    notices,
    total,
    page,
    pageSize,
  });
});

/**
 * DELETE /api/admin/notices
 * Delete notices by IDs or all notices
 */
admin.delete("/notices", async (c) => {
  const { ids, deleteAll } = await c.req.json();
  const adminId = c.get("userId");

  if (deleteAll) {
    await deleteAllNotices();
    await logAdminOperation(adminId, "notices_delete_all", "notices", null, null, null);
  } else if (ids && Array.isArray(ids)) {
    await deleteNotices(ids);
    await logAdminOperation(adminId, "notices_delete", "notices", null, { ids }, null);
  } else {
    return c.json({ error: "Must provide ids array or deleteAll=true" }, 400);
  }

  return c.json({ success: true });
});

// ============================================================================
// Cron Tasks
// ============================================================================

/**
 * GET /api/admin/cron
 * Get all cron tasks
 */
admin.get("/cron", async (c) => {
  const tasks = await sql`
    SELECT * FROM cron_tasks ORDER BY name
  `;

  return c.json(tasks);
});

/**
 * POST /api/admin/cron/:id/run
 * Manually trigger a cron task
 */
admin.post("/cron/:id/run", async (c) => {
  const taskId = parseInt(c.req.param("id"));
  const adminId = c.get("userId");

  const [task] = await sql`
    SELECT * FROM cron_tasks WHERE id = ${taskId}
  `;

  if (!task) {
    return c.json({ error: "Cron task not found" }, 404);
  }

  // TODO: Implement actual task execution based on task.name
  // For now, just log the execution attempt
  await sql`
    UPDATE cron_tasks
    SET last_run_at = NOW(), run_count = run_count + 1, last_status = 'success'
    WHERE id = ${taskId}
  `;

  await logAdminOperation(
    adminId,
    "cron_run",
    "cron_task",
    taskId,
    { task_name: task.name },
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true });
});

// ============================================================================
// Database Maintenance
// ============================================================================

/**
 * POST /api/admin/maintenance/vacuum
 * Run VACUUM on database
 */
admin.post("/maintenance/vacuum", async (c) => {
  const adminId = c.get("userId");

  // Note: VACUUM cannot run inside a transaction, so we use sql.unsafe
  await sql.unsafe("VACUUM ANALYZE");

  await logAdminOperation(
    adminId,
    "maintenance_vacuum",
    "database",
    null,
    null,
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true, message: "Database vacuum completed" });
});

/**
 * POST /api/admin/maintenance/cleanup
 * Run cleanup operations
 */
admin.post("/maintenance/cleanup", async (c) => {
  const adminId = c.get("userId");
  const { target } = await c.req.json();

  let message = "";

  switch (target) {
    case "old_sessions":
      // Delete sessions older than 90 days
      await sql`
        DELETE FROM sessions
        WHERE time_archived IS NOT NULL
        AND time_archived < EXTRACT(EPOCH FROM NOW() - INTERVAL '90 days') * 1000
      `;
      message = "Cleaned up old sessions";
      break;

    case "old_notices":
      // Delete notices older than 30 days
      await sql`
        DELETE FROM notices
        WHERE created_at < NOW() - INTERVAL '30 days'
      `;
      message = "Cleaned up old notices";
      break;

    default:
      return c.json({ error: "Invalid cleanup target" }, 400);
  }

  await logAdminOperation(
    adminId,
    "maintenance_cleanup",
    "database",
    null,
    { target },
    c.req.header("x-forwarded-for") || null
  );

  return c.json({ success: true, message });
});

export default admin;
```

### 6. Register admin routes

**File**: `/Users/williamcory/plue/server/index.ts`

Add admin routes to the main app:

```typescript
import admin from "./routes/admin";

// ... existing code ...

// Admin routes
app.route("/api/admin", admin);
```

## Frontend Implementation

### 1. Admin dashboard page

**File**: `/Users/williamcory/plue/ui/pages/admin/index.astro`

```astro
---
import Layout from "../../layouts/Layout.astro";

// Fetch admin stats
const response = await fetch("http://localhost:3000/api/admin/dashboard");
const { stats, memory } = await response.json();
---

<Layout title="Admin Dashboard">
  <div class="admin-container">
    <h1>Administration</h1>

    <nav class="admin-nav">
      <a href="/admin">Dashboard</a>
      <a href="/admin/users">Users</a>
      <a href="/admin/repositories">Repositories</a>
      <a href="/admin/settings">Settings</a>
      <a href="/admin/notices">Notices</a>
      <a href="/admin/cron">Cron Jobs</a>
      <a href="/admin/maintenance">Maintenance</a>
    </nav>

    <section class="stats-grid">
      <div class="stat-card">
        <h3>Users</h3>
        <div class="stat-value">{stats.totalUsers}</div>
        <div class="stat-detail">
          {stats.activeUsers} active, {stats.adminUsers} admins
        </div>
      </div>

      <div class="stat-card">
        <h3>Repositories</h3>
        <div class="stat-value">{stats.totalRepos}</div>
        <div class="stat-detail">
          {stats.publicRepos} public, {stats.privateRepos} private
        </div>
      </div>

      <div class="stat-card">
        <h3>Issues</h3>
        <div class="stat-value">{stats.totalIssues}</div>
        <div class="stat-detail">
          {stats.openIssues} open, {stats.closedIssues} closed
        </div>
      </div>

      <div class="stat-card">
        <h3>Sessions</h3>
        <div class="stat-value">{stats.totalSessions}</div>
        <div class="stat-detail">{stats.activeSessions} active</div>
      </div>
    </section>

    <section class="system-info">
      <h2>System Information</h2>
      <table>
        <tr>
          <td>Bun Version</td>
          <td>{stats.bunVersion}</td>
        </tr>
        <tr>
          <td>PostgreSQL Version</td>
          <td>{stats.postgresVersion}</td>
        </tr>
        <tr>
          <td>System Uptime</td>
          <td>{Math.floor(Number(stats.systemUptime) / 60)} minutes</td>
        </tr>
        <tr>
          <td>Memory (Heap Used)</td>
          <td>{memory.heapUsed}</td>
        </tr>
        <tr>
          <td>Memory (RSS)</td>
          <td>{memory.rss}</td>
        </tr>
      </table>
    </section>
  </div>
</Layout>

<style>
  .admin-container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
  }

  .admin-nav {
    display: flex;
    gap: 1rem;
    margin: 2rem 0;
    padding: 1rem;
    background: #000;
    border: 2px solid #fff;
  }

  .admin-nav a {
    color: #fff;
    text-decoration: none;
    padding: 0.5rem 1rem;
    border: 1px solid #fff;
  }

  .admin-nav a:hover {
    background: #fff;
    color: #000;
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1rem;
    margin: 2rem 0;
  }

  .stat-card {
    background: #000;
    color: #fff;
    padding: 1.5rem;
    border: 2px solid #fff;
  }

  .stat-card h3 {
    margin: 0 0 0.5rem 0;
    font-size: 0.875rem;
    text-transform: uppercase;
  }

  .stat-value {
    font-size: 2.5rem;
    font-weight: bold;
    margin: 0.5rem 0;
  }

  .stat-detail {
    font-size: 0.875rem;
    opacity: 0.8;
  }

  .system-info {
    margin: 2rem 0;
  }

  .system-info h2 {
    margin-bottom: 1rem;
  }

  .system-info table {
    width: 100%;
    border: 2px solid #000;
    border-collapse: collapse;
  }

  .system-info td {
    padding: 0.75rem;
    border: 1px solid #000;
  }

  .system-info tr td:first-child {
    font-weight: bold;
    width: 200px;
  }
</style>
```

### 2. User management page

**File**: `/Users/williamcory/plue/ui/pages/admin/users.astro`

```astro
---
import Layout from "../../layouts/Layout.astro";

const page = Astro.url.searchParams.get("page") || "1";
const search = Astro.url.searchParams.get("search") || "";

const response = await fetch(
  `http://localhost:3000/api/admin/users?page=${page}&search=${search}`
);
const { users, total, pageSize } = await response.json();
const totalPages = Math.ceil(total / pageSize);
---

<Layout title="User Management">
  <div class="admin-container">
    <h1>User Management</h1>

    <div class="toolbar">
      <form method="get" class="search-form">
        <input
          type="text"
          name="search"
          placeholder="Search users..."
          value={search}
        />
        <button type="submit">Search</button>
      </form>
      <a href="/admin/users/new" class="btn-primary">Create User</a>
    </div>

    <table class="user-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Username</th>
          <th>Display Name</th>
          <th>Admin</th>
          <th>Active</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {
          users.map((user: any) => (
            <tr>
              <td>{user.id}</td>
              <td>{user.username}</td>
              <td>{user.display_name || "-"}</td>
              <td>{user.is_admin ? "Yes" : "No"}</td>
              <td>{user.is_active ? "Yes" : "No"}</td>
              <td>{new Date(user.created_at).toLocaleDateString()}</td>
              <td>
                <a href={`/admin/users/${user.id}`}>Edit</a>
                <button class="delete-btn" data-user-id={user.id}>
                  Delete
                </button>
              </td>
            </tr>
          ))
        }
      </tbody>
    </table>

    <div class="pagination">
      {
        Number(page) > 1 && (
          <a href={`?page=${Number(page) - 1}&search=${search}`}>Previous</a>
        )
      }
      <span>
        Page {page} of {totalPages}
      </span>
      {
        Number(page) < totalPages && (
          <a href={`?page=${Number(page) + 1}&search=${search}`}>Next</a>
        )
      }
    </div>
  </div>
</Layout>

<script>
  document.querySelectorAll(".delete-btn").forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      const userId = (e.target as HTMLElement).dataset.userId;
      if (!confirm("Are you sure you want to delete this user?")) return;

      const res = await fetch(`/api/admin/users/${userId}`, {
        method: "DELETE",
      });

      if (res.ok) {
        window.location.reload();
      } else {
        alert("Failed to delete user");
      }
    });
  });
</script>

<style>
  .admin-container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 2rem;
  }

  .toolbar {
    display: flex;
    justify-content: space-between;
    margin: 2rem 0;
  }

  .search-form {
    display: flex;
    gap: 0.5rem;
  }

  .search-form input {
    padding: 0.5rem;
    border: 2px solid #000;
    min-width: 300px;
  }

  .btn-primary {
    padding: 0.5rem 1rem;
    background: #000;
    color: #fff;
    border: 2px solid #000;
    text-decoration: none;
    display: inline-block;
  }

  .btn-primary:hover {
    background: #fff;
    color: #000;
  }

  .user-table {
    width: 100%;
    border-collapse: collapse;
    border: 2px solid #000;
  }

  .user-table th,
  .user-table td {
    padding: 0.75rem;
    border: 1px solid #000;
    text-align: left;
  }

  .user-table th {
    background: #000;
    color: #fff;
    font-weight: bold;
  }

  .user-table tr:nth-child(even) {
    background: #f5f5f5;
  }

  .delete-btn {
    margin-left: 0.5rem;
    padding: 0.25rem 0.5rem;
    background: #fff;
    border: 1px solid #000;
    cursor: pointer;
  }

  .delete-btn:hover {
    background: #000;
    color: #fff;
  }

  .pagination {
    margin: 2rem 0;
    display: flex;
    gap: 1rem;
    justify-content: center;
    align-items: center;
  }

  .pagination a {
    padding: 0.5rem 1rem;
    border: 2px solid #000;
    text-decoration: none;
  }
</style>
```

### 3. System settings page

**File**: `/Users/williamcory/plue/ui/pages/admin/settings.astro`

```astro
---
import Layout from "../../layouts/Layout.astro";

const response = await fetch("http://localhost:3000/api/admin/settings");
const settings = await response.json();
---

<Layout title="System Settings">
  <div class="admin-container">
    <h1>System Settings</h1>

    <form id="settings-form" class="settings-form">
      <section>
        <h2>General Settings</h2>

        <div class="form-group">
          <label for="site_name">Site Name</label>
          <input
            type="text"
            id="site_name"
            name="site_name"
            value={settings.site_name}
          />
        </div>

        <div class="form-group">
          <label for="site_description">Site Description</label>
          <textarea id="site_description" name="site_description">
            {settings.site_description}
          </textarea>
        </div>
      </section>

      <section>
        <h2>Registration & Access</h2>

        <div class="form-group">
          <label>
            <input
              type="checkbox"
              name="disable_registration"
              checked={settings.disable_registration === "true"}
            />
            Disable Registration
          </label>
        </div>

        <div class="form-group">
          <label>
            <input
              type="checkbox"
              name="require_signin_view"
              checked={settings.require_signin_view === "true"}
            />
            Require Sign-in to View
          </label>
        </div>

        <div class="form-group">
          <label>
            <input
              type="checkbox"
              name="default_allow_create_organization"
              checked={settings.default_allow_create_organization === "true"}
            />
            Allow Users to Create Organizations
          </label>
        </div>
      </section>

      <button type="submit" class="btn-primary">Save Settings</button>
    </form>
  </div>
</Layout>

<script>
  const form = document.getElementById("settings-form") as HTMLFormElement;

  form.addEventListener("submit", async (e) => {
    e.preventDefault();

    const formData = new FormData(form);
    const settings: Record<string, string> = {};

    formData.forEach((value, key) => {
      settings[key] = value.toString();
    });

    // Handle checkboxes
    const checkboxes = form.querySelectorAll('input[type="checkbox"]');
    checkboxes.forEach((checkbox) => {
      const cb = checkbox as HTMLInputElement;
      settings[cb.name] = cb.checked.toString();
    });

    const res = await fetch("/api/admin/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(settings),
    });

    if (res.ok) {
      alert("Settings saved successfully");
    } else {
      alert("Failed to save settings");
    }
  });
</script>

<style>
  .admin-container {
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem;
  }

  .settings-form section {
    margin: 2rem 0;
    padding: 1.5rem;
    border: 2px solid #000;
  }

  .settings-form h2 {
    margin-top: 0;
    margin-bottom: 1.5rem;
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
  }

  .form-group textarea {
    min-height: 100px;
  }

  .btn-primary {
    padding: 0.75rem 2rem;
    background: #000;
    color: #fff;
    border: 2px solid #000;
    cursor: pointer;
    font-size: 1rem;
  }

  .btn-primary:hover {
    background: #fff;
    color: #000;
  }
</style>
```

## Reference Code from Gitea

The implementation above is based on the following Gitea files:

1. **Admin Dashboard**: `/Users/williamcory/plue/gitea/routers/web/admin/admin.go` (lines 136-146)
   - System statistics gathering
   - Runtime memory stats
   - Uptime tracking

2. **User Management**: `/Users/williamcory/plue/gitea/routers/web/admin/users.go`
   - User listing with filters (lines 46-82)
   - User creation (lines 106-214)
   - User editing (lines 334-482)
   - User deletion (lines 485-522)

3. **Repository Management**: `/Users/williamcory/plue/gitea/routers/web/admin/repos.go`
   - Repository listing (lines 29-39)
   - Repository deletion (lines 42-61)

4. **System Settings**: `/Users/williamcory/plue/gitea/models/system/setting.go`
   - Key-value settings storage
   - Versioning for optimistic locking
   - Batch updates

5. **Notices**: `/Users/williamcory/plue/gitea/models/system/notice.go`
   - Notice creation and types
   - Paginated retrieval
   - Cleanup operations

6. **Cron Tasks**: `/Users/williamcory/plue/gitea/models/admin/task.go`
   - Task tracking
   - Status updates
   - Execution history

## Implementation Checklist

### Database
- [ ] Add admin columns to users table
- [ ] Create system_settings table with default values
- [ ] Create notices table
- [ ] Create cron_tasks table with default tasks
- [ ] Create admin_operations audit log table
- [ ] Run migration script

### Backend Services
- [ ] Implement admin middleware (`requireAdmin`)
- [ ] Implement audit logging (`logAdminOperation`)
- [ ] Create settings service (get, update)
- [ ] Create notices service (create, list, delete)
- [ ] Create admin stats service (system stats, memory stats)
- [ ] Create admin routes handler

### API Endpoints
- [ ] GET /api/admin/dashboard
- [ ] GET /api/admin/users
- [ ] POST /api/admin/users
- [ ] PATCH /api/admin/users/:id
- [ ] DELETE /api/admin/users/:id
- [ ] GET /api/admin/repositories
- [ ] DELETE /api/admin/repositories/:id
- [ ] GET /api/admin/settings
- [ ] PATCH /api/admin/settings
- [ ] GET /api/admin/notices
- [ ] DELETE /api/admin/notices
- [ ] GET /api/admin/cron
- [ ] POST /api/admin/cron/:id/run
- [ ] POST /api/admin/maintenance/vacuum
- [ ] POST /api/admin/maintenance/cleanup

### Frontend Pages
- [ ] Admin dashboard (`/admin`)
- [ ] User management list (`/admin/users`)
- [ ] User edit form (`/admin/users/:id`)
- [ ] Repository list (`/admin/repositories`)
- [ ] System settings (`/admin/settings`)
- [ ] Notices list (`/admin/notices`)
- [ ] Cron jobs monitor (`/admin/cron`)
- [ ] Maintenance page (`/admin/maintenance`)

### Testing
- [ ] Test admin middleware with non-admin user
- [ ] Test admin middleware with admin user
- [ ] Test user CRUD operations
- [ ] Test repository deletion
- [ ] Test settings update
- [ ] Test notice creation and cleanup
- [ ] Test audit log creation
- [ ] Test pagination on all list endpoints
- [ ] Test database maintenance operations

### Documentation
- [ ] Document admin setup (creating first admin user)
- [ ] Document available system settings
- [ ] Document cron task system
- [ ] Document audit log usage
- [ ] Add admin user guide

## Notes

1. **First Admin User**: The first admin user should be created manually via SQL:
   ```sql
   UPDATE users SET is_admin = true WHERE username = 'your_username';
   ```

2. **Security**: Admin routes are protected by the `requireAdmin` middleware which checks:
   - User is authenticated
   - User has `is_admin = true`
   - User is active (`is_active = true`)
   - User is not prohibited from login

3. **Audit Trail**: All admin operations are logged in the `admin_operations` table with:
   - Admin user ID
   - Operation type
   - Target type and ID
   - Additional details (JSON)
   - IP address
   - Timestamp

4. **Soft Deletes**: Users are soft-deleted by setting `is_active = false` and `prohibit_login = true` rather than hard deletion to preserve data integrity.

5. **Cron Tasks**: The cron task system tracks scheduled jobs but doesn't implement the actual execution logic. Task execution should be implemented separately based on specific requirements.

6. **Brutalist UI**: All admin pages follow Plue's brutalist design with:
   - Black/white color scheme
   - Heavy borders (2px solid)
   - Monospace fonts for data
   - Simple grid layouts
   - No rounded corners or shadows
