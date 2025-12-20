-- Issue References Migration
-- Tracks cross-references between issues (#123 linking)

CREATE TABLE IF NOT EXISTS issue_references (
  id SERIAL PRIMARY KEY,
  source_issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  target_issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),

  -- Prevent duplicate references
  UNIQUE(source_issue_id, target_issue_id)
);

CREATE INDEX IF NOT EXISTS idx_issue_references_source ON issue_references(source_issue_id);
CREATE INDEX IF NOT EXISTS idx_issue_references_target ON issue_references(target_issue_id);

-- Also track references from comments
CREATE TABLE IF NOT EXISTS comment_references (
  id SERIAL PRIMARY KEY,
  comment_id INTEGER NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  target_issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(comment_id, target_issue_id)
);

CREATE INDEX IF NOT EXISTS idx_comment_references_comment ON comment_references(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_references_target ON comment_references(target_issue_id);
