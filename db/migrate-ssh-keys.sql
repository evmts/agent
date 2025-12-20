-- SSH Keys for Git over SSH authentication
-- Migration for SSH public key authentication

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

-- Index for fast fingerprint lookup during SSH auth
CREATE INDEX IF NOT EXISTS idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);
CREATE INDEX IF NOT EXISTS idx_ssh_keys_user_id ON ssh_keys(user_id);

-- Also add to schema.sql by appending:
-- (This is for reference, the table is created by this migration)
