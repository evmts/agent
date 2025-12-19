-- Branch Management Migration
-- Stores branch metadata for pagination and tracking
CREATE TABLE IF NOT EXISTS branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  commit_id VARCHAR(40) NOT NULL,
  commit_message TEXT,
  pusher_id INTEGER REFERENCES users(id),
  is_deleted BOOLEAN DEFAULT false,
  deleted_by_id INTEGER REFERENCES users(id),
  deleted_at TIMESTAMP,
  commit_time TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_branches_repo ON branches(repository_id);
CREATE INDEX IF NOT EXISTS idx_branches_deleted ON branches(is_deleted);

-- Branch protection rules
CREATE TABLE IF NOT EXISTS protected_branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  rule_name VARCHAR(255) NOT NULL, -- Branch name or glob pattern
  priority BIGINT NOT NULL DEFAULT 0,

  -- Push protection
  can_push BOOLEAN NOT NULL DEFAULT false,
  enable_whitelist BOOLEAN DEFAULT false,
  whitelist_user_ids JSONB DEFAULT '[]',
  whitelist_team_ids JSONB DEFAULT '[]',
  whitelist_deploy_keys BOOLEAN DEFAULT false,

  -- Force push protection
  can_force_push BOOLEAN NOT NULL DEFAULT false,
  enable_force_push_allowlist BOOLEAN DEFAULT false,
  force_push_allowlist_user_ids JSONB DEFAULT '[]',
  force_push_allowlist_team_ids JSONB DEFAULT '[]',
  force_push_allowlist_deploy_keys BOOLEAN DEFAULT false,

  -- Merge protection
  enable_merge_whitelist BOOLEAN DEFAULT false,
  merge_whitelist_user_ids JSONB DEFAULT '[]',
  merge_whitelist_team_ids JSONB DEFAULT '[]',

  -- Status checks
  enable_status_check BOOLEAN DEFAULT false,
  status_check_contexts JSONB DEFAULT '[]',

  -- Approvals
  enable_approvals_whitelist BOOLEAN DEFAULT false,
  approvals_whitelist_user_ids JSONB DEFAULT '[]',
  approvals_whitelist_team_ids JSONB DEFAULT '[]',
  required_approvals BIGINT DEFAULT 0,
  block_on_rejected_reviews BOOLEAN DEFAULT false,
  block_on_official_review_requests BOOLEAN DEFAULT false,
  block_on_outdated_branch BOOLEAN DEFAULT false,
  dismiss_stale_approvals BOOLEAN DEFAULT false,
  ignore_stale_approvals BOOLEAN DEFAULT false,

  -- Advanced
  require_signed_commits BOOLEAN DEFAULT false,
  protected_file_patterns TEXT,
  unprotected_file_patterns TEXT,
  block_admin_merge_override BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, rule_name)
);

CREATE INDEX IF NOT EXISTS idx_protected_branches_repo ON protected_branches(repository_id);
CREATE INDEX IF NOT EXISTS idx_protected_branches_priority ON protected_branches(repository_id, priority DESC);

-- Track branch renames for redirects
CREATE TABLE IF NOT EXISTS renamed_branches (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  from_name VARCHAR(255) NOT NULL,
  to_name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_renamed_branches_repo ON renamed_branches(repository_id);
CREATE INDEX IF NOT EXISTS idx_renamed_branches_from ON renamed_branches(repository_id, from_name);