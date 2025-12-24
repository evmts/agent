# Fix Database Foreign Key Reference Error

## Priority: BLOCKER | Database

## Problem

The `runner_pool` table references a non-existent table:

`db/schema.sql:974`
```sql
claimed_by_task_id INTEGER REFERENCES workflow_tasks(id) ON DELETE SET NULL
```

The `workflow_tasks` table doesn't exist - the workflow system uses `workflow_steps` instead.

This is a **schema creation blocker** - the database cannot be initialized.

## Task

1. **Verify the issue:**
   ```sql
   -- Check if workflow_tasks exists
   SELECT table_name FROM information_schema.tables
   WHERE table_name = 'workflow_tasks';

   -- Check what workflow-related tables exist
   SELECT table_name FROM information_schema.tables
   WHERE table_name LIKE 'workflow%';
   ```

2. **Analyze intended behavior:**
   - Read `runner_pool` table definition to understand purpose
   - Determine if `claimed_by_task_id` should reference `workflow_steps.id`
   - Check if there's code expecting `workflow_tasks` table

3. **Fix the schema:**

   **Option A: Reference workflow_steps (likely correct)**
   ```sql
   -- db/schema.sql:974
   claimed_by_task_id INTEGER REFERENCES workflow_steps(id) ON DELETE SET NULL
   ```

   **Option B: Remove the foreign key (if unused)**
   ```sql
   claimed_by_task_id INTEGER  -- No FK constraint
   ```

   **Option C: Create missing table (if needed)**
   ```sql
   CREATE TABLE workflow_tasks (
       id SERIAL PRIMARY KEY,
       -- Define appropriate columns
   );
   ```

4. **Create migration:**
   ```sql
   -- db/migrations/007_fix_runner_pool_fk.sql

   -- Remove broken FK
   ALTER TABLE runner_pool
   DROP CONSTRAINT IF EXISTS runner_pool_claimed_by_task_id_fkey;

   -- Add corrected FK
   ALTER TABLE runner_pool
   ADD CONSTRAINT runner_pool_claimed_by_task_id_fkey
   FOREIGN KEY (claimed_by_task_id) REFERENCES workflow_steps(id) ON DELETE SET NULL;
   ```

5. **Update DAO if needed:**
   - Check `db/daos/workflows.zig` for any `workflow_tasks` references
   - Update queries to use correct table name

6. **Test the fix:**
   - Run schema from scratch: `psql < db/schema.sql`
   - Verify no errors
   - Test runner claiming workflow steps

## Acceptance Criteria

- [ ] Schema can be created from scratch without errors
- [ ] FK references an existing table
- [ ] Migration is reversible
- [ ] All workflow tests pass
- [ ] Runner pool functionality works
