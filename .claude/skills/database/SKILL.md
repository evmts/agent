---
name: database
description: Plue database schema, migrations, and table structure. Use when working with the database, writing queries, or understanding data models.
---

# Plue Database

## Schema Location

- Schema file: `db/schema.sql`

## Tables

### GitHub-like Entities
- `users` - User accounts
- `repositories` - Git repositories
- `issues` - Issue tracking
- `comments` - Issue/PR comments
- `labels`, `milestones` - Issue organization

### Agent State Persistence
- `sessions` - Agent conversation sessions
- `messages` - Chat messages within sessions
- `workflow_tasks` - Agent task tracking

## Connection

```bash
DATABASE_URL=postgresql://postgres:password@localhost:5432/plue
```

## Local Development

```bash
docker compose up -d postgres    # Start PostgreSQL
zig build run                    # Server connects automatically
```
