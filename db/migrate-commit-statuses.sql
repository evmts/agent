-- Commit Statuses Migration
-- Adds commit_statuses table for tracking CI/workflow check results

-- Commit statuses (CI/workflow check results)
CREATE TABLE IF NOT EXISTS commit_statuses (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  commit_sha VARCHAR(64) NOT NULL,

  -- Context identifies the check (e.g., "ci", "test", "lint")
  context VARCHAR(255) NOT NULL,

  -- State: pending, success, failure, error
  state VARCHAR(20) NOT NULL CHECK (state IN ('pending', 'success', 'failure', 'error')),

  -- Human-readable description
  description TEXT,

  -- URL to workflow run or external check
  target_url TEXT,

  -- Link to workflow run if created by internal workflow
  workflow_run_id INTEGER REFERENCES workflow_runs(id) ON DELETE SET NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(repository_id, commit_sha, context)
);

CREATE INDEX IF NOT EXISTS idx_commit_statuses_repo ON commit_statuses(repository_id);
CREATE INDEX IF NOT EXISTS idx_commit_statuses_commit ON commit_statuses(commit_sha);
CREATE INDEX IF NOT EXISTS idx_commit_statuses_repo_commit ON commit_statuses(repository_id, commit_sha);
CREATE INDEX IF NOT EXISTS idx_commit_statuses_workflow_run ON commit_statuses(workflow_run_id);
