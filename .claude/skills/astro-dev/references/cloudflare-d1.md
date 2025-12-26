# Cloudflare D1 with Astro

## Overview

D1 is Cloudflare's serverless SQL database built on SQLite. Perfect for Astro applications deployed to Cloudflare Workers.

## Setup

### 1. Create Database

```bash
# Create a new D1 database
npx wrangler d1 create my-database

# Output will include:
# database_id = "xxxx-xxxx-xxxx-xxxx"
```

### 2. Configure wrangler.jsonc

```jsonc
{
  "name": "my-astro-app",
  "main": "./dist/_worker.js",
  "compatibility_date": "2024-10-01",
  "assets": {
    "directory": "./dist"
  },
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "my-database",
      "database_id": "xxxx-xxxx-xxxx-xxxx"
    }
  ]
}
```

### 3. Create Schema

**db/schema.sql:**
```sql
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  published BOOLEAN DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_published ON posts(published);
```

### 4. Run Migrations

```bash
# Local database
npx wrangler d1 execute my-database --local --file=db/schema.sql

# Remote database
npx wrangler d1 execute my-database --remote --file=db/schema.sql
```

## Using D1 in Astro

### In Pages (.astro)

```astro
---
// src/pages/posts.astro
const { env } = Astro.locals.runtime;

const { results: posts } = await env.DB.prepare(
  'SELECT * FROM posts WHERE published = ? ORDER BY created_at DESC'
).bind(true).all();
---

<h1>Blog Posts</h1>
<ul>
  {posts.map(post => (
    <li>
      <a href={`/posts/${post.id}`}>{post.title}</a>
    </li>
  ))}
</ul>
```

### In API Routes

```typescript
// src/pages/api/posts.ts
import type { APIRoute } from 'astro';

export const GET: APIRoute = async ({ locals }) => {
  const { env } = locals.runtime;
  
  const { results } = await env.DB.prepare(
    'SELECT id, title, created_at FROM posts WHERE published = ?'
  ).bind(true).all();
  
  return new Response(JSON.stringify(results), {
    headers: { 'Content-Type': 'application/json' },
  });
};

export const POST: APIRoute = async ({ request, locals }) => {
  const { env } = locals.runtime;
  const { title, content, user_id } = await request.json();
  
  const result = await env.DB.prepare(
    'INSERT INTO posts (title, content, user_id) VALUES (?, ?, ?) RETURNING id'
  ).bind(title, content, user_id).first();
  
  return new Response(JSON.stringify(result), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
};
```

## Query Patterns

### Basic Queries

```typescript
const { env } = Astro.locals.runtime;

// SELECT (single row)
const user = await env.DB.prepare(
  'SELECT * FROM users WHERE id = ?'
).bind(userId).first();

// SELECT (all rows)
const { results } = await env.DB.prepare(
  'SELECT * FROM posts WHERE user_id = ?'
).bind(userId).all();

// INSERT
await env.DB.prepare(
  'INSERT INTO users (email, name) VALUES (?, ?)'
).bind(email, name).run();

// UPDATE
await env.DB.prepare(
  'UPDATE users SET name = ? WHERE id = ?'
).bind(newName, userId).run();

// DELETE
await env.DB.prepare(
  'DELETE FROM posts WHERE id = ?'
).bind(postId).run();
```

### Transactions

```typescript
// Batch multiple statements
await env.DB.batch([
  env.DB.prepare('UPDATE users SET credits = credits - ? WHERE id = ?').bind(10, userId),
  env.DB.prepare('INSERT INTO transactions (user_id, amount) VALUES (?, ?)').bind(userId, -10),
  env.DB.prepare('UPDATE products SET stock = stock - 1 WHERE id = ?').bind(productId),
]);
```

### Pagination

```typescript
const page = 1;
const perPage = 20;
const offset = (page - 1) * perPage;

const { results } = await env.DB.prepare(
  'SELECT * FROM posts ORDER BY created_at DESC LIMIT ? OFFSET ?'
).bind(perPage, offset).all();
```

## Drizzle ORM Integration

Drizzle provides type-safe database access for D1.

### Installation

```bash
npm install drizzle-orm
npm install -D drizzle-kit
```

### Schema Definition

**db/schema.ts:**
```typescript
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

export const users = sqliteTable('users', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  createdAt: integer('created_at', { mode: 'timestamp' }).$defaultFn(() => new Date()),
});

export const posts = sqliteTable('posts', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  userId: integer('user_id').notNull().references(() => users.id),
  title: text('title').notNull(),
  content: text('content').notNull(),
  published: integer('published', { mode: 'boolean' }).default(false),
  createdAt: integer('created_at', { mode: 'timestamp' }).$defaultFn(() => new Date()),
});
```

### Drizzle Config

**drizzle.config.ts:**
```typescript
import type { Config } from 'drizzle-kit';

export default {
  schema: './db/schema.ts',
  out: './db/migrations',
  driver: 'd1',
  dbCredentials: {
    wranglerConfigPath: 'wrangler.jsonc',
    dbName: 'my-database',
  },
} satisfies Config;
```

### Usage with Drizzle

```typescript
// src/lib/db.ts
import { drizzle } from 'drizzle-orm/d1';
import * as schema from '../../db/schema';

export function createDb(d1: D1Database) {
  return drizzle(d1, { schema });
}
```

```astro
---
// src/pages/users.astro
import { eq } from 'drizzle-orm';
import { createDb } from '../lib/db';
import { users } from '../../db/schema';

const { env } = Astro.locals.runtime;
const db = createDb(env.DB);

const allUsers = await db.select().from(users);
---

<ul>
  {allUsers.map(user => (
    <li>{user.name} - {user.email}</li>
  ))}
</ul>
```

### Migrations with Drizzle

```bash
# Generate migration
npx drizzle-kit generate:sqlite

# Apply migration locally
npx wrangler d1 execute my-database --local --file=db/migrations/0001_*.sql

# Apply migration remotely
npx wrangler d1 execute my-database --remote --file=db/migrations/0001_*.sql
```

## Local Development

### Configure Local Database

D1 automatically creates a local SQLite database when using `--local`:

```bash
# Execute queries locally
npx wrangler d1 execute my-database --local --command "SELECT * FROM users"

# Run SQL file locally
npx wrangler d1 execute my-database --local --file=query.sql
```

### Local Database Location

Local D1 databases are stored in `.wrangler/state/v3/d1/`.

## TypeScript Types

**src/env.d.ts:**
```typescript
/// <reference types="@cloudflare/workers-types" />

interface Env {
  DB: D1Database;
}
```

With Drizzle:
```typescript
import type * as schema from '../db/schema';
import type { drizzle } from 'drizzle-orm/d1';

type DrizzleDB = ReturnType<typeof drizzle<typeof schema>>;
```

## Best Practices

### 1. Use Prepared Statements

Always use parameterized queries to prevent SQL injection:

```typescript
// ❌ BAD - SQL injection risk
await env.DB.prepare(`SELECT * FROM users WHERE email = '${email}'`).all();

// ✅ GOOD - Safe parameterized query
await env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).all();
```

### 2. Index Common Queries

```sql
CREATE INDEX idx_posts_user_published ON posts(user_id, published);
CREATE INDEX idx_users_email ON users(email);
```

### 3. Batch Operations

Use transactions for multiple related operations:

```typescript
await env.DB.batch([
  env.DB.prepare('INSERT INTO posts (title, content, user_id) VALUES (?, ?, ?)').bind(title1, content1, userId),
  env.DB.prepare('INSERT INTO posts (title, content, user_id) VALUES (?, ?, ?)').bind(title2, content2, userId),
]);
```

### 4. Handle Errors

```typescript
try {
  const result = await env.DB.prepare(
    'INSERT INTO users (email, name) VALUES (?, ?)'
  ).bind(email, name).run();
} catch (error) {
  if (error.message.includes('UNIQUE constraint')) {
    return new Response('Email already exists', { status: 409 });
  }
  throw error;
}
```

### 5. Use Drizzle for Complex Apps

For complex schemas and queries, Drizzle provides better type safety and DX.

## Common Patterns

### User Authentication

```typescript
// Register
const hashedPassword = await hashPassword(password);
await env.DB.prepare(
  'INSERT INTO users (email, password, name) VALUES (?, ?, ?)'
).bind(email, hashedPassword, name).run();

// Login
const user = await env.DB.prepare(
  'SELECT * FROM users WHERE email = ?'
).bind(email).first();

if (user && await verifyPassword(password, user.password)) {
  // Generate JWT token
}
```

### Pagination with Count

```typescript
// Get total count
const { count } = await env.DB.prepare(
  'SELECT COUNT(*) as count FROM posts WHERE published = ?'
).bind(true).first();

// Get page
const { results } = await env.DB.prepare(
  'SELECT * FROM posts WHERE published = ? LIMIT ? OFFSET ?'
).bind(true, perPage, offset).all();

return {
  posts: results,
  total: count,
  pages: Math.ceil(count / perPage),
};
```

### Search

```typescript
const searchTerm = `%${query}%`;
const { results } = await env.DB.prepare(
  'SELECT * FROM posts WHERE title LIKE ? OR content LIKE ?'
).bind(searchTerm, searchTerm).all();
```

## Limitations

- Max 10 MB database size (free tier)
- Max 25 million rows read per day (free tier)
- Max 50 million rows written per day (free tier)
- SQLite feature subset (no ATTACH, custom functions limited)

## Resources

- [Cloudflare D1 Docs](https://developers.cloudflare.com/d1/)
- [D1 SQL Reference](https://developers.cloudflare.com/d1/platform/sql/)
- [Drizzle ORM Docs](https://orm.drizzle.team/)
- [D1 Limits](https://developers.cloudflare.com/d1/platform/limits/)

## Troubleshooting

**Issue: Database not found**
- Verify `database_id` in `wrangler.jsonc`
- Run `npx wrangler d1 list` to see available databases

**Issue: Schema changes not reflecting**
- Make sure you ran migrations on correct environment (--local or --remote)
- Check migration SQL for errors

**Issue: Query timeouts**
- Add indexes to frequently queried columns
- Optimize complex queries
- Consider pagination for large result sets
