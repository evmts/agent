-- Actions: Core Data Models & Database Schema
-- GitHub Actions-compatible CI/CD system database schema

-- Table: actions_workflows
-- Stores workflow definitions parsed from .github/workflows/*.yml
CREATE TABLE actions_workflows (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    filename VARCHAR(500) NOT NULL, -- .github/workflows/ci.yml
    yaml_content TEXT NOT NULL,
    triggers JSONB NOT NULL DEFAULT '[]', -- Parsed trigger events
    jobs JSONB NOT NULL DEFAULT '{}', -- Parsed job definitions
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(repository_id, filename)
);

-- Table: actions_workflow_runs
-- Tracks individual executions of workflows
CREATE TABLE actions_workflow_runs (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    workflow_id INTEGER NOT NULL REFERENCES actions_workflows(id) ON DELETE CASCADE,
    run_number INTEGER NOT NULL, -- Sequential number per repository
    status VARCHAR(20) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'in_progress', 'completed', 'cancelled')),
    conclusion VARCHAR(20) CHECK (conclusion IN ('success', 'failure', 'cancelled', 'timed_out')),
    trigger_event JSONB NOT NULL, -- The event that triggered this run
    commit_sha VARCHAR(40) NOT NULL,
    branch VARCHAR(255) NOT NULL,
    actor_id INTEGER NOT NULL REFERENCES users(id),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(repository_id, run_number)
);

-- Table: actions_job_executions
-- Individual job executions within workflow runs
CREATE TABLE actions_job_executions (
    id SERIAL PRIMARY KEY,
    workflow_run_id INTEGER NOT NULL REFERENCES actions_workflow_runs(id) ON DELETE CASCADE,
    job_id VARCHAR(255) NOT NULL, -- Job name from YAML
    job_name VARCHAR(255), -- Display name
    runner_id INTEGER REFERENCES actions_runners(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'queued', 'in_progress', 'completed', 'cancelled', 'failed')),
    conclusion VARCHAR(20) CHECK (conclusion IN ('success', 'failure', 'cancelled', 'skipped', 'timed_out')),
    runs_on JSONB NOT NULL DEFAULT '[]', -- Runner requirements/labels
    needs JSONB NOT NULL DEFAULT '[]', -- Job dependencies
    if_condition TEXT, -- Conditional execution
    strategy JSONB, -- Matrix/parallel execution strategy
    timeout_minutes INTEGER DEFAULT 360, -- 6 hours default
    environment JSONB NOT NULL DEFAULT '{}', -- Environment variables
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    logs TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(workflow_run_id, job_id)
);

-- Table: actions_job_steps
-- Individual steps within job executions
CREATE TABLE actions_job_steps (
    id SERIAL PRIMARY KEY,
    job_execution_id INTEGER NOT NULL REFERENCES actions_job_executions(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    name VARCHAR(500),
    uses VARCHAR(500), -- Action to use (e.g., actions/checkout@v3)
    run TEXT, -- Shell command to run
    with_params JSONB NOT NULL DEFAULT '{}', -- Action parameters
    env JSONB NOT NULL DEFAULT '{}', -- Step-specific environment
    if_condition TEXT, -- Conditional execution
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped', 'failed')),
    conclusion VARCHAR(20) CHECK (conclusion IN ('success', 'failure', 'cancelled', 'skipped', 'timed_out')),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    logs TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(job_execution_id, step_number)
);

-- Table: actions_runners
-- CI/CD runner registration and management
CREATE TABLE actions_runners (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    labels JSONB NOT NULL DEFAULT '[]', -- Runner labels for job matching
    repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE, -- null for org-wide
    organization_id INTEGER REFERENCES organizations(id) ON DELETE CASCADE, -- null for repo-specific
    user_id INTEGER REFERENCES users(id), -- Runner owner
    status VARCHAR(20) NOT NULL DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'busy')),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    capabilities JSONB NOT NULL DEFAULT '{}', -- Runner capabilities
    version VARCHAR(100),
    os VARCHAR(50),
    architecture VARCHAR(50),
    ip_address INET,
    runner_token_hash VARCHAR(255), -- Hashed authentication token
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: actions_secrets
-- Encrypted secret storage for workflows
CREATE TABLE actions_secrets (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    encrypted_value TEXT NOT NULL, -- AES encrypted value
    key_id VARCHAR(255) NOT NULL, -- Key ID for decryption
    repository_id INTEGER REFERENCES repositories(id) ON DELETE CASCADE, -- null for org-wide
    organization_id INTEGER REFERENCES organizations(id) ON DELETE CASCADE, -- null for repo-specific
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    UNIQUE(repository_id, organization_id, name)
);

-- Table: actions_audit_logs
-- Comprehensive audit trail for all actions operations
CREATE TABLE actions_audit_logs (
    id SERIAL PRIMARY KEY,
    action VARCHAR(100) NOT NULL, -- e.g., 'workflow_run_created', 'job_started'
    actor_id INTEGER REFERENCES users(id),
    repository_id INTEGER REFERENCES repositories(id),
    organization_id INTEGER REFERENCES organizations(id),
    workflow_id INTEGER REFERENCES actions_workflows(id),
    workflow_run_id INTEGER REFERENCES actions_workflow_runs(id),
    job_execution_id INTEGER REFERENCES actions_job_executions(id),
    runner_id INTEGER REFERENCES actions_runners(id),
    details JSONB NOT NULL DEFAULT '{}', -- Action-specific details
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Performance Indexes

-- Workflows
CREATE INDEX idx_actions_workflows_repository_id ON actions_workflows(repository_id);
CREATE INDEX idx_actions_workflows_active ON actions_workflows(active) WHERE active = true;
CREATE INDEX idx_actions_workflows_triggers ON actions_workflows USING GIN(triggers);

-- Workflow Runs  
CREATE INDEX idx_actions_workflow_runs_repository_id ON actions_workflow_runs(repository_id);
CREATE INDEX idx_actions_workflow_runs_workflow_id ON actions_workflow_runs(workflow_id);
CREATE INDEX idx_actions_workflow_runs_status ON actions_workflow_runs(status);
CREATE INDEX idx_actions_workflow_runs_actor_id ON actions_workflow_runs(actor_id);
CREATE INDEX idx_actions_workflow_runs_commit_sha ON actions_workflow_runs(commit_sha);
CREATE INDEX idx_actions_workflow_runs_branch ON actions_workflow_runs(branch);
CREATE INDEX idx_actions_workflow_runs_created_at ON actions_workflow_runs(created_at DESC);

-- Job Executions
CREATE INDEX idx_actions_job_executions_workflow_run_id ON actions_job_executions(workflow_run_id);
CREATE INDEX idx_actions_job_executions_runner_id ON actions_job_executions(runner_id);
CREATE INDEX idx_actions_job_executions_status ON actions_job_executions(status);
CREATE INDEX idx_actions_job_executions_needs ON actions_job_executions USING GIN(needs);
CREATE INDEX idx_actions_job_executions_runs_on ON actions_job_executions USING GIN(runs_on);

-- Job Steps
CREATE INDEX idx_actions_job_steps_job_execution_id ON actions_job_steps(job_execution_id);
CREATE INDEX idx_actions_job_steps_status ON actions_job_steps(status);

-- Runners
CREATE INDEX idx_actions_runners_status ON actions_runners(status);
CREATE INDEX idx_actions_runners_labels ON actions_runners USING GIN(labels);
CREATE INDEX idx_actions_runners_repository_id ON actions_runners(repository_id);
CREATE INDEX idx_actions_runners_organization_id ON actions_runners(organization_id);
CREATE INDEX idx_actions_runners_last_seen ON actions_runners(last_seen DESC);

-- Secrets
CREATE INDEX idx_actions_secrets_repository_id ON actions_secrets(repository_id);
CREATE INDEX idx_actions_secrets_organization_id ON actions_secrets(organization_id);
CREATE INDEX idx_actions_secrets_name ON actions_secrets(name);

-- Audit Logs
CREATE INDEX idx_actions_audit_logs_action ON actions_audit_logs(action);
CREATE INDEX idx_actions_audit_logs_actor_id ON actions_audit_logs(actor_id);
CREATE INDEX idx_actions_audit_logs_repository_id ON actions_audit_logs(repository_id);
CREATE INDEX idx_actions_audit_logs_workflow_run_id ON actions_audit_logs(workflow_run_id);
CREATE INDEX idx_actions_audit_logs_created_at ON actions_audit_logs(created_at DESC);

-- Functional Indexes for Common Queries
CREATE INDEX idx_actions_workflow_runs_active ON actions_workflow_runs(repository_id, status) WHERE status IN ('queued', 'in_progress');
CREATE INDEX idx_actions_job_executions_queued ON actions_job_executions(status, created_at) WHERE status = 'queued';
CREATE INDEX idx_actions_runners_available ON actions_runners(status, last_seen) WHERE status = 'online';

-- Trigger for updating updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_actions_workflows_updated_at BEFORE UPDATE ON actions_workflows FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_actions_runners_updated_at BEFORE UPDATE ON actions_runners FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_actions_secrets_updated_at BEFORE UPDATE ON actions_secrets FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE actions_workflows IS 'GitHub Actions workflow definitions from YAML files';
COMMENT ON TABLE actions_workflow_runs IS 'Individual executions of workflows triggered by events';
COMMENT ON TABLE actions_job_executions IS 'Job executions within workflow runs with dependency tracking';
COMMENT ON TABLE actions_job_steps IS 'Individual steps within jobs with detailed execution tracking';
COMMENT ON TABLE actions_runners IS 'Self-hosted and managed CI/CD runners';
COMMENT ON TABLE actions_secrets IS 'Encrypted secrets available to workflows';
COMMENT ON TABLE actions_audit_logs IS 'Comprehensive audit trail for compliance and debugging';