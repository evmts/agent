-- Workflow system tables (from docs/workflows-engineering.md)

CREATE TABLE IF NOT EXISTS workflow_definitions (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  triggers JSONB NOT NULL,
  image VARCHAR(255),
  dockerfile VARCHAR(500),
  plan JSONB NOT NULL,
  content_hash VARCHAR(64) NOT NULL,
  parsed_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_workflow_definitions_repo ON workflow_definitions(repository_id);

CREATE TABLE IF NOT EXISTS prompt_definitions (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  client VARCHAR(100) NOT NULL,
  prompt_type VARCHAR(20) NOT NULL,
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

CREATE TABLE IF NOT EXISTS workflow_steps (
  id SERIAL PRIMARY KEY,
  run_id INTEGER REFERENCES workflow_runs(id) ON DELETE CASCADE,
  step_id VARCHAR(100) NOT NULL,
  name VARCHAR(255) NOT NULL,
  step_type VARCHAR(20) NOT NULL,
  config JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  exit_code INTEGER,
  output JSONB,
  error_message TEXT,
  turns_used INTEGER,
  tokens_in INTEGER,
  tokens_out INTEGER
);

CREATE INDEX IF NOT EXISTS idx_workflow_steps_run ON workflow_steps(run_id);

CREATE TABLE IF NOT EXISTS workflow_logs (
  id SERIAL PRIMARY KEY,
  step_id INTEGER REFERENCES workflow_steps(id) ON DELETE CASCADE,
  log_type VARCHAR(20) NOT NULL,
  content TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_logs_step ON workflow_logs(step_id, sequence);

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
