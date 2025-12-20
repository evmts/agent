-- Migration: Add topics column to repositories table
-- Date: 2025-12-19

-- Add topics column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'repositories' AND column_name = 'topics'
  ) THEN
    ALTER TABLE repositories ADD COLUMN topics TEXT[] DEFAULT '{}';
  END IF;
END $$;

-- Create index for topic searches (GIN index for array operations)
CREATE INDEX IF NOT EXISTS idx_repositories_topics ON repositories USING GIN (topics);
