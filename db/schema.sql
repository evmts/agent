-- Plue Database Schema

-- Users table with SIWE (Sign In With Ethereum) authentication
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  lower_username VARCHAR(255) UNIQUE NOT NULL, -- for case-insensitive lookups
  email VARCHAR(255) UNIQUE,
  lower_email VARCHAR(255) UNIQUE, -- for case-insensitive lookups

  -- Display info
  display_name VARCHAR(255),
  bio TEXT,
  avatar_url VARCHAR(2048),

  -- SIWE Authentication
  wallet_address VARCHAR(42) UNIQUE, -- Ethereum address (checksummed)

  -- Account status
  is_active BOOLEAN NOT NULL DEFAULT true, -- SIWE users are active by default
  is_admin BOOLEAN NOT NULL DEFAULT false,
  prohibit_login BOOLEAN NOT NULL DEFAULT false,

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_lower_username ON users(lower_username);
CREATE INDEX IF NOT EXISTS idx_users_lower_email ON users(lower_email);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_wallet_address ON users(wallet_address);

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
  username VARCHAR(255) NOT NULL,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  data BYTEA, -- Legacy field for TypeScript compatibility
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

-- Email verification tokens (for email-based features)
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token_hash VARCHAR(64) UNIQUE NOT NULL, -- sha256 hash
  token_type VARCHAR(20) NOT NULL CHECK (token_type IN ('verify', 'reset')),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  used_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_user_id ON email_verification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_hash ON email_verification_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_expires ON email_verification_tokens(expires_at);

-- SIWE nonces for replay attack prevention
CREATE TABLE IF NOT EXISTS siwe_nonces (
  nonce VARCHAR(64) PRIMARY KEY,
  wallet_address VARCHAR(42),
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL,
  used_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_siwe_nonces_expires ON siwe_nonces(expires_at);
CREATE INDEX IF NOT EXISTS idx_siwe_nonces_wallet ON siwe_nonces(wallet_address);

-- Repositories
CREATE TABLE IF NOT EXISTS repositories (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT true,
  default_branch VARCHAR(255) DEFAULT 'main',
  topics TEXT[] DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, name)
);

-- Milestones
CREATE TABLE IF NOT EXISTS milestones (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  due_date TIMESTAMP,
  state VARCHAR(20) DEFAULT 'open' CHECK (state IN ('open', 'closed')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  closed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_milestones_repository ON milestones(repository_id);
CREATE INDEX IF NOT EXISTS idx_milestones_state ON milestones(state);

-- Issues
CREATE TABLE IF NOT EXISTS issues (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  issue_number INTEGER NOT NULL,
  title VARCHAR(512) NOT NULL,
  body TEXT,
  state VARCHAR(20) DEFAULT 'open' CHECK (state IN ('open', 'closed')),
  milestone_id INTEGER REFERENCES milestones(id) ON DELETE SET NULL,
  due_date TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  closed_at TIMESTAMP,
  UNIQUE(repository_id, issue_number)
);

CREATE INDEX IF NOT EXISTS idx_issues_milestone ON issues(milestone_id);

-- Comments
CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER REFERENCES issues(id) ON DELETE CASCADE,
  author_id INTEGER REFERENCES users(id) ON DELETE RESTRICT,
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  edited BOOLEAN NOT NULL DEFAULT false
);

-- Mentions (for potential notifications in git-based issues)
CREATE TABLE IF NOT EXISTS mentions (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  issue_number INTEGER NOT NULL,
  comment_id VARCHAR(10), -- NULL for issue body, or comment ID like "001"
  mentioned_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mentions_repo_issue ON mentions(repository_id, issue_number);
CREATE INDEX IF NOT EXISTS idx_mentions_user ON mentions(mentioned_user_id);

-- Issue assignees (many-to-many relationship)
CREATE TABLE IF NOT EXISTS issue_assignees (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  assigned_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(issue_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_issue_assignees_issue ON issue_assignees(issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_assignees_user ON issue_assignees(user_id);

-- Labels for issues
CREATE TABLE IF NOT EXISTS labels (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  color VARCHAR(7) NOT NULL, -- hex color like #ff0000
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_labels_repository ON labels(repository_id);

-- Issue labels (many-to-many relationship)
CREATE TABLE IF NOT EXISTS issue_labels (
  id SERIAL PRIMARY KEY,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  label_id INTEGER NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(issue_id, label_id)
);

CREATE INDEX IF NOT EXISTS idx_issue_labels_issue ON issue_labels(issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_labels_label ON issue_labels(label_id);

-- =============================================================================
-- Branch Management Tables
-- =============================================================================

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

-- SSH Keys for Git over SSH authentication
CREATE TABLE IF NOT EXISTS ssh_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL, -- User-defined key name
  fingerprint VARCHAR(255) NOT NULL UNIQUE, -- SHA256:... fingerprint
  public_key TEXT NOT NULL, -- Full public key content
  key_type VARCHAR(32) NOT NULL DEFAULT 'user', -- 'user' or 'deploy'
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);
CREATE INDEX IF NOT EXISTS idx_ssh_keys_user_id ON ssh_keys(user_id);

-- =============================================================================
-- Workflow System Tables (New Python-based workflow system)
-- =============================================================================

-- Workflow definitions (parsed from .py files)
CREATE TABLE IF NOT EXISTS workflow_definitions (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  triggers JSONB NOT NULL,              -- Trigger configuration from workflow decorator
  image VARCHAR(255),                   -- Docker image
  dockerfile VARCHAR(500),              -- Path to Dockerfile
  plan JSONB NOT NULL,                  -- The generated DAG of steps
  content_hash VARCHAR(64) NOT NULL,    -- SHA256 hash for change detection
  parsed_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_workflow_definitions_repo ON workflow_definitions(repository_id);

-- Prompt definitions (parsed from .prompt.md files)
CREATE TABLE IF NOT EXISTS prompt_definitions (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  client VARCHAR(100) NOT NULL,
  prompt_type VARCHAR(20) NOT NULL,     -- llm, agent
  inputs_schema JSONB NOT NULL,
  output_schema JSONB NOT NULL,
  tools JSONB,
  max_turns INTEGER,
  body_template TEXT NOT NULL,
  content_hash VARCHAR(64) NOT NULL,
  parsed_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_prompt_definitions_repo ON prompt_definitions(repository_id);

-- Workflow runs
CREATE TABLE IF NOT EXISTS workflow_runs (
  id SERIAL PRIMARY KEY,
  workflow_definition_id INTEGER REFERENCES workflow_definitions(id) ON DELETE SET NULL,
  trigger_type VARCHAR(50) NOT NULL,
  trigger_payload JSONB NOT NULL,
  inputs JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  outputs JSONB,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow ON workflow_runs(workflow_definition_id);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_status ON workflow_runs(status);

-- Individual steps within a run
CREATE TABLE IF NOT EXISTS workflow_steps (
  id SERIAL PRIMARY KEY,
  run_id INTEGER REFERENCES workflow_runs(id) ON DELETE CASCADE,
  step_id VARCHAR(100) NOT NULL,
  name VARCHAR(255) NOT NULL,
  step_type VARCHAR(20) NOT NULL,       -- shell, llm, agent, parallel
  config JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  exit_code INTEGER,
  output JSONB,
  error_message TEXT,

  -- Agent-specific
  turns_used INTEGER,
  tokens_in INTEGER,
  tokens_out INTEGER
);

CREATE INDEX IF NOT EXISTS idx_workflow_steps_run ON workflow_steps(run_id);

-- Step logs (streaming output)
CREATE TABLE IF NOT EXISTS workflow_logs (
  id SERIAL PRIMARY KEY,
  step_id INTEGER REFERENCES workflow_steps(id) ON DELETE CASCADE,
  log_type VARCHAR(20) NOT NULL,        -- stdout, stderr, token, tool_call, tool_result
  content TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_logs_step ON workflow_logs(step_id, sequence);

-- LLM usage tracking
CREATE TABLE IF NOT EXISTS llm_usage (
  id SERIAL PRIMARY KEY,
  step_id INTEGER REFERENCES workflow_steps(id) ON DELETE CASCADE,
  prompt_name VARCHAR(255),
  model VARCHAR(100) NOT NULL,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  latency_ms INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_llm_usage_step ON llm_usage(step_id);

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

-- =============================================================================
-- Seed Data
-- =============================================================================

-- Seed mock users (SIWE auth - no passwords)
INSERT INTO users (username, lower_username, email, lower_email, display_name, bio, is_active) VALUES
  ('evilrabbit', 'evilrabbit', 'evilrabbit@plue.local', 'evilrabbit@plue.local', 'Evil Rabbit', 'Building dark things', false),
  ('ghost', 'ghost', 'ghost@plue.local', 'ghost@plue.local', 'Ghost', 'Spectral presence', false),
  ('null', 'null', 'null@plue.local', 'null@plue.local', 'Null', 'Exception handler', false)
ON CONFLICT (username) DO UPDATE SET
  lower_username = EXCLUDED.lower_username,
  email = EXCLUDED.email,
  lower_email = EXCLUDED.lower_email,
  is_active = EXCLUDED.is_active;
-- =============================================================================
-- Repository Starring and Watching
-- =============================================================================

-- Stars table tracks which users have starred which repositories
CREATE TABLE IF NOT EXISTS stars (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, repository_id)
);

CREATE INDEX IF NOT EXISTS idx_stars_user ON stars(user_id);
CREATE INDEX IF NOT EXISTS idx_stars_repo ON stars(repository_id);
CREATE INDEX IF NOT EXISTS idx_stars_created ON stars(created_at DESC);

-- Watches table tracks which users are watching which repositories
-- level: 'all' = all activity, 'releases' = releases only, 'ignore' = ignore all
CREATE TABLE IF NOT EXISTS watches (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  level VARCHAR(20) NOT NULL DEFAULT 'all' CHECK (level IN ('all', 'releases', 'ignore')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, repository_id)
);

CREATE INDEX IF NOT EXISTS idx_watches_user ON watches(user_id);
CREATE INDEX IF NOT EXISTS idx_watches_repo ON watches(repository_id);
CREATE INDEX IF NOT EXISTS idx_watches_level ON watches(level);

-- =============================================================================
-- Reactions Tables
-- =============================================================================

-- Reactions for issues and comments
CREATE TABLE IF NOT EXISTS reactions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('issue', 'comment')),
  target_id INTEGER NOT NULL,
  emoji VARCHAR(10) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, target_type, target_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_reactions_issue ON reactions(target_type, target_id) WHERE target_type = 'issue';
CREATE INDEX IF NOT EXISTS idx_reactions_comment ON reactions(target_type, target_id) WHERE target_type = 'comment';
CREATE INDEX IF NOT EXISTS idx_reactions_user ON reactions(user_id);

-- =============================================================================
-- Issue Activity Timeline
-- =============================================================================

-- Issue events for activity timeline (system comments)
CREATE TABLE IF NOT EXISTS issue_events (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  issue_number INTEGER NOT NULL,
  actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL,

  -- Event type
  event_type VARCHAR(30) NOT NULL CHECK (event_type IN (
    'closed',
    'reopened',
    'label_added',
    'label_removed',
    'assignee_added',
    'assignee_removed',
    'milestone_added',
    'milestone_removed',
    'milestone_changed',
    'title_changed',
    'renamed'
  )),

  -- Event metadata (stored as JSONB for flexibility)
  -- Examples:
  -- label events: {"label": "bug"}
  -- assignee events: {"assignee": "username"}
  -- milestone events: {"milestone": "v1.0"}
  -- title change: {"old_title": "...", "new_title": "..."}
  metadata JSONB DEFAULT '{}',

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_issue_events_repo_issue ON issue_events(repository_id, issue_number);
CREATE INDEX IF NOT EXISTS idx_issue_events_actor ON issue_events(actor_id);
CREATE INDEX IF NOT EXISTS idx_issue_events_type ON issue_events(event_type);
CREATE INDEX IF NOT EXISTS idx_issue_events_created ON issue_events(created_at);

-- =============================================================================
-- Issue Dependencies (Blocking/Blocked By)
-- =============================================================================

-- Track which issues block other issues
-- blocker_issue_id blocks blocked_issue_id
CREATE TABLE IF NOT EXISTS issue_dependencies (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  blocker_issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  blocked_issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(blocker_issue_id, blocked_issue_id),
  -- Prevent self-blocking
  CHECK (blocker_issue_id != blocked_issue_id)
);

CREATE INDEX IF NOT EXISTS idx_issue_dependencies_blocker ON issue_dependencies(blocker_issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_dependencies_blocked ON issue_dependencies(blocked_issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_dependencies_repo ON issue_dependencies(repository_id);

-- =============================================================================
-- Pinned Issues
-- =============================================================================

-- Track pinned issues (max 3 per repository)
CREATE TABLE IF NOT EXISTS pinned_issues (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  pin_order INTEGER NOT NULL DEFAULT 0, -- 0 = first, 1 = second, 2 = third
  pinned_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, issue_id),
  UNIQUE(repository_id, pin_order),
  CHECK (pin_order >= 0 AND pin_order <= 2)
);

CREATE INDEX IF NOT EXISTS idx_pinned_issues_repo ON pinned_issues(repository_id);
CREATE INDEX IF NOT EXISTS idx_pinned_issues_issue ON pinned_issues(issue_id);
CREATE INDEX IF NOT EXISTS idx_pinned_issues_order ON pinned_issues(repository_id, pin_order);

-- =============================================================================
-- JJ-Native Tables (Jujutsu VCS Support)
-- =============================================================================

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

-- Conflicts - track conflicts in changes and their resolution status
CREATE TABLE IF NOT EXISTS conflicts (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  change_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  conflict_type TEXT NOT NULL DEFAULT 'content', -- 'content', 'rename', 'delete'
  resolved BOOLEAN DEFAULT FALSE,
  resolved_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  resolution_method TEXT, -- 'manual', 'theirs', 'ours', 'base'
  resolved_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(change_id, file_path)
);

CREATE INDEX IF NOT EXISTS idx_conflicts_repo ON conflicts(repository_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_change ON conflicts(change_id);
CREATE INDEX IF NOT EXISTS idx_conflicts_resolved ON conflicts(resolved);
CREATE INDEX IF NOT EXISTS idx_conflicts_file ON conflicts(file_path);

-- =============================================================================
-- Rate Limiting
-- =============================================================================

-- Distributed rate limiting using PostgreSQL
CREATE TABLE IF NOT EXISTS rate_limits (
  key VARCHAR(255) PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0,
  window_start TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_expires ON rate_limits(expires_at);

-- =============================================================================
-- Runner Pool (Warm Pool for Agent/Workflow Execution)
-- =============================================================================

-- Tracks standby runner pods for fast task assignment
CREATE TABLE IF NOT EXISTS runner_pool (
  id SERIAL PRIMARY KEY,
  pod_name VARCHAR(255) UNIQUE NOT NULL,
  pod_ip VARCHAR(45) NOT NULL,
  node_name VARCHAR(255),
  status VARCHAR(20) NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'claimed', 'terminated')),
  registered_at TIMESTAMP DEFAULT NOW(),
  last_heartbeat TIMESTAMP DEFAULT NOW(),
  claimed_at TIMESTAMP,
  claimed_by_task_id INTEGER REFERENCES workflow_tasks(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_runner_pool_status ON runner_pool(status);
CREATE INDEX IF NOT EXISTS idx_runner_pool_available ON runner_pool(status) WHERE status = 'available';
CREATE INDEX IF NOT EXISTS idx_runner_pool_heartbeat ON runner_pool(last_heartbeat);

-- =============================================================================
-- Landing Queue (Pull Request Landing System)
-- =============================================================================

-- Tracks change landing requests (similar to GitHub merge queue)
CREATE TABLE IF NOT EXISTS landing_queue (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  change_id VARCHAR(255) NOT NULL,
  target_bookmark VARCHAR(255) NOT NULL,
  title VARCHAR(512),
  description TEXT,
  author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'checking', 'ready', 'landed', 'failed', 'aborted')),
  has_conflicts BOOLEAN DEFAULT false,
  conflicted_files TEXT[],
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  landed_at TIMESTAMP,
  landed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  landed_change_id VARCHAR(255),
  UNIQUE(repository_id, change_id)
);

CREATE INDEX IF NOT EXISTS idx_landing_queue_repo ON landing_queue(repository_id);
CREATE INDEX IF NOT EXISTS idx_landing_queue_status ON landing_queue(status);
CREATE INDEX IF NOT EXISTS idx_landing_queue_author ON landing_queue(author_id);
CREATE INDEX IF NOT EXISTS idx_landing_queue_created ON landing_queue(created_at);

-- Landing reviews (approval/rejection of landing requests)
CREATE TABLE IF NOT EXISTS landing_reviews (
  id SERIAL PRIMARY KEY,
  landing_id INTEGER NOT NULL REFERENCES landing_queue(id) ON DELETE CASCADE,
  reviewer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'dismissed')),
  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(landing_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_landing_reviews_landing ON landing_reviews(landing_id);
CREATE INDEX IF NOT EXISTS idx_landing_reviews_reviewer ON landing_reviews(reviewer_id);

-- Line comments on landing requests
CREATE TABLE IF NOT EXISTS landing_line_comments (
  id SERIAL PRIMARY KEY,
  landing_id INTEGER NOT NULL REFERENCES landing_queue(id) ON DELETE CASCADE,
  author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  file_path TEXT NOT NULL,
  line_number INTEGER,
  side VARCHAR(10) CHECK (side IN ('left', 'right')),
  content TEXT NOT NULL,
  resolved BOOLEAN DEFAULT false,
  resolved_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  resolved_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_landing_line_comments_landing ON landing_line_comments(landing_id);
CREATE INDEX IF NOT EXISTS idx_landing_line_comments_file ON landing_line_comments(landing_id, file_path);
