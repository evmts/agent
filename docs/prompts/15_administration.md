# Basic Administration Implementation Prompt

## Overview

Add basic admin functionality to Plue - a simple admin dashboard for managing users and viewing system stats. Keep it minimal.

## Scope

**In scope:**
- Admin role on users
- Admin dashboard with basic stats
- User list with suspend/delete
- Basic system settings (site name, registration on/off)

**Out of scope:**
- Repository management (admins can use normal UI)
- Organization management
- Cron jobs
- System notices
- Database maintenance
- Audit logs
- Complex settings

## Database Schema

Add to `/Users/williamcory/plue/db/schema.sql`:

```sql
-- Add admin flag to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_users_admin ON users(is_admin) WHERE is_admin = true;

-- Simple system settings
CREATE TABLE IF NOT EXISTS system_settings (
  key VARCHAR(255) PRIMARY KEY,
  value TEXT
);

INSERT INTO system_settings (key, value) VALUES
  ('site_name', 'Plue'),
  ('allow_registration', 'true')
ON CONFLICT (key) DO NOTHING;
```

## Admin Middleware

Create `/Users/williamcory/plue/server/middleware/admin.ts`:

```typescript
import { Context, Next } from 'hono';

export async function requireAdmin(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  if (!user.is_admin) {
    return c.json({ error: 'Admin access required' }, 403);
  }

  await next();
}
```

## API Routes

Create `/Users/williamcory/plue/server/routes/admin.ts`:

```typescript
import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { requireAdmin } from '../middleware/admin';
import { sql } from '../../db';

const app = new Hono();

// All routes require admin
app.use('*', requireAdmin);

// Dashboard stats
app.get('/stats', async (c) => {
  const [[userCount], [repoCount], [issueCount]] = await Promise.all([
    sql`SELECT COUNT(*) as count FROM users`,
    sql`SELECT COUNT(*) as count FROM repositories`,
    sql`SELECT COUNT(*) as count FROM issues`,
  ]);

  return c.json({
    users: Number(userCount.count),
    repositories: Number(repoCount.count),
    issues: Number(issueCount.count),
  });
});

// List users
app.get('/users', async (c) => {
  const page = Number(c.req.query('page') || 1);
  const limit = 50;
  const offset = (page - 1) * limit;

  const users = await sql`
    SELECT id, username, display_name, is_admin, is_active, created_at
    FROM users
    ORDER BY created_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  const [{ count }] = await sql`SELECT COUNT(*) as count FROM users`;

  return c.json({
    users,
    total: Number(count),
    page,
    pages: Math.ceil(Number(count) / limit),
  });
});

// Update user
const UpdateUserSchema = z.object({
  is_admin: z.boolean().optional(),
  is_active: z.boolean().optional(),
});

app.patch('/users/:id', zValidator('json', UpdateUserSchema), async (c) => {
  const id = Number(c.req.param('id'));
  const updates = c.req.valid('json');

  // Don't allow deactivating yourself
  const currentUser = c.get('user');
  if (id === currentUser.id && updates.is_active === false) {
    return c.json({ error: 'Cannot deactivate yourself' }, 400);
  }

  const setClauses = [];
  const values = [];

  if (updates.is_admin !== undefined) {
    setClauses.push('is_admin = $' + (values.length + 1));
    values.push(updates.is_admin);
  }
  if (updates.is_active !== undefined) {
    setClauses.push('is_active = $' + (values.length + 1));
    values.push(updates.is_active);
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'No updates provided' }, 400);
  }

  await sql`
    UPDATE users SET ${sql.unsafe(setClauses.join(', '))}
    WHERE id = ${id}
  `;

  return c.json({ success: true });
});

// Delete user
app.delete('/users/:id', async (c) => {
  const id = Number(c.req.param('id'));
  const currentUser = c.get('user');

  if (id === currentUser.id) {
    return c.json({ error: 'Cannot delete yourself' }, 400);
  }

  await sql`DELETE FROM users WHERE id = ${id}`;

  return c.json({ success: true });
});

// Get settings
app.get('/settings', async (c) => {
  const settings = await sql`SELECT key, value FROM system_settings`;

  const result: Record<string, string> = {};
  for (const { key, value } of settings) {
    result[key] = value;
  }

  return c.json(result);
});

// Update settings
app.patch('/settings', async (c) => {
  const body = await c.req.json();

  for (const [key, value] of Object.entries(body)) {
    await sql`
      INSERT INTO system_settings (key, value) VALUES (${key}, ${String(value)})
      ON CONFLICT (key) DO UPDATE SET value = ${String(value)}
    `;
  }

  return c.json({ success: true });
});

export default app;
```

## UI Pages

### Admin Layout

Create `/Users/williamcory/plue/ui/layouts/AdminLayout.astro`:

```astro
---
import Layout from './Layout.astro';

interface Props {
  title: string;
}

const { title } = Astro.props;

// Check if user is admin (implement based on your auth)
const user = Astro.locals.user;
if (!user?.is_admin) {
  return Astro.redirect('/');
}
---

<Layout title={title}>
  <div class="admin-layout">
    <nav class="admin-nav">
      <a href="/admin">Dashboard</a>
      <a href="/admin/users">Users</a>
      <a href="/admin/settings">Settings</a>
    </nav>
    <main class="admin-content">
      <slot />
    </main>
  </div>
</Layout>

<style>
.admin-layout {
  display: flex;
  min-height: 100vh;
}

.admin-nav {
  width: 200px;
  background: #000;
  padding: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.admin-nav a {
  color: #fff;
  text-decoration: none;
  padding: 0.5rem;
}

.admin-nav a:hover {
  background: #333;
}

.admin-content {
  flex: 1;
  padding: 2rem;
}
</style>
```

### Dashboard

Create `/Users/williamcory/plue/ui/pages/admin/index.astro`:

```astro
---
import AdminLayout from '../../layouts/AdminLayout.astro';

const res = await fetch(`${Astro.url.origin}/api/admin/stats`, {
  headers: { Cookie: Astro.request.headers.get('Cookie') || '' }
});
const stats = await res.json();
---

<AdminLayout title="Admin Dashboard">
  <h1>Dashboard</h1>

  <div class="stats-grid">
    <div class="stat-card">
      <div class="stat-value">{stats.users}</div>
      <div class="stat-label">Users</div>
    </div>
    <div class="stat-card">
      <div class="stat-value">{stats.repositories}</div>
      <div class="stat-label">Repositories</div>
    </div>
    <div class="stat-card">
      <div class="stat-value">{stats.issues}</div>
      <div class="stat-label">Issues</div>
    </div>
  </div>
</AdminLayout>

<style>
.stats-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1rem;
  margin-top: 2rem;
}

.stat-card {
  border: 2px solid #000;
  padding: 2rem;
  text-align: center;
}

.stat-value {
  font-size: 3rem;
  font-weight: bold;
}

.stat-label {
  font-size: 1rem;
  color: #666;
}
</style>
```

### Users Page

Create `/Users/williamcory/plue/ui/pages/admin/users.astro`:

```astro
---
import AdminLayout from '../../layouts/AdminLayout.astro';

const page = Number(Astro.url.searchParams.get('page') || 1);

const res = await fetch(`${Astro.url.origin}/api/admin/users?page=${page}`, {
  headers: { Cookie: Astro.request.headers.get('Cookie') || '' }
});
const { users, total, pages } = await res.json();
---

<AdminLayout title="Manage Users">
  <h1>Users ({total})</h1>

  <table class="users-table">
    <thead>
      <tr>
        <th>Username</th>
        <th>Admin</th>
        <th>Active</th>
        <th>Created</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      {users.map(user => (
        <tr data-user-id={user.id}>
          <td>{user.username}</td>
          <td>{user.is_admin ? 'Yes' : 'No'}</td>
          <td>{user.is_active ? 'Yes' : 'No'}</td>
          <td>{new Date(user.created_at).toLocaleDateString()}</td>
          <td>
            <button onclick={`toggleAdmin(${user.id}, ${!user.is_admin})`}>
              {user.is_admin ? 'Remove Admin' : 'Make Admin'}
            </button>
            <button onclick={`toggleActive(${user.id}, ${!user.is_active})`}>
              {user.is_active ? 'Suspend' : 'Activate'}
            </button>
            <button onclick={`deleteUser(${user.id})`} class="danger">
              Delete
            </button>
          </td>
        </tr>
      ))}
    </tbody>
  </table>

  {pages > 1 && (
    <div class="pagination">
      {Array.from({ length: pages }, (_, i) => i + 1).map(p => (
        <a href={`?page=${p}`} class={p === page ? 'active' : ''}>{p}</a>
      ))}
    </div>
  )}
</AdminLayout>

<script>
async function toggleAdmin(id: number, value: boolean) {
  await fetch(`/api/admin/users/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ is_admin: value }),
  });
  location.reload();
}

async function toggleActive(id: number, value: boolean) {
  await fetch(`/api/admin/users/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ is_active: value }),
  });
  location.reload();
}

async function deleteUser(id: number) {
  if (!confirm('Delete this user? This cannot be undone.')) return;
  await fetch(`/api/admin/users/${id}`, { method: 'DELETE' });
  location.reload();
}
</script>

<style>
.users-table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 1rem;
}

.users-table th,
.users-table td {
  border: 1px solid #000;
  padding: 0.75rem;
  text-align: left;
}

.users-table th {
  background: #000;
  color: #fff;
}

button {
  margin-right: 0.5rem;
  padding: 0.25rem 0.5rem;
  cursor: pointer;
}

button.danger {
  background: #fff;
  border: 1px solid red;
  color: red;
}

.pagination {
  margin-top: 1rem;
  display: flex;
  gap: 0.5rem;
}

.pagination a {
  padding: 0.5rem 1rem;
  border: 1px solid #000;
  text-decoration: none;
  color: #000;
}

.pagination a.active {
  background: #000;
  color: #fff;
}
</style>
```

### Settings Page

Create `/Users/williamcory/plue/ui/pages/admin/settings.astro`:

```astro
---
import AdminLayout from '../../layouts/AdminLayout.astro';

const res = await fetch(`${Astro.url.origin}/api/admin/settings`, {
  headers: { Cookie: Astro.request.headers.get('Cookie') || '' }
});
const settings = await res.json();
---

<AdminLayout title="Settings">
  <h1>Settings</h1>

  <form id="settings-form">
    <div class="field">
      <label for="site_name">Site Name</label>
      <input type="text" id="site_name" name="site_name" value={settings.site_name || 'Plue'} />
    </div>

    <div class="field">
      <label>
        <input
          type="checkbox"
          name="allow_registration"
          checked={settings.allow_registration === 'true'}
        />
        Allow Registration
      </label>
    </div>

    <button type="submit">Save Settings</button>
  </form>
</AdminLayout>

<script>
document.getElementById('settings-form')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = e.target as HTMLFormElement;
  const data = {
    site_name: (form.elements.namedItem('site_name') as HTMLInputElement).value,
    allow_registration: (form.elements.namedItem('allow_registration') as HTMLInputElement).checked ? 'true' : 'false',
  };

  await fetch('/api/admin/settings', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });

  alert('Settings saved');
});
</script>

<style>
form {
  max-width: 400px;
}

.field {
  margin-bottom: 1rem;
}

label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: bold;
}

input[type="text"] {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid #000;
}

button {
  padding: 0.75rem 1.5rem;
  background: #000;
  color: #fff;
  border: none;
  cursor: pointer;
}
</style>
```

## Implementation Checklist

### Phase 1: Database
- [ ] Add is_admin, is_active columns to users
- [ ] Create system_settings table
- [ ] Set first user as admin

### Phase 2: Backend
- [ ] Create admin middleware
- [ ] Create admin routes
- [ ] Add routes to server/index.ts

### Phase 3: Frontend
- [ ] Create AdminLayout
- [ ] Create dashboard page
- [ ] Create users page
- [ ] Create settings page

### Phase 4: Testing
- [ ] Test admin-only access
- [ ] Test user suspend/delete
- [ ] Test settings save/load
