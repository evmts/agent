-- Plue Database Schema

-- Users (seeded, no auth)
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  display_name VARCHAR(255),
  bio TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Repositories
CREATE TABLE IF NOT EXISTS repositories (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
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
  author_id INTEGER REFERENCES users(id),
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
  author_id INTEGER REFERENCES users(id),
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

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
-- Seed Data
-- =============================================================================

-- Seed mock users
INSERT INTO users (username, display_name, bio) VALUES
  ('evilrabbit', 'Evil Rabbit', 'Building dark things'),
  ('ghost', 'Ghost', 'Spectral presence'),
  ('null', 'Null', 'Exception handler')
ON CONFLICT (username) DO NOTHING;
