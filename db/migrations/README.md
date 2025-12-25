# Database Migrations

Incremental SQL migrations for schema evolution. Applied sequentially to modify the database structure.

## Migration Files

| Migration | Purpose |
|-----------|---------|
| `005_fix_workflow_config_format.sql` | Fix workflow configuration JSON format |
| `006_workflow_tables.sql` | Add workflow execution system tables |
| `007_atomic_issue_numbers.sql` | Fix race condition in issue number assignment |
| `008_convert_timestamp_to_timestamptz.sql` | Convert TIMESTAMP to TIMESTAMPTZ (timezone-aware) |
| `008_convert_timestamp_to_timestamptz_rollback.sql` | Rollback for migration 008 |

## Naming Convention

```
<number>_<description>.sql
<number>_<description>_rollback.sql  (optional)
```

- **Number**: Sequential (005, 006, 007, 008)
- **Description**: Snake_case summary of change
- **Rollback**: Optional reverse migration for safety-critical changes

## Application

Migrations are applied manually via `psql`:

```bash
psql plue < db/migrations/006_workflow_tables.sql
```

For production, use a migration tool like `migrate` or `flyway`.

## Migration Structure

Each migration should be:

1. **Idempotent**: Safe to run multiple times
   ```sql
   CREATE TABLE IF NOT EXISTS table_name (...);
   ALTER TABLE table_name ADD COLUMN IF NOT EXISTS col_name TYPE;
   ```

2. **Atomic**: Wrapped in transaction (where applicable)
   ```sql
   BEGIN;
   -- migration steps
   COMMIT;
   ```

3. **Indexed**: Create indexes for new columns
   ```sql
   CREATE INDEX IF NOT EXISTS idx_name ON table(column);
   ```

4. **Documented**: Include comments explaining why
   ```sql
   -- Fix race condition in issue number assignment
   -- Add atomic counter to repositories table
   ```

## Example Migration

```sql
-- 007_atomic_issue_numbers.sql
-- Fix race condition in issue number assignment

-- Add atomic counter
ALTER TABLE repositories
ADD COLUMN IF NOT EXISTS next_issue_number INTEGER NOT NULL DEFAULT 1;

-- Initialize from existing data
UPDATE repositories r
SET next_issue_number = COALESCE((
  SELECT MAX(issue_number) + 1
  FROM issues
  WHERE repository_id = r.id
), 1);

-- Create atomic function
CREATE OR REPLACE FUNCTION get_next_issue_number(repo_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  next_num INTEGER;
BEGIN
  UPDATE repositories
  SET next_issue_number = next_issue_number + 1
  WHERE id = repo_id
  RETURNING next_issue_number - 1 INTO next_num;

  RETURN next_num;
END;
$$;

-- Add index
CREATE INDEX IF NOT EXISTS idx_repositories_next_issue_number
ON repositories(id, next_issue_number);
```

## Rollback Migrations

For high-risk changes, provide a rollback:

```sql
-- 008_convert_timestamp_to_timestamptz_rollback.sql
-- Rollback: Convert TIMESTAMPTZ back to TIMESTAMP

ALTER TABLE workflow_definitions
ALTER COLUMN parsed_at TYPE TIMESTAMP;

ALTER TABLE workflow_runs
ALTER COLUMN started_at TYPE TIMESTAMP,
ALTER COLUMN completed_at TYPE TIMESTAMP,
ALTER COLUMN created_at TYPE TIMESTAMP;
```

## Testing Migrations

1. Apply to local dev database
2. Verify schema changes
3. Run tests: `zig build test`
4. Check DAO compatibility
5. Apply to staging environment
6. Apply to production

## Schema Sync

After migrations, update `schema.sql` to reflect the current state:

```bash
pg_dump plue --schema-only > db/schema.sql
```

This keeps `schema.sql` as the single source of truth for fresh installations.

## Common Patterns

### Add Column
```sql
ALTER TABLE table_name
ADD COLUMN IF NOT EXISTS column_name TYPE DEFAULT value;
```

### Add Index
```sql
CREATE INDEX IF NOT EXISTS idx_name
ON table_name(column_name);
```

### Add Function
```sql
CREATE OR REPLACE FUNCTION function_name(args)
RETURNS return_type
LANGUAGE plpgsql
AS $$
BEGIN
  -- function body
END;
$$;
```

### Modify Column Type
```sql
ALTER TABLE table_name
ALTER COLUMN column_name TYPE new_type;
```

### Add Constraint
```sql
ALTER TABLE table_name
ADD CONSTRAINT constraint_name constraint_definition;
```

## Migration History

Migrations reflect the evolution of Plue's architecture:

- **005-006**: Added workflow execution system for AI agents
- **007**: Fixed concurrency bug in issue numbering
- **008**: Timezone consistency across all timestamp columns

See `../schema.sql` for the complete current schema.
