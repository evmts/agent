-- JJ-Native Migration
-- Tables for jj (Jujutsu) VCS support

-- Changes - tracks jj change metadata
CREATE TABLE IF NOT EXISTS changes (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  change_id VARCHAR(64) NOT NULL, -- jj change ID (stable across rebases)
  commit_id VARCHAR(64), -- git commit ID if colocated
  description TEXT,
  author_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  author_name VARCHAR(255),
  author_email VARCHAR(255),
  has_conflict BOOLEAN DEFAULT false,
  is_empty BOOLEAN DEFAULT false,
  parent_change_ids JSONB DEFAULT '[]',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, change_id)
);

CREATE INDEX IF NOT EXISTS idx_changes_repo ON changes(repository_id);
CREATE INDEX IF NOT EXISTS idx_changes_change_id ON changes(change_id);
CREATE INDEX IF NOT EXISTS idx_changes_commit ON changes(commit_id);

-- Bookmarks - jj bookmarks (like git branches but movable labels)
CREATE TABLE IF NOT EXISTS bookmarks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  target_change_id VARCHAR(64) NOT NULL,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_repo ON bookmarks(repository_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_target ON bookmarks(target_change_id);

-- JJ Operations - operation log for undo/redo
CREATE TABLE IF NOT EXISTS jj_operations (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  operation_id VARCHAR(64) NOT NULL,
  operation_type VARCHAR(64) NOT NULL,
  description TEXT,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  parent_operation_id VARCHAR(64),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, operation_id)
);

CREATE INDEX IF NOT EXISTS idx_jj_operations_repo ON jj_operations(repository_id);

-- Landing Queue - landing requests (replaces pull requests)
CREATE TABLE IF NOT EXISTS landing_queue (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  source_change_id VARCHAR(64) NOT NULL,
  target_bookmark VARCHAR(255) NOT NULL,
  author_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  title VARCHAR(512) NOT NULL,
  description TEXT,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'ready', 'conflict', 'landed', 'closed')),
  has_conflict BOOLEAN DEFAULT false,
  landed_at TIMESTAMP,
  landed_by INTEGER REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_landing_queue_repo ON landing_queue(repository_id);
CREATE INDEX IF NOT EXISTS idx_landing_queue_status ON landing_queue(status);

-- Protected Bookmarks - protection rules for bookmarks
CREATE TABLE IF NOT EXISTS protected_bookmarks (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  pattern VARCHAR(255) NOT NULL,
  require_review BOOLEAN DEFAULT true,
  required_approvals INTEGER DEFAULT 1,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, pattern)
);

CREATE INDEX IF NOT EXISTS idx_protected_bookmarks_repo ON protected_bookmarks(repository_id);

-- Landing Reviews - reviews on landing requests
CREATE TABLE IF NOT EXISTS landing_reviews (
  id SERIAL PRIMARY KEY,
  landing_id INTEGER NOT NULL REFERENCES landing_queue(id) ON DELETE CASCADE,
  reviewer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'approved', 'changes_requested')),
  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(landing_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_landing_reviews_landing ON landing_reviews(landing_id);
CREATE INDEX IF NOT EXISTS idx_landing_reviews_reviewer ON landing_reviews(reviewer_id);
