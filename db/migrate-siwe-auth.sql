-- Migration: Replace password auth with SIWE (Sign In With Ethereum)
-- Run this AFTER backing up your database

-- Step 1: Add wallet_address column
ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_address VARCHAR(42) UNIQUE;
CREATE INDEX IF NOT EXISTS idx_users_wallet_address ON users(wallet_address);

-- Step 2: Make email optional (SIWE doesn't require email)
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN lower_email DROP NOT NULL;

-- Step 3: Remove password-related columns
ALTER TABLE users DROP COLUMN IF EXISTS password_hash;
ALTER TABLE users DROP COLUMN IF EXISTS password_algo;
ALTER TABLE users DROP COLUMN IF EXISTS salt;
ALTER TABLE users DROP COLUMN IF EXISTS must_change_password;

-- Step 4: Create SIWE nonces table for replay attack prevention
CREATE TABLE IF NOT EXISTS siwe_nonces (
  nonce VARCHAR(64) PRIMARY KEY,
  wallet_address VARCHAR(42),
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL,
  used_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_siwe_nonces_expires ON siwe_nonces(expires_at);
CREATE INDEX IF NOT EXISTS idx_siwe_nonces_wallet ON siwe_nonces(wallet_address);

-- Step 5: Clean up email verification tokens (no longer needed for auth)
DROP TABLE IF EXISTS email_verification_tokens;

-- Step 6: Update existing seed users to have NULL wallet_address
UPDATE users SET wallet_address = NULL WHERE wallet_address IS NULL;
