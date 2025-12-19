-- Plue Database Schema

-- Users table with authentication
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  lower_username VARCHAR(255) UNIQUE NOT NULL, -- for case-insensitive lookups
  email VARCHAR(255) UNIQUE NOT NULL,
  lower_email VARCHAR(255) UNIQUE NOT NULL, -- for case-insensitive lookups

  -- Display info
  display_name VARCHAR(255),
  bio TEXT,
  avatar_url VARCHAR(2048),

  -- Authentication
  password_hash VARCHAR(255) NOT NULL,
  password_algo VARCHAR(50) NOT NULL DEFAULT 'argon2id',
  salt VARCHAR(64) NOT NULL,

  -- Account status
  is_active BOOLEAN NOT NULL DEFAULT false, -- email verified
  is_admin BOOLEAN NOT NULL DEFAULT false,
  prohibit_login BOOLEAN NOT NULL DEFAULT false,
  must_change_password BOOLEAN NOT NULL DEFAULT false,

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_lower_username ON users(lower_username);
CREATE INDEX IF NOT EXISTS idx_users_lower_email ON users(lower_email);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);

-- Email addresses (supports multiple per user)
CREATE TABLE IF NOT EXISTS email_addresses (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  lower_email VARCHAR(255) NOT NULL,
  is_activated BOOLEAN NOT NULL DEFAULT false,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(email),
  UNIQUE(lower_email)
);

CREATE INDEX IF NOT EXISTS idx_email_addresses_user_id ON email_addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_email_addresses_lower_email ON email_addresses(lower_email);

-- Auth sessions (for cookie-based authentication)
CREATE TABLE IF NOT EXISTS auth_sessions (
  session_key VARCHAR(64) PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  data BYTEA,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at ON auth_sessions(expires_at);

-- Access tokens for API authentication
CREATE TABLE IF NOT EXISTS access_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL, -- user-defined name
  token_hash VARCHAR(64) UNIQUE NOT NULL, -- sha256 hash
  token_last_eight VARCHAR(8) NOT NULL, -- for display
  scopes VARCHAR(512) NOT NULL DEFAULT 'all', -- comma-separated
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_used_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_access_tokens_user_id ON access_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_access_tokens_token_hash ON access_tokens(token_hash);

-- Email verification tokens
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token_hash VARCHAR(64) UNIQUE NOT NULL,
  token_type VARCHAR(20) NOT NULL CHECK (token_type IN ('activate', 'reset_password')),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_user_id ON email_verification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_token_hash ON email_verification_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_expires_at ON email_verification_tokens(expires_at);

-- Repositories
CREATE TABLE IF NOT EXISTS repositories (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT true,
  default_branch VARCHAR(255) DEFAULT 'main',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, name)
);

-- Issues
CREATE TABLE IF NOT EXISTS issues (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  issue_number INTEGER NOT NULL,
  title VARCHAR(512) NOT NULL,
  body TEXT,
  state VARCHAR(20) DEFAULT 'open' CHECK (state IN ('open', 'closed')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  closed_at TIMESTAMP,
  UNIQUE(repository_id, issue_number)
);

-- Comments
CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER REFERENCES issues(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- =============================================================================
-- Pull Request Tables
-- =============================================================================

-- Pull requests extend issues
CREATE TABLE IF NOT EXISTS pull_requests (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,

  -- Branch information
  head_repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
  head_branch VARCHAR(255) NOT NULL,
  head_commit_id VARCHAR(64),
  base_repo_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  base_branch VARCHAR(255) NOT NULL,
  merge_base VARCHAR(64),

  -- Status
  status VARCHAR(20) DEFAULT 'checking' CHECK (status IN (
    'checking',      -- Checking for conflicts
    'mergeable',     -- Can be merged
    'conflict',      -- Has merge conflicts
    'merged',        -- Already merged
    'error',         -- Error during check
    'empty'          -- No changes
  )),

  -- Merge information
  has_merged BOOLEAN DEFAULT false,
  merged_at TIMESTAMP,
  merged_by INTEGER REFERENCES users(id),
  merged_commit_id VARCHAR(64),
  merge_style VARCHAR(20) CHECK (merge_style IN ('merge', 'squash', 'rebase')),

  -- Stats
  commits_ahead INTEGER DEFAULT 0,
  commits_behind INTEGER DEFAULT 0,
  additions INTEGER DEFAULT 0,
  deletions INTEGER DEFAULT 0,
  changed_files INTEGER DEFAULT 0,
  conflicted_files TEXT[], -- Array of file paths with conflicts

  -- Settings
  allow_maintainer_edit BOOLEAN DEFAULT true,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(issue_id)
);

CREATE INDEX IF NOT EXISTS idx_pull_requests_head_repo ON pull_requests(head_repo_id);
CREATE INDEX IF NOT EXISTS idx_pull_requests_base_repo ON pull_requests(base_repo_id);
CREATE INDEX IF NOT EXISTS idx_pull_requests_status ON pull_requests(status);
CREATE INDEX IF NOT EXISTS idx_pull_requests_merged ON pull_requests(has_merged);

-- Code reviews for pull requests
CREATE TABLE IF NOT EXISTS reviews (
  id SERIAL PRIMARY KEY,
  pull_request_id INTEGER NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  reviewer_id INTEGER NOT NULL REFERENCES users(id),

  -- Review type
  type VARCHAR(20) NOT NULL CHECK (type IN (
    'pending',    -- Draft review not yet submitted
    'comment',    -- General feedback
    'approve',    -- Approve changes
    'request_changes' -- Request changes before merge
  )),

  content TEXT, -- Overall review comment
  commit_id VARCHAR(64), -- Commit being reviewed

  -- Status
  official BOOLEAN DEFAULT false, -- Made by assigned reviewer
  stale BOOLEAN DEFAULT false,    -- Outdated due to new commits
  dismissed BOOLEAN DEFAULT false, -- Dismissed by maintainer

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_pr ON reviews(pull_request_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer ON reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_type ON reviews(type);

-- Line-by-line code comments
CREATE TABLE IF NOT EXISTS review_comments (
  id SERIAL PRIMARY KEY,
  review_id INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  pull_request_id INTEGER NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  author_id INTEGER NOT NULL REFERENCES users(id),

  -- Location in diff
  commit_id VARCHAR(64) NOT NULL,
  file_path TEXT NOT NULL,
  diff_side VARCHAR(10) CHECK (diff_side IN ('left', 'right')), -- old vs new
  line INTEGER NOT NULL, -- Line number in the file

  -- Content
  body TEXT NOT NULL,

  -- Status
  invalidated BOOLEAN DEFAULT false, -- Line changed by subsequent commit
  resolved BOOLEAN DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_review_comments_review ON review_comments(review_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_pr ON review_comments(pull_request_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_file ON review_comments(pull_request_id, file_path);

-- =============================================================================
-- Agent State Tables
-- =============================================================================

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
  id VARCHAR(64) PRIMARY KEY,
  project_id VARCHAR(255) NOT NULL DEFAULT 'default',
  directory TEXT NOT NULL,
  title VARCHAR(512) NOT NULL,
  version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
  time_created BIGINT NOT NULL,
  time_updated BIGINT NOT NULL,
  time_archived BIGINT,
  parent_id VARCHAR(64) REFERENCES sessions(id) ON DELETE SET NULL,
  fork_point VARCHAR(64),
  summary JSONB,
  revert JSONB,
  compaction JSONB,
  token_count INTEGER NOT NULL DEFAULT 0,
  bypass_mode BOOLEAN NOT NULL DEFAULT false,
  model VARCHAR(255),
  reasoning_effort VARCHAR(20) CHECK (reasoning_effort IN ('minimal', 'low', 'medium', 'high')),
  ghost_commit JSONB,
  plugins JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(time_updated DESC);

-- Messages
CREATE TABLE IF NOT EXISTS messages (
  id VARCHAR(64) PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
  time_created BIGINT NOT NULL,
  time_completed BIGINT,
  -- Status tracking
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'streaming', 'completed', 'failed', 'aborted')),
  thinking_text TEXT,
  error_message TEXT,
  -- User message fields
  agent VARCHAR(255),
  model_provider_id VARCHAR(255),
  model_model_id VARCHAR(255),
  system_prompt TEXT,
  tools JSONB,
  -- Assistant message fields
  parent_id VARCHAR(64),
  mode VARCHAR(64),
  path_cwd TEXT,
  path_root TEXT,
  cost DECIMAL(20, 10),
  tokens_input INTEGER,
  tokens_output INTEGER,
  tokens_reasoning INTEGER,
  tokens_cache_read INTEGER,
  tokens_cache_write INTEGER,
  finish VARCHAR(64),
  is_summary BOOLEAN,
  error JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(session_id, created_at);

-- Parts (message components)
CREATE TABLE IF NOT EXISTS parts (
  id VARCHAR(64) PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  message_id VARCHAR(64) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL CHECK (type IN ('text', 'reasoning', 'tool', 'file')),
  -- Text/Reasoning fields
  text TEXT,
  -- Tool fields
  tool_name VARCHAR(255),
  tool_state JSONB,
  -- File fields
  mime VARCHAR(255),
  url TEXT,
  filename VARCHAR(512),
  -- Time tracking
  time_start BIGINT,
  time_end BIGINT,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_parts_message ON parts(message_id);
CREATE INDEX IF NOT EXISTS idx_parts_session ON parts(session_id);

-- Snapshot History
CREATE TABLE IF NOT EXISTS snapshot_history (
  id SERIAL PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  change_id VARCHAR(255) NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_snapshot_history_session ON snapshot_history(session_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_snapshot_history_order ON snapshot_history(session_id, sort_order);

-- Subtasks
CREATE TABLE IF NOT EXISTS subtasks (
  id SERIAL PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  result JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subtasks_session ON subtasks(session_id);

-- File Trackers
CREATE TABLE IF NOT EXISTS file_trackers (
  id SERIAL PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  read_time BIGINT,
  mod_time BIGINT,
  UNIQUE(session_id, file_path)
);

CREATE INDEX IF NOT EXISTS idx_file_trackers_session ON file_trackers(session_id);

-- =============================================================================
-- Seed Data (with temporary passwords for existing users)
-- =============================================================================

-- Seed mock users with auth fields
INSERT INTO users (username, lower_username, email, lower_email, display_name, bio, password_hash, password_algo, salt, is_active) VALUES
  ('evilrabbit', 'evilrabbit', 'evilrabbit@plue.local', 'evilrabbit@plue.local', 'Evil Rabbit', 'Building dark things', 'temp_hash', 'argon2id', 'temp_salt', false),
  ('ghost', 'ghost', 'ghost@plue.local', 'ghost@plue.local', 'Ghost', 'Spectral presence', 'temp_hash', 'argon2id', 'temp_salt', false),
  ('null', 'null', 'null@plue.local', 'null@plue.local', 'Null', 'Exception handler', 'temp_hash', 'argon2id', 'temp_salt', false)
ON CONFLICT (username) DO UPDATE SET
  lower_username = EXCLUDED.lower_username,
  email = EXCLUDED.email,
  lower_email = EXCLUDED.lower_email,
  password_hash = EXCLUDED.password_hash,
  password_algo = EXCLUDED.password_algo,
  salt = EXCLUDED.salt,
  is_active = EXCLUDED.is_active;