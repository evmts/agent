---
name: database
description: Plue database schema, migrations, and table structure. Use when working with the database, writing queries, or understanding data models.
---

# Plue Database

## Running Migrations

```bash
bun run db:migrate     # Run migrations
```

## Schema Location

- Schema file: `db/schema.sql`
- Migration script: `db/migrate.ts`

## Tables

### GitHub-like Entities
- `users` - User accounts
- `repositories` - Git repositories
- `issues` - Issue tracking
- `comments` - Issue/PR comments

### Agent State Persistence
- `sessions` - Agent conversation sessions
- `messages` - Chat messages within sessions
- `snapshots` - State snapshots for rollback

### Agent Task Tracking
- `subtasks` - Task breakdown for agent work
- `file_trackers` - Files being tracked/modified

## Connection

```bash
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric
```

ElectricSQL provides real-time sync on top of PostgreSQL.
