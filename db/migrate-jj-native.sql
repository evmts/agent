-- JJ-Native Migration
-- Transforms Plue from git-centric to jj-native version control

-- =============================================================================
-- New Tables for jj Concepts
-- =============================================================================

-- Changes metadata (denormalized from jj for queries)
-- Change IDs are stable identifiers that survive rebases
CREATE TABLE IF NOT EXISTS changes (
  change_id VARCHAR(64) PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  session_id VARCHAR(64) REFERENCES sessions(id) ON DELETE CASCADE,
  commit_id VARCHAR(64),
  parent_change_ids TEXT[],
  description TEXT,
  author_name VARCHAR(255),
  author_email VARCHAR(255),
  timestamp BIGINT,
  is_empty BOOLEAN DEFAULT false,
  has_conflicts BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_changes_repo ON changes(repository_id);
CREATE INDEX IF NOT EXISTS idx_changes_session ON changes(session_id);
CREATE INDEX IF NOT EXISTS idx_changes_timestamp ON changes(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_changes_conflicts ON changes(has_conflicts) WHERE has_conflicts = true;

-- Bookmarks (replace branches)
-- Bookmarks are movable labels pointing to change IDs
CREATE TABLE IF NOT EXISTS bookmarks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  target_change_id VARCHAR(64) NOT NULL,
  pusher_id INTEGER REFERENCES users(id),
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_repo ON bookmarks(repository_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_change ON bookmarks(target_change_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_default ON bookmarks(repository_id, is_default) WHERE is_default = true;

-- Operations log (jj op log)
-- Tracks all jj operations for undo/redo functionality
CREATE TABLE IF NOT EXISTS jj_operations (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  session_id VARCHAR(64) REFERENCES sessions(id) ON DELETE CASCADE,
  operation_id VARCHAR(255) NOT NULL,
  operation_type VARCHAR(50),
  description TEXT,
  timestamp BIGINT NOT NULL,
  is_undone BOOLEAN DEFAULT false,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_jj_operations_repo ON jj_operations(repository_id);
CREATE INDEX IF NOT EXISTS idx_jj_operations_session ON jj_operations(session_id);
CREATE INDEX IF NOT EXISTS idx_jj_operations_timestamp ON jj_operations(timestamp DESC);

-- Conflicts (first-class citizens in jj)
-- Unlike git, conflicts are stored in commits and don't block operations
CREATE TABLE IF NOT EXISTS conflicts (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  session_id VARCHAR(64) REFERENCES sessions(id) ON DELETE CASCADE,
  change_id VARCHAR(64) NOT NULL,
  file_path TEXT NOT NULL,
  conflict_type VARCHAR(50) CHECK (conflict_type IN ('content', 'delete', 'add', 'modify_delete')),
  resolved BOOLEAN DEFAULT false,
  resolved_by INTEGER REFERENCES users(id),
  resolution_method VARCHAR(50) CHECK (resolution_method IN ('manual', 'ours', 'theirs', 'auto')),
  resolved_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(change_id, file_path)
);

CREATE INDEX IF NOT EXISTS idx_conflicts_repo ON conflicts(repository_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_session ON conflicts(session_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_change ON conflicts(change_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_unresolved ON conflicts(resolved) WHERE resolved = false;

-- Landing queue (replaces pull_requests)
-- Changes are "landed" onto bookmarks instead of "merged" into branches
CREATE TABLE IF NOT EXISTS landing_queue (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  change_id VARCHAR(64) NOT NULL,
  target_bookmark VARCHAR(255) NOT NULL,
  title VARCHAR(512),
  description TEXT,
  author_id INTEGER REFERENCES users(id),
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
    'pending',     -- Waiting to be processed
    'checking',    -- Checking for conflicts
    'ready',       -- Ready to land (no conflicts)
    'conflicted',  -- Has conflicts that need resolution
    'landed',      -- Successfully landed
    'cancelled'    -- Cancelled by user
  )),
  has_conflicts BOOLEAN DEFAULT false,
  conflicted_files TEXT[],
  landed_at TIMESTAMP,
  landed_by INTEGER REFERENCES users(id),
  landed_change_id VARCHAR(64),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_landing_queue_repo ON landing_queue(repository_id);
CREATE INDEX IF NOT EXISTS idx_landing_queue_status ON landing_queue(status);
CREATE INDEX IF NOT EXISTS idx_landing_queue_author ON landing_queue(author_id);
CREATE INDEX IF NOT EXISTS idx_landing_queue_change ON landing_queue(change_id);

-- Protected bookmarks (replaces protected_branches)
CREATE TABLE IF NOT EXISTS protected_bookmarks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  rule_name VARCHAR(255) NOT NULL,
  priority BIGINT NOT NULL DEFAULT 0,

  -- Landing protection
  require_landing_queue BOOLEAN DEFAULT true,

  -- Push protection
  can_push BOOLEAN NOT NULL DEFAULT false,
  enable_whitelist BOOLEAN DEFAULT false,
  whitelist_user_ids JSONB DEFAULT '[]',

  -- Approvals
  enable_approvals BOOLEAN DEFAULT false,
  required_approvals INTEGER DEFAULT 0,
  approvals_whitelist_user_ids JSONB DEFAULT '[]',

  -- Status checks
  enable_status_check BOOLEAN DEFAULT false,
  status_check_contexts JSONB DEFAULT '[]',

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, rule_name)
);

CREATE INDEX IF NOT EXISTS idx_protected_bookmarks_repo ON protected_bookmarks(repository_id);
CREATE INDEX IF NOT EXISTS idx_protected_bookmarks_priority ON protected_bookmarks(repository_id, priority DESC);

-- Reviews for landing requests (adapted from PR reviews)
CREATE TABLE IF NOT EXISTS landing_reviews (
  id SERIAL PRIMARY KEY,
  landing_id INTEGER NOT NULL REFERENCES landing_queue(id) ON DELETE CASCADE,
  reviewer_id INTEGER NOT NULL REFERENCES users(id),
  type VARCHAR(20) NOT NULL CHECK (type IN ('pending', 'comment', 'approve', 'request_changes')),
  content TEXT,
  change_id VARCHAR(64),
  official BOOLEAN DEFAULT false,
  stale BOOLEAN DEFAULT false,
  dismissed BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_landing_reviews_landing ON landing_reviews(landing_id);
CREATE INDEX IF NOT EXISTS idx_landing_reviews_reviewer ON landing_reviews(reviewer_id);

-- =============================================================================
-- Update existing tables
-- =============================================================================

-- Add default_bookmark to repositories (alongside default_branch for migration)
ALTER TABLE repositories
ADD COLUMN IF NOT EXISTS default_bookmark VARCHAR(255) DEFAULT 'main';

-- Update snapshot_history to include more metadata
ALTER TABLE snapshot_history
ADD COLUMN IF NOT EXISTS description TEXT,
ADD COLUMN IF NOT EXISTS operation_id INTEGER REFERENCES jj_operations(id);
