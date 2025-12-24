# Fix Timezone Consistency in Database

## Priority: HIGH | Data Integrity

## Problem

All timestamp columns use `TIMESTAMP` instead of `TIMESTAMP WITH TIME ZONE`:

`db/schema.sql` examples:
- Line 25: `created_at TIMESTAMP DEFAULT NOW()`
- Line 59: `expires_at TIMESTAMP NOT NULL`
- Line 131: `due_date TIMESTAMP`

This causes:
- Ambiguity during DST transitions
- Inconsistency across distributed deployments
- Unreliable audit trails

## Task

1. **Audit all timestamp columns:**
   ```bash
   grep -n "TIMESTAMP" db/schema.sql
   ```
   List every column that needs migration.

2. **Create migration file:**
   ```sql
   -- db/migrations/008_fix_timestamps.sql

   -- Users table
   ALTER TABLE users
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

   -- Auth sessions
   ALTER TABLE auth_sessions
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN expires_at TYPE TIMESTAMPTZ USING expires_at AT TIME ZONE 'UTC';

   -- Access tokens
   ALTER TABLE access_tokens
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN expires_at TYPE TIMESTAMPTZ USING expires_at AT TIME ZONE 'UTC',
     ALTER COLUMN last_used_at TYPE TIMESTAMPTZ USING last_used_at AT TIME ZONE 'UTC';

   -- Repositories
   ALTER TABLE repositories
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

   -- Issues
   ALTER TABLE issues
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC',
     ALTER COLUMN closed_at TYPE TIMESTAMPTZ USING closed_at AT TIME ZONE 'UTC',
     ALTER COLUMN due_date TYPE TIMESTAMPTZ USING due_date AT TIME ZONE 'UTC';

   -- Workflow tables
   ALTER TABLE workflow_runs
     ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
     ALTER COLUMN started_at TYPE TIMESTAMPTZ USING started_at AT TIME ZONE 'UTC',
     ALTER COLUMN completed_at TYPE TIMESTAMPTZ USING completed_at AT TIME ZONE 'UTC';

   -- Continue for all tables...
   ```

3. **Update schema.sql for new deployments:**
   Change all `TIMESTAMP` to `TIMESTAMPTZ`:
   ```sql
   -- Before
   created_at TIMESTAMP DEFAULT NOW()

   -- After
   created_at TIMESTAMPTZ DEFAULT NOW()
   ```

4. **Update DAO queries:**
   Ensure Zig code handles timezone-aware timestamps:
   ```zig
   // Check timestamp parsing in db/root.zig
   // Verify EXTRACT(EPOCH) still works with TIMESTAMPTZ
   ```

5. **Update JavaScript/TypeScript code:**
   ```typescript
   // Ensure Date objects are properly created from TIMESTAMPTZ
   const createdAt = new Date(row.created_at); // Should work
   ```

6. **Set database timezone:**
   ```sql
   -- In PostgreSQL config or at connection time
   SET timezone = 'UTC';
   ```

7. **Add timezone to docker-compose:**
   ```yaml
   # infra/docker/docker-compose.yaml
   postgres:
     environment:
       - TZ=UTC
       - PGTZ=UTC
   ```

8. **Create rollback migration:**
   ```sql
   -- db/migrations/008_fix_timestamps_rollback.sql
   ALTER TABLE users
     ALTER COLUMN created_at TYPE TIMESTAMP USING created_at AT TIME ZONE 'UTC';
   -- etc...
   ```

9. **Test the migration:**
   - Create timestamps in different timezones
   - Migrate to TIMESTAMPTZ
   - Verify values are correct
   - Test DST edge cases (March/November transitions)

## Acceptance Criteria

- [ ] All TIMESTAMP columns migrated to TIMESTAMPTZ
- [ ] Schema updated for new deployments
- [ ] Migration is reversible
- [ ] All existing data preserved correctly
- [ ] Application code handles new type correctly
- [ ] Tests verify timezone handling
