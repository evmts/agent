-- Fix race condition in issue number assignment
-- Add atomic counter to repositories table and create helper function

-- Add next_issue_number counter to repositories
ALTER TABLE repositories
ADD COLUMN IF NOT EXISTS next_issue_number INTEGER NOT NULL DEFAULT 1;

-- Initialize next_issue_number based on existing issues
UPDATE repositories r
SET next_issue_number = COALESCE((
  SELECT MAX(issue_number) + 1
  FROM issues
  WHERE repository_id = r.id
), 1);

-- Create atomic function to get next issue number
-- This function atomically increments and returns the next issue number for a repository
-- Prevents race conditions where two concurrent requests could get the same issue number
CREATE OR REPLACE FUNCTION get_next_issue_number(repo_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  next_num INTEGER;
BEGIN
  -- Atomically increment and return the next issue number
  -- The UPDATE statement locks the row, preventing concurrent access
  UPDATE repositories
  SET next_issue_number = next_issue_number + 1
  WHERE id = repo_id
  RETURNING next_issue_number - 1 INTO next_num;

  IF next_num IS NULL THEN
    RAISE EXCEPTION 'Repository % not found', repo_id;
  END IF;

  RETURN next_num;
END;
$$;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_repositories_next_issue_number
ON repositories(id, next_issue_number);
