# Security Features Implementation

## Overview

Implement comprehensive security features for Plue, including two-factor authentication (TOTP), GPG key management for signed commits, SSH key management with deploy keys, API token scopes, and audit logging. This transforms Plue into a security-hardened Git platform with enterprise-grade authentication and activity tracking.

**Scope:**
- Two-factor authentication (TOTP) with QR code enrollment
- GPG key management (add, verify, delete keys)
- Signed commit verification display in UI
- SSH key management (user keys and deploy keys)
- Deploy keys with read-only/read-write permissions
- API token scopes (fine-grained permissions)
- Audit logs (login attempts, key changes, security events)
- Security settings dashboard
- Recovery codes for 2FA

**Out of scope (future features):**
- WebAuthn/FIDO2 (passkeys)
- Hardware security keys (YubiKey)
- OAuth2 scopes
- IP allowlisting/denylisting
- Advanced audit log filtering/export

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server with middleware
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL with `postgres` client
- **Validation**: Zod v4
- **TOTP**: `otpauth` (TOTP generation/validation)
- **GPG**: `openpgp` (GPG key parsing/verification)
- **SSH**: `ssh2` (SSH key parsing/fingerprinting)
- **QR Codes**: `qrcode` (2FA enrollment QR codes)

## Research Reference

This implementation is based on Gitea's security features. Key reference files:

**TOTP/2FA:**
- `/Users/williamcory/plue/gitea/models/auth/twofactor.go` - TOTP model with encrypted secrets
- Scratch tokens for recovery (10 random chars, PBKDF2 hashed)
- AES encryption for TOTP secrets
- Passcode validation with replay prevention

**GPG Keys:**
- `/Users/williamcory/plue/gitea/models/asymkey/gpg_key.go` - GPG key model
- Key verification against user emails
- Subkey support
- Expiry tracking
- Capability flags (sign, encrypt, certify)

**SSH Keys:**
- `/Users/williamcory/plue/gitea/models/asymkey/ssh_key.go` - SSH key model
- Fingerprint calculation
- Deploy keys (read-only SSH keys for repos)
- Key activity tracking

**Access Token Scopes:**
- `/Users/williamcory/plue/gitea/models/auth/access_token_scope.go` - Fine-grained scopes
- Bitmap-based permission checking
- Scope categories: admin, repo, issue, org, user, package, notification

**Security UI:**
- `/Users/williamcory/plue/gitea/routers/web/user/setting/security/security.go` - Security settings page
- Lists all 2FA methods, keys, and tokens

## Database Schema Changes

### 1. TOTP credentials table

**File**: `/Users/williamcory/plue/db/schema.sql`

Add after the `users` table:

```sql
-- Two-factor authentication (TOTP)
CREATE TABLE IF NOT EXISTS totp_credentials (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Encrypted TOTP secret (AES-256-GCM)
  secret_encrypted TEXT NOT NULL,
  secret_iv VARCHAR(32) NOT NULL, -- initialization vector

  -- Recovery/scratch token (hashed with PBKDF2)
  scratch_salt VARCHAR(32) NOT NULL,
  scratch_hash VARCHAR(128) NOT NULL,

  -- Replay prevention
  last_used_passcode VARCHAR(10),

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_totp_credentials_user_id ON totp_credentials(user_id);
```

**Notes:**
- Secret is AES-encrypted at rest (use `PLUE_SECRET_KEY` env var as master key)
- Scratch token is a recovery code (shown once during enrollment)
- `last_used_passcode` prevents replay attacks

### 2. GPG keys table

```sql
-- GPG keys for signed commits
CREATE TABLE IF NOT EXISTS gpg_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Key identification
  key_id VARCHAR(16) NOT NULL, -- 16-char hex key ID
  primary_key_id VARCHAR(16), -- NULL for primary keys, set for subkeys
  fingerprint VARCHAR(40) NOT NULL, -- 40-char hex fingerprint

  -- Key content (armored public key)
  content TEXT NOT NULL,

  -- Key metadata
  expires_at TIMESTAMP,
  is_verified BOOLEAN NOT NULL DEFAULT false,

  -- Key capabilities
  can_sign BOOLEAN NOT NULL DEFAULT false,
  can_encrypt_comms BOOLEAN NOT NULL DEFAULT false,
  can_encrypt_storage BOOLEAN NOT NULL DEFAULT false,
  can_certify BOOLEAN NOT NULL DEFAULT false,

  created_at TIMESTAMP DEFAULT NOW(),
  added_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(key_id),
  UNIQUE(fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_gpg_keys_user_id ON gpg_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_gpg_keys_key_id ON gpg_keys(key_id);
CREATE INDEX IF NOT EXISTS idx_gpg_keys_fingerprint ON gpg_keys(fingerprint);

-- GPG key email associations (verify key emails match user emails)
CREATE TABLE IF NOT EXISTS gpg_key_emails (
  id SERIAL PRIMARY KEY,
  gpg_key_id INTEGER NOT NULL REFERENCES gpg_keys(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gpg_key_emails_key_id ON gpg_key_emails(gpg_key_id);
```

**Notes:**
- Store full armored public key in `content`
- `primary_key_id` links subkeys to their primary key
- Verify emails in key match user's verified emails
- Mark key `is_verified` only if emails match

### 3. SSH keys and deploy keys

```sql
-- SSH public keys (user keys)
CREATE TABLE IF NOT EXISTS ssh_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  name VARCHAR(255) NOT NULL, -- user-defined name
  fingerprint VARCHAR(128) NOT NULL, -- SHA256 fingerprint
  content TEXT NOT NULL, -- full SSH public key

  key_type VARCHAR(50) NOT NULL, -- 'user' or 'principal'

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_used_at TIMESTAMP,

  UNIQUE(fingerprint),
  UNIQUE(user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_ssh_keys_user_id ON ssh_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);

-- Deploy keys (read-only SSH keys for CI/CD)
CREATE TABLE IF NOT EXISTS deploy_keys (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,

  name VARCHAR(255) NOT NULL, -- user-defined name
  fingerprint VARCHAR(128) NOT NULL, -- SHA256 fingerprint
  content TEXT NOT NULL, -- full SSH public key

  -- Access mode
  is_read_only BOOLEAN NOT NULL DEFAULT true,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_used_at TIMESTAMP,

  UNIQUE(fingerprint),
  UNIQUE(repository_id, name)
);

CREATE INDEX IF NOT EXISTS idx_deploy_keys_repository_id ON deploy_keys(repository_id);
CREATE INDEX IF NOT EXISTS idx_deploy_keys_fingerprint ON deploy_keys(fingerprint);
```

**Notes:**
- Deploy keys are per-repository (not per-user)
- `is_read_only` controls whether key can push
- Same fingerprint can't be used twice (globally unique)

### 4. Update access tokens with scopes

Extend the existing `access_tokens` table (from 01_authentication.md):

```sql
-- Update access_tokens table to add scope support
ALTER TABLE access_tokens
  ADD COLUMN IF NOT EXISTS scope VARCHAR(512) NOT NULL DEFAULT 'all';

-- Add scope index for filtering
CREATE INDEX IF NOT EXISTS idx_access_tokens_scope ON access_tokens(scope);
```

**Scope format:**
- Comma-separated scope strings: `"read:repo,write:issue,read:org"`
- Special scopes: `"all"` (full access), `"public-only"` (public repos only)
- Categories: `admin`, `repo`, `issue`, `org`, `user`, `notification`
- Levels: `read:category`, `write:category` (write implies read)

### 5. Audit logs table

```sql
-- Audit logs for security events
CREATE TABLE IF NOT EXISTS audit_logs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,

  -- Event identification
  action VARCHAR(100) NOT NULL, -- e.g., 'login.success', 'key.add', '2fa.enable'
  category VARCHAR(50) NOT NULL, -- 'auth', 'key', 'security', 'admin'

  -- Event details
  ip_address INET,
  user_agent TEXT,
  metadata JSONB, -- additional context (key fingerprint, etc.)

  -- Result
  success BOOLEAN NOT NULL DEFAULT true,
  error_message TEXT,

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_category ON audit_logs(category);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);
```

**Common audit events:**
- `login.success`, `login.failure`, `login.2fa_success`, `login.2fa_failure`
- `2fa.enable`, `2fa.disable`, `2fa.recovery_used`
- `key.ssh.add`, `key.ssh.delete`, `key.gpg.add`, `key.gpg.delete`
- `key.deploy.add`, `key.deploy.delete`
- `token.create`, `token.delete`, `token.update`
- `password.change`, `email.add`, `email.verify`

## Backend Implementation

### 1. Database utilities

**File**: `/Users/williamcory/plue/db/security.ts` (new)

```typescript
import postgres from 'postgres';
import { getDb } from './index';

// ============================================================================
// TOTP Credentials
// ============================================================================

export interface TotpCredential {
  id: number;
  user_id: number;
  secret_encrypted: string;
  secret_iv: string;
  scratch_salt: string;
  scratch_hash: string;
  last_used_passcode: string | null;
  created_at: Date;
  updated_at: Date;
}

export async function getTotpCredentialByUserId(userId: number): Promise<TotpCredential | null> {
  const db = getDb();
  const [row] = await db`
    SELECT * FROM totp_credentials WHERE user_id = ${userId}
  `;
  return row || null;
}

export async function createTotpCredential(data: {
  user_id: number;
  secret_encrypted: string;
  secret_iv: string;
  scratch_salt: string;
  scratch_hash: string;
}): Promise<TotpCredential> {
  const db = getDb();
  const [row] = await db`
    INSERT INTO totp_credentials (user_id, secret_encrypted, secret_iv, scratch_salt, scratch_hash)
    VALUES (${data.user_id}, ${data.secret_encrypted}, ${data.secret_iv}, ${data.scratch_salt}, ${data.scratch_hash})
    RETURNING *
  `;
  return row;
}

export async function updateTotpLastUsedPasscode(userId: number, passcode: string): Promise<void> {
  const db = getDb();
  await db`
    UPDATE totp_credentials
    SET last_used_passcode = ${passcode}, updated_at = NOW()
    WHERE user_id = ${userId}
  `;
}

export async function deleteTotpCredential(userId: number): Promise<void> {
  const db = getDb();
  await db`DELETE FROM totp_credentials WHERE user_id = ${userId}`;
}

// ============================================================================
// GPG Keys
// ============================================================================

export interface GpgKey {
  id: number;
  user_id: number;
  key_id: string;
  primary_key_id: string | null;
  fingerprint: string;
  content: string;
  expires_at: Date | null;
  is_verified: boolean;
  can_sign: boolean;
  can_encrypt_comms: boolean;
  can_encrypt_storage: boolean;
  can_certify: boolean;
  created_at: Date;
  added_at: Date;
}

export async function getGpgKeysByUserId(userId: number): Promise<GpgKey[]> {
  const db = getDb();
  return await db`
    SELECT * FROM gpg_keys
    WHERE user_id = ${userId} AND primary_key_id IS NULL
    ORDER BY created_at DESC
  `;
}

export async function getGpgKeyById(id: number, userId: number): Promise<GpgKey | null> {
  const db = getDb();
  const [row] = await db`
    SELECT * FROM gpg_keys WHERE id = ${id} AND user_id = ${userId}
  `;
  return row || null;
}

export async function createGpgKey(data: Omit<GpgKey, 'id' | 'created_at' | 'added_at'>): Promise<GpgKey> {
  const db = getDb();
  const [row] = await db`
    INSERT INTO gpg_keys (
      user_id, key_id, primary_key_id, fingerprint, content,
      expires_at, is_verified, can_sign, can_encrypt_comms,
      can_encrypt_storage, can_certify
    )
    VALUES (
      ${data.user_id}, ${data.key_id}, ${data.primary_key_id}, ${data.fingerprint},
      ${data.content}, ${data.expires_at}, ${data.is_verified}, ${data.can_sign},
      ${data.can_encrypt_comms}, ${data.can_encrypt_storage}, ${data.can_certify}
    )
    RETURNING *
  `;
  return row;
}

export async function deleteGpgKey(id: number, userId: number): Promise<void> {
  const db = getDb();
  await db`DELETE FROM gpg_keys WHERE id = ${id} AND user_id = ${userId}`;
}

// ============================================================================
// SSH Keys
// ============================================================================

export interface SshKey {
  id: number;
  user_id: number;
  name: string;
  fingerprint: string;
  content: string;
  key_type: string;
  created_at: Date;
  updated_at: Date;
  last_used_at: Date | null;
}

export async function getSshKeysByUserId(userId: number): Promise<SshKey[]> {
  const db = getDb();
  return await db`
    SELECT * FROM ssh_keys
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
  `;
}

export async function createSshKey(data: {
  user_id: number;
  name: string;
  fingerprint: string;
  content: string;
  key_type: string;
}): Promise<SshKey> {
  const db = getDb();
  const [row] = await db`
    INSERT INTO ssh_keys (user_id, name, fingerprint, content, key_type)
    VALUES (${data.user_id}, ${data.name}, ${data.fingerprint}, ${data.content}, ${data.key_type})
    RETURNING *
  `;
  return row;
}

export async function deleteSshKey(id: number, userId: number): Promise<void> {
  const db = getDb();
  await db`DELETE FROM ssh_keys WHERE id = ${id} AND user_id = ${userId}`;
}

// ============================================================================
// Deploy Keys
// ============================================================================

export interface DeployKey {
  id: number;
  repository_id: number;
  name: string;
  fingerprint: string;
  content: string;
  is_read_only: boolean;
  created_at: Date;
  updated_at: Date;
  last_used_at: Date | null;
}

export async function getDeployKeysByRepoId(repoId: number): Promise<DeployKey[]> {
  const db = getDb();
  return await db`
    SELECT * FROM deploy_keys
    WHERE repository_id = ${repoId}
    ORDER BY created_at DESC
  `;
}

export async function createDeployKey(data: {
  repository_id: number;
  name: string;
  fingerprint: string;
  content: string;
  is_read_only: boolean;
}): Promise<DeployKey> {
  const db = getDb();
  const [row] = await db`
    INSERT INTO deploy_keys (repository_id, name, fingerprint, content, is_read_only)
    VALUES (${data.repository_id}, ${data.name}, ${data.fingerprint}, ${data.content}, ${data.is_read_only})
    RETURNING *
  `;
  return row;
}

export async function deleteDeployKey(id: number, repoId: number): Promise<void> {
  const db = getDb();
  await db`DELETE FROM deploy_keys WHERE id = ${id} AND repository_id = ${repoId}`;
}

// ============================================================================
// Audit Logs
// ============================================================================

export interface AuditLog {
  id: number;
  user_id: number | null;
  action: string;
  category: string;
  ip_address: string | null;
  user_agent: string | null;
  metadata: Record<string, any> | null;
  success: boolean;
  error_message: string | null;
  created_at: Date;
}

export async function createAuditLog(data: {
  user_id?: number;
  action: string;
  category: string;
  ip_address?: string;
  user_agent?: string;
  metadata?: Record<string, any>;
  success?: boolean;
  error_message?: string;
}): Promise<void> {
  const db = getDb();
  await db`
    INSERT INTO audit_logs (user_id, action, category, ip_address, user_agent, metadata, success, error_message)
    VALUES (
      ${data.user_id ?? null},
      ${data.action},
      ${data.category},
      ${data.ip_address ?? null},
      ${data.user_agent ?? null},
      ${data.metadata ? db.json(data.metadata) : null},
      ${data.success ?? true},
      ${data.error_message ?? null}
    )
  `;
}

export async function getAuditLogsByUserId(userId: number, limit = 100): Promise<AuditLog[]> {
  const db = getDb();
  return await db`
    SELECT * FROM audit_logs
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
    LIMIT ${limit}
  `;
}

export async function getRecentAuditLogs(limit = 100): Promise<AuditLog[]> {
  const db = getDb();
  return await db`
    SELECT * FROM audit_logs
    ORDER BY created_at DESC
    LIMIT ${limit}
  `;
}
```

### 2. TOTP utilities

**File**: `/Users/williamcory/plue/server/lib/totp.ts` (new)

```typescript
import { Secret, TOTP, URI } from 'otpauth';
import crypto from 'crypto';

const TOTP_ISSUER = 'Plue';
const TOTP_PERIOD = 30; // 30 seconds
const TOTP_DIGITS = 6;
const TOTP_ALGORITHM = 'SHA1';

// Encryption key (derived from PLUE_SECRET_KEY env var)
function getEncryptionKey(): Buffer {
  const secretKey = process.env.PLUE_SECRET_KEY;
  if (!secretKey) {
    throw new Error('PLUE_SECRET_KEY environment variable not set');
  }
  // Use first 32 bytes of SHA256 hash as AES-256 key
  return crypto.createHash('sha256').update(secretKey).digest();
}

/**
 * Generate a new TOTP secret
 */
export function generateTotpSecret(): string {
  const secret = new Secret({ size: 20 }); // 160 bits
  return secret.base32;
}

/**
 * Encrypt TOTP secret with AES-256-GCM
 */
export function encryptTotpSecret(secret: string): { encrypted: string; iv: string } {
  const key = getEncryptionKey();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

  let encrypted = cipher.update(secret, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  const authTag = cipher.getAuthTag();

  return {
    encrypted: encrypted + ':' + authTag.toString('base64'),
    iv: iv.toString('hex'),
  };
}

/**
 * Decrypt TOTP secret
 */
export function decryptTotpSecret(encrypted: string, iv: string): string {
  const key = getEncryptionKey();
  const [ciphertext, authTagB64] = encrypted.split(':');
  const authTag = Buffer.from(authTagB64, 'base64');

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'hex'));
  decipher.setAuthTag(authTag);

  let decrypted = decipher.update(ciphertext, 'base64', 'utf8');
  decrypted += decipher.final('utf8');

  return decrypted;
}

/**
 * Generate TOTP URI for QR code
 */
export function generateTotpUri(secret: string, username: string): string {
  const totp = new TOTP({
    issuer: TOTP_ISSUER,
    label: username,
    algorithm: TOTP_ALGORITHM,
    digits: TOTP_DIGITS,
    period: TOTP_PERIOD,
    secret: Secret.fromBase32(secret),
  });
  return totp.toString();
}

/**
 * Validate TOTP passcode
 */
export function validateTotpPasscode(secret: string, passcode: string): boolean {
  const totp = new TOTP({
    algorithm: TOTP_ALGORITHM,
    digits: TOTP_DIGITS,
    period: TOTP_PERIOD,
    secret: Secret.fromBase32(secret),
  });

  // Allow 1 period (30s) window on either side for clock skew
  const delta = totp.validate({ token: passcode, window: 1 });
  return delta !== null;
}

/**
 * Generate recovery/scratch token (10 random chars)
 */
export function generateScratchToken(): string {
  // Use special chars to avoid ambiguity (no 0, O, 1, I)
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(6);
  let token = '';
  for (const byte of bytes) {
    token += chars[byte % chars.length];
  }
  return token;
}

/**
 * Hash scratch token with PBKDF2
 */
export function hashScratchToken(token: string, salt: string): string {
  const hash = crypto.pbkdf2Sync(token, salt, 10000, 50, 'sha256');
  return hash.toString('hex');
}

/**
 * Verify scratch token
 */
export function verifyScratchToken(token: string, salt: string, hash: string): boolean {
  const computedHash = hashScratchToken(token, salt);
  return crypto.timingSafeEqual(
    Buffer.from(computedHash, 'hex'),
    Buffer.from(hash, 'hex')
  );
}

/**
 * Generate salt for scratch token
 */
export function generateSalt(): string {
  return crypto.randomBytes(16).toString('hex');
}
```

### 3. GPG utilities

**File**: `/Users/williamcory/plue/server/lib/gpg.ts` (new)

```typescript
import * as openpgp from 'openpgp';

export interface ParsedGpgKey {
  keyId: string; // 16-char hex
  fingerprint: string; // 40-char hex
  content: string; // armored public key
  emails: string[];
  expiresAt: Date | null;
  canSign: boolean;
  canEncrypt: boolean;
  canCertify: boolean;
  subkeys: ParsedGpgKey[];
}

/**
 * Parse and validate armored GPG public key
 */
export async function parseGpgKey(armoredKey: string): Promise<ParsedGpgKey> {
  try {
    const publicKey = await openpgp.readKey({ armoredKey });
    const primaryKey = publicKey.getKeys()[0];

    if (!primaryKey) {
      throw new Error('No primary key found');
    }

    // Extract user IDs (emails)
    const emails: string[] = [];
    for (const user of publicKey.users) {
      if (user.userID?.email) {
        emails.push(user.userID.email.toLowerCase());
      }
    }

    // Get key capabilities
    const canSign = await primaryKey.isSigningKey();
    const canEncrypt = await primaryKey.isEncryptionKey();
    const canCertify = primaryKey.keyPacket.algorithm === openpgp.enums.publicKey.rsaSign ||
                       primaryKey.keyPacket.algorithm === openpgp.enums.publicKey.ecdsa ||
                       primaryKey.keyPacket.algorithm === openpgp.enums.publicKey.eddsa;

    // Get expiration
    let expiresAt: Date | null = null;
    const expirationTime = await primaryKey.getExpirationTime();
    if (expirationTime instanceof Date && !isNaN(expirationTime.getTime())) {
      expiresAt = expirationTime;
    }

    // Parse subkeys
    const subkeys: ParsedGpgKey[] = [];
    for (const subkey of publicKey.subkeys) {
      const subkeyPacket = subkey.keyPacket;
      const subkeyId = subkeyPacket.getKeyID().toHex().toUpperCase();
      const subkeyFingerprint = subkeyPacket.getFingerprint().toUpperCase();

      const subCanSign = await subkey.isSigningKey();
      const subCanEncrypt = await subkey.isEncryptionKey();

      let subExpiresAt: Date | null = null;
      const subExpirationTime = await subkey.getExpirationTime();
      if (subExpirationTime instanceof Date && !isNaN(subExpirationTime.getTime())) {
        subExpiresAt = subExpirationTime;
      }

      subkeys.push({
        keyId: subkeyId,
        fingerprint: subkeyFingerprint,
        content: '', // Subkeys don't have separate armored content
        emails: [],
        expiresAt: subExpiresAt,
        canSign: subCanSign,
        canEncrypt: subCanEncrypt,
        canCertify: false,
        subkeys: [],
      });
    }

    return {
      keyId: primaryKey.getKeyID().toHex().toUpperCase(),
      fingerprint: primaryKey.getFingerprint().toUpperCase(),
      content: armoredKey,
      emails,
      expiresAt,
      canSign,
      canEncrypt,
      canCertify,
      subkeys,
    };
  } catch (error) {
    throw new Error(`Invalid GPG key: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Verify GPG signed commit
 */
export async function verifyGpgSignature(
  content: string,
  signature: string,
  armoredPublicKey: string
): Promise<{ verified: boolean; keyId: string | null }> {
  try {
    const publicKey = await openpgp.readKey({ armoredKey: armoredPublicKey });
    const message = await openpgp.readCleartextMessage({ cleartextMessage: content });
    const verificationResult = await openpgp.verify({
      message,
      signature: await openpgp.readSignature({ armoredSignature: signature }),
      verificationKeys: publicKey,
    });

    const { verified, keyID } = verificationResult.signatures[0];
    await verified;

    return {
      verified: true,
      keyId: keyID.toHex().toUpperCase(),
    };
  } catch (error) {
    return {
      verified: false,
      keyId: null,
    };
  }
}

/**
 * Format key ID with padding (Gitea-style)
 */
export function padKeyId(keyId: string): string {
  if (keyId.length >= 16) {
    return keyId;
  }
  return '0'.repeat(16 - keyId.length) + keyId;
}
```

### 4. SSH utilities

**File**: `/Users/williamcory/plue/server/lib/ssh.ts` (new)

```typescript
import { parseKey } from 'ssh2';
import crypto from 'crypto';

export interface ParsedSshKey {
  type: string; // 'ssh-rsa', 'ssh-ed25519', etc.
  fingerprint: string; // SHA256 fingerprint
  content: string; // full SSH public key
  comment: string; // optional comment
}

/**
 * Parse and validate SSH public key
 */
export function parseSshKey(content: string): ParsedSshKey {
  try {
    const parsed = parseKey(content);

    if (parsed instanceof Error) {
      throw parsed;
    }

    if (!parsed || parsed.type !== 'ssh') {
      throw new Error('Invalid SSH public key');
    }

    // Calculate SHA256 fingerprint
    const pubKey = parsed.getPublicSSH();
    const hash = crypto.createHash('sha256').update(pubKey).digest('base64');
    const fingerprint = `SHA256:${hash.replace(/=+$/, '')}`;

    // Extract type and comment
    const parts = content.trim().split(/\s+/);
    const type = parts[0] || 'unknown';
    const comment = parts.slice(2).join(' ') || '';

    return {
      type,
      fingerprint,
      content: content.trim(),
      comment,
    };
  } catch (error) {
    throw new Error(`Invalid SSH key: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Validate SSH key type (only allow secure algorithms)
 */
export function isValidSshKeyType(type: string): boolean {
  const allowedTypes = [
    'ssh-rsa',
    'ssh-ed25519',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
  ];
  return allowedTypes.includes(type);
}
```

### 5. Token scope utilities

**File**: `/Users/williamcory/plue/server/lib/token-scopes.ts` (new)

```typescript
/**
 * Access token scope utilities
 * Based on Gitea's bitmap-based scope system
 */

export type ScopeCategory =
  | 'admin'
  | 'repo'
  | 'issue'
  | 'org'
  | 'user'
  | 'notification';

export type ScopeLevel = 'read' | 'write';

export type AccessTokenScope =
  | 'all'
  | 'public-only'
  | `${ScopeLevel}:${ScopeCategory}`;

/**
 * All available scopes
 */
export const ALL_SCOPES: AccessTokenScope[] = [
  'all',
  'public-only',
  'read:admin', 'write:admin',
  'read:repo', 'write:repo',
  'read:issue', 'write:issue',
  'read:org', 'write:org',
  'read:user', 'write:user',
  'read:notification', 'write:notification',
];

/**
 * Scope hierarchy (write implies read)
 */
const SCOPE_HIERARCHY: Record<string, string[]> = {
  'all': ALL_SCOPES.filter(s => s !== 'all' && s !== 'public-only'),
  'write:admin': ['read:admin'],
  'write:repo': ['read:repo'],
  'write:issue': ['read:issue'],
  'write:org': ['read:org'],
  'write:user': ['read:user'],
  'write:notification': ['read:notification'],
};

/**
 * Parse scope string into array
 */
export function parseScopes(scopeString: string): AccessTokenScope[] {
  if (!scopeString || scopeString.trim() === '') {
    return [];
  }
  return scopeString.split(',').map(s => s.trim()) as AccessTokenScope[];
}

/**
 * Expand scopes based on hierarchy (e.g., write:repo includes read:repo)
 */
export function expandScopes(scopes: AccessTokenScope[]): Set<AccessTokenScope> {
  const expanded = new Set<AccessTokenScope>();

  for (const scope of scopes) {
    expanded.add(scope);

    // Add implied scopes
    const implied = SCOPE_HIERARCHY[scope];
    if (implied) {
      for (const impliedScope of implied) {
        expanded.add(impliedScope as AccessTokenScope);
      }
    }
  }

  return expanded;
}

/**
 * Check if token has required scope
 */
export function hasScope(
  tokenScopes: string,
  requiredScope: AccessTokenScope
): boolean {
  const scopes = parseScopes(tokenScopes);
  const expanded = expandScopes(scopes);

  return expanded.has(requiredScope);
}

/**
 * Check if token has any of the required scopes
 */
export function hasAnyScope(
  tokenScopes: string,
  requiredScopes: AccessTokenScope[]
): boolean {
  return requiredScopes.some(scope => hasScope(tokenScopes, scope));
}

/**
 * Validate scope string
 */
export function validateScopes(scopeString: string): { valid: boolean; error?: string } {
  const scopes = parseScopes(scopeString);

  for (const scope of scopes) {
    if (!ALL_SCOPES.includes(scope)) {
      return {
        valid: false,
        error: `Invalid scope: ${scope}`,
      };
    }
  }

  return { valid: true };
}

/**
 * Normalize scope string (remove duplicates, sort)
 */
export function normalizeScopes(scopeString: string): string {
  const scopes = parseScopes(scopeString);
  const expanded = expandScopes(scopes);

  // Remove redundant scopes (if we have 'all', we don't need anything else)
  if (expanded.has('all')) {
    return 'all';
  }

  // Sort and join
  return Array.from(expanded).sort().join(',');
}

/**
 * Get human-readable scope descriptions
 */
export function getScopeDescription(scope: AccessTokenScope): string {
  const descriptions: Record<AccessTokenScope, string> = {
    'all': 'Full access to all resources',
    'public-only': 'Limited to public repositories and organizations',
    'read:admin': 'Read admin information',
    'write:admin': 'Manage admin settings',
    'read:repo': 'Read repository content',
    'write:repo': 'Push to repositories',
    'read:issue': 'Read issues and pull requests',
    'write:issue': 'Create and modify issues',
    'read:org': 'Read organization information',
    'write:org': 'Manage organizations',
    'read:user': 'Read user profile',
    'write:user': 'Update user profile',
    'read:notification': 'Read notifications',
    'write:notification': 'Mark notifications as read',
  };
  return descriptions[scope] || 'Unknown scope';
}
```

### 6. API routes

**File**: `/Users/williamcory/plue/server/routes/security.ts` (new)

```typescript
import { Hono } from 'hono';
import QRCode from 'qrcode';
import { z } from 'zod';
import {
  getTotpCredentialByUserId,
  createTotpCredential,
  deleteTotpCredential,
  updateTotpLastUsedPasscode,
  getGpgKeysByUserId,
  createGpgKey,
  deleteGpgKey,
  getSshKeysByUserId,
  createSshKey,
  deleteSshKey,
  getDeployKeysByRepoId,
  createDeployKey,
  deleteDeployKey,
  createAuditLog,
  getAuditLogsByUserId,
} from '../../db/security';
import {
  generateTotpSecret,
  encryptTotpSecret,
  decryptTotpSecret,
  generateTotpUri,
  validateTotpPasscode,
  generateScratchToken,
  hashScratchToken,
  verifyScratchToken,
  generateSalt,
} from '../lib/totp';
import { parseGpgKey } from '../lib/gpg';
import { parseSshKey, isValidSshKeyType } from '../lib/ssh';

const app = new Hono();

// Validation schemas
const EnableTotpSchema = z.object({
  passcode: z.string().length(6),
});

const VerifyTotpSchema = z.object({
  passcode: z.string().length(6),
});

const RecoverWithScratchSchema = z.object({
  scratch_token: z.string().length(10),
});

const AddGpgKeySchema = z.object({
  content: z.string().min(100),
});

const AddSshKeySchema = z.object({
  name: z.string().min(1).max(255),
  content: z.string().min(50),
});

const AddDeployKeySchema = z.object({
  name: z.string().min(1).max(255),
  content: z.string().min(50),
  is_read_only: z.boolean().default(true),
});

// ============================================================================
// TOTP / 2FA Routes
// ============================================================================

// GET /api/security/2fa/enroll - Start 2FA enrollment (generate QR code)
app.get('/2fa/enroll', async (c) => {
  const userId = c.get('userId'); // From auth middleware

  // Check if already enrolled
  const existing = await getTotpCredentialByUserId(userId);
  if (existing) {
    return c.json({ error: 'Already enrolled in 2FA' }, 400);
  }

  // Generate secret and QR code
  const secret = generateTotpSecret();
  const user = c.get('user'); // From auth middleware
  const uri = generateTotpUri(secret, user.username);
  const qrCode = await QRCode.toDataURL(uri);

  // Store secret in session temporarily (not DB yet)
  c.get('session').totp_secret = secret;

  return c.json({
    secret,
    qr_code: qrCode,
    uri,
  });
});

// POST /api/security/2fa/enable - Complete 2FA enrollment
app.post('/2fa/enable', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json();
  const { passcode } = EnableTotpSchema.parse(body);

  // Get secret from session
  const secret = c.get('session').totp_secret;
  if (!secret) {
    return c.json({ error: 'No enrollment in progress' }, 400);
  }

  // Validate passcode
  if (!validateTotpPasscode(secret, passcode)) {
    return c.json({ error: 'Invalid passcode' }, 400);
  }

  // Encrypt secret
  const { encrypted, iv } = encryptTotpSecret(secret);

  // Generate scratch token
  const scratchToken = generateScratchToken();
  const scratchSalt = generateSalt();
  const scratchHash = hashScratchToken(scratchToken, scratchSalt);

  // Save to database
  await createTotpCredential({
    user_id: userId,
    secret_encrypted: encrypted,
    secret_iv: iv,
    scratch_salt: scratchSalt,
    scratch_hash: scratchHash,
  });

  // Log event
  await createAuditLog({
    user_id: userId,
    action: '2fa.enable',
    category: 'security',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    success: true,
  });

  // Clear session secret
  delete c.get('session').totp_secret;

  return c.json({
    success: true,
    scratch_token: scratchToken, // Show once!
  });
});

// POST /api/security/2fa/verify - Verify TOTP passcode (for login)
app.post('/2fa/verify', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json();
  const { passcode } = VerifyTotpSchema.parse(body);

  const credential = await getTotpCredentialByUserId(userId);
  if (!credential) {
    return c.json({ error: 'Not enrolled in 2FA' }, 400);
  }

  // Check for replay
  if (credential.last_used_passcode === passcode) {
    await createAuditLog({
      user_id: userId,
      action: '2fa.replay_attempt',
      category: 'security',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      success: false,
    });
    return c.json({ error: 'Passcode already used' }, 400);
  }

  // Decrypt secret
  const secret = decryptTotpSecret(credential.secret_encrypted, credential.secret_iv);

  // Validate
  const valid = validateTotpPasscode(secret, passcode);

  if (valid) {
    // Update last used passcode
    await updateTotpLastUsedPasscode(userId, passcode);

    await createAuditLog({
      user_id: userId,
      action: '2fa.success',
      category: 'auth',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      success: true,
    });
  } else {
    await createAuditLog({
      user_id: userId,
      action: '2fa.failure',
      category: 'auth',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      success: false,
    });
  }

  return c.json({ valid });
});

// POST /api/security/2fa/recover - Recover with scratch token
app.post('/2fa/recover', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json();
  const { scratch_token } = RecoverWithScratchSchema.parse(body);

  const credential = await getTotpCredentialByUserId(userId);
  if (!credential) {
    return c.json({ error: 'Not enrolled in 2FA' }, 400);
  }

  // Verify scratch token
  const valid = verifyScratchToken(
    scratch_token,
    credential.scratch_salt,
    credential.scratch_hash
  );

  if (!valid) {
    await createAuditLog({
      user_id: userId,
      action: '2fa.recovery_failure',
      category: 'security',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      success: false,
    });
    return c.json({ error: 'Invalid recovery token' }, 400);
  }

  // Disable 2FA (user will need to re-enroll)
  await deleteTotpCredential(userId);

  await createAuditLog({
    user_id: userId,
    action: '2fa.recovery_used',
    category: 'security',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    success: true,
  });

  return c.json({ success: true });
});

// DELETE /api/security/2fa - Disable 2FA
app.delete('/2fa', async (c) => {
  const userId = c.get('userId');

  await deleteTotpCredential(userId);

  await createAuditLog({
    user_id: userId,
    action: '2fa.disable',
    category: 'security',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    success: true,
  });

  return c.json({ success: true });
});

// ============================================================================
// GPG Key Routes
// ============================================================================

// GET /api/security/gpg - List GPG keys
app.get('/gpg', async (c) => {
  const userId = c.get('userId');
  const keys = await getGpgKeysByUserId(userId);
  return c.json({ keys });
});

// POST /api/security/gpg - Add GPG key
app.post('/gpg', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json();
  const { content } = AddGpgKeySchema.parse(body);

  try {
    // Parse GPG key
    const parsed = await parseGpgKey(content);

    // Verify emails match user's verified emails
    // (In real implementation, check against email_addresses table)
    const userEmails = ['user@example.com']; // TODO: Get from DB
    const verified = parsed.emails.some(email => userEmails.includes(email));

    // Create key
    const key = await createGpgKey({
      user_id: userId,
      key_id: parsed.keyId,
      primary_key_id: null,
      fingerprint: parsed.fingerprint,
      content: parsed.content,
      expires_at: parsed.expiresAt,
      is_verified: verified,
      can_sign: parsed.canSign,
      can_encrypt_comms: parsed.canEncrypt,
      can_encrypt_storage: parsed.canEncrypt,
      can_certify: parsed.canCertify,
    });

    await createAuditLog({
      user_id: userId,
      action: 'key.gpg.add',
      category: 'key',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      metadata: { key_id: parsed.keyId, fingerprint: parsed.fingerprint },
      success: true,
    });

    return c.json({ key });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : 'Invalid key' }, 400);
  }
});

// DELETE /api/security/gpg/:id - Delete GPG key
app.delete('/gpg/:id', async (c) => {
  const userId = c.get('userId');
  const id = parseInt(c.req.param('id'));

  await deleteGpgKey(id, userId);

  await createAuditLog({
    user_id: userId,
    action: 'key.gpg.delete',
    category: 'key',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    metadata: { key_id: id },
    success: true,
  });

  return c.json({ success: true });
});

// ============================================================================
// SSH Key Routes
// ============================================================================

// GET /api/security/ssh - List SSH keys
app.get('/ssh', async (c) => {
  const userId = c.get('userId');
  const keys = await getSshKeysByUserId(userId);
  return c.json({ keys });
});

// POST /api/security/ssh - Add SSH key
app.post('/ssh', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json();
  const { name, content } = AddSshKeySchema.parse(body);

  try {
    // Parse SSH key
    const parsed = parseSshKey(content);

    // Validate key type
    if (!isValidSshKeyType(parsed.type)) {
      return c.json({ error: `Unsupported key type: ${parsed.type}` }, 400);
    }

    // Create key
    const key = await createSshKey({
      user_id: userId,
      name,
      fingerprint: parsed.fingerprint,
      content: parsed.content,
      key_type: 'user',
    });

    await createAuditLog({
      user_id: userId,
      action: 'key.ssh.add',
      category: 'key',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      metadata: { name, fingerprint: parsed.fingerprint },
      success: true,
    });

    return c.json({ key });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : 'Invalid key' }, 400);
  }
});

// DELETE /api/security/ssh/:id - Delete SSH key
app.delete('/ssh/:id', async (c) => {
  const userId = c.get('userId');
  const id = parseInt(c.req.param('id'));

  await deleteSshKey(id, userId);

  await createAuditLog({
    user_id: userId,
    action: 'key.ssh.delete',
    category: 'key',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    metadata: { key_id: id },
    success: true,
  });

  return c.json({ success: true });
});

// ============================================================================
// Deploy Key Routes
// ============================================================================

// GET /api/repos/:repoId/deploy-keys - List deploy keys
app.get('/repos/:repoId/deploy-keys', async (c) => {
  const repoId = parseInt(c.req.param('repoId'));
  // TODO: Check user has access to repo

  const keys = await getDeployKeysByRepoId(repoId);
  return c.json({ keys });
});

// POST /api/repos/:repoId/deploy-keys - Add deploy key
app.post('/repos/:repoId/deploy-keys', async (c) => {
  const userId = c.get('userId');
  const repoId = parseInt(c.req.param('repoId'));
  const body = await c.req.json();
  const { name, content, is_read_only } = AddDeployKeySchema.parse(body);

  try {
    // Parse SSH key
    const parsed = parseSshKey(content);

    // Validate key type
    if (!isValidSshKeyType(parsed.type)) {
      return c.json({ error: `Unsupported key type: ${parsed.type}` }, 400);
    }

    // Create key
    const key = await createDeployKey({
      repository_id: repoId,
      name,
      fingerprint: parsed.fingerprint,
      content: parsed.content,
      is_read_only,
    });

    await createAuditLog({
      user_id: userId,
      action: 'key.deploy.add',
      category: 'key',
      ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
      user_agent: c.req.header('user-agent'),
      metadata: { repo_id: repoId, name, fingerprint: parsed.fingerprint },
      success: true,
    });

    return c.json({ key });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : 'Invalid key' }, 400);
  }
});

// DELETE /api/repos/:repoId/deploy-keys/:id - Delete deploy key
app.delete('/repos/:repoId/deploy-keys/:id', async (c) => {
  const userId = c.get('userId');
  const repoId = parseInt(c.req.param('repoId'));
  const id = parseInt(c.req.param('id'));

  await deleteDeployKey(id, repoId);

  await createAuditLog({
    user_id: userId,
    action: 'key.deploy.delete',
    category: 'key',
    ip_address: c.req.header('x-forwarded-for') || c.req.header('x-real-ip'),
    user_agent: c.req.header('user-agent'),
    metadata: { repo_id: repoId, key_id: id },
    success: true,
  });

  return c.json({ success: true });
});

// ============================================================================
// Audit Log Routes
// ============================================================================

// GET /api/security/audit-logs - Get audit logs for current user
app.get('/audit-logs', async (c) => {
  const userId = c.get('userId');
  const limit = parseInt(c.req.query('limit') || '100');

  const logs = await getAuditLogsByUserId(userId, limit);
  return c.json({ logs });
});

export default app;
```

### 7. Update server routes index

**File**: `/Users/williamcory/plue/server/routes/index.ts`

Add security routes:

```typescript
import security from './security';

// ... existing code ...

app.route('/api/security', security);
```

## Frontend Implementation

### 1. Security settings page

**File**: `/Users/williamcory/plue/ui/pages/settings/security.astro` (new)

```astro
---
import Layout from '../../layouts/Layout.astro';

// TODO: Fetch from API (requires auth)
const user = {
  username: 'evilrabbit',
  has_2fa: false,
};

const gpgKeys = [];
const sshKeys = [];
const auditLogs = [];
---

<Layout title="Security Settings">
  <div class="container">
    <h1>Security Settings</h1>

    <!-- Two-Factor Authentication -->
    <section class="section">
      <h2>Two-Factor Authentication (2FA)</h2>

      {user.has_2fa ? (
        <div>
          <p>✓ 2FA is enabled for your account</p>
          <button id="disable-2fa" class="btn btn-danger">Disable 2FA</button>
        </div>
      ) : (
        <div>
          <p>Add an extra layer of security with TOTP-based 2FA</p>
          <button id="enable-2fa" class="btn btn-primary">Enable 2FA</button>
        </div>
      )}
    </section>

    <!-- GPG Keys -->
    <section class="section">
      <h2>GPG Keys</h2>
      <p>Manage GPG keys for signing commits</p>

      <div id="gpg-keys">
        {gpgKeys.length === 0 ? (
          <p>No GPG keys added</p>
        ) : (
          <ul>
            {gpgKeys.map((key: any) => (
              <li>
                <code>{key.key_id}</code> - {key.fingerprint}
                <button class="btn-delete-gpg" data-id={key.id}>Delete</button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <button id="add-gpg-key" class="btn btn-primary">Add GPG Key</button>
    </section>

    <!-- SSH Keys -->
    <section class="section">
      <h2>SSH Keys</h2>
      <p>Manage SSH keys for Git operations</p>

      <div id="ssh-keys">
        {sshKeys.length === 0 ? (
          <p>No SSH keys added</p>
        ) : (
          <ul>
            {sshKeys.map((key: any) => (
              <li>
                <strong>{key.name}</strong> - <code>{key.fingerprint}</code>
                <button class="btn-delete-ssh" data-id={key.id}>Delete</button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <button id="add-ssh-key" class="btn btn-primary">Add SSH Key</button>
    </section>

    <!-- Audit Logs -->
    <section class="section">
      <h2>Recent Activity</h2>

      <table>
        <thead>
          <tr>
            <th>Action</th>
            <th>IP Address</th>
            <th>Time</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {auditLogs.length === 0 ? (
            <tr><td colspan="4">No recent activity</td></tr>
          ) : (
            auditLogs.map((log: any) => (
              <tr>
                <td>{log.action}</td>
                <td>{log.ip_address || '-'}</td>
                <td>{new Date(log.created_at).toLocaleString()}</td>
                <td>{log.success ? '✓' : '✗'}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </section>
  </div>
</Layout>

<style>
  .container {
    max-width: 900px;
    margin: 0 auto;
    padding: 2rem;
  }

  .section {
    margin-bottom: 3rem;
    padding: 1.5rem;
    border: 2px solid black;
  }

  h1 {
    margin-bottom: 2rem;
  }

  h2 {
    margin-bottom: 1rem;
    font-size: 1.5rem;
  }

  .btn {
    padding: 0.5rem 1rem;
    border: 2px solid black;
    background: white;
    cursor: pointer;
    font-family: monospace;
  }

  .btn-primary {
    background: black;
    color: white;
  }

  .btn-danger {
    background: red;
    color: white;
  }

  table {
    width: 100%;
    border-collapse: collapse;
  }

  th, td {
    padding: 0.5rem;
    border: 1px solid black;
    text-align: left;
  }

  th {
    background: black;
    color: white;
  }
</style>

<script>
  // 2FA enrollment modal
  document.getElementById('enable-2fa')?.addEventListener('click', async () => {
    const response = await fetch('/api/security/2fa/enroll', {
      credentials: 'include',
    });
    const data = await response.json();

    // Show modal with QR code
    const modal = document.createElement('div');
    modal.innerHTML = `
      <div class="modal">
        <div class="modal-content">
          <h3>Scan QR Code</h3>
          <p>Scan this QR code with your authenticator app (Google Authenticator, Authy, etc.)</p>
          <img src="${data.qr_code}" alt="QR Code" />
          <p>Secret: <code>${data.secret}</code></p>

          <label>
            Enter 6-digit code from app:
            <input type="text" id="totp-passcode" maxlength="6" />
          </label>

          <button id="verify-totp" class="btn btn-primary">Enable 2FA</button>
          <button id="cancel-totp" class="btn">Cancel</button>
        </div>
      </div>
    `;
    document.body.appendChild(modal);

    // Verify passcode
    modal.querySelector('#verify-totp')?.addEventListener('click', async () => {
      const passcode = (modal.querySelector('#totp-passcode') as HTMLInputElement).value;
      const verifyResponse = await fetch('/api/security/2fa/enable', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ passcode }),
      });

      const verifyData = await verifyResponse.json();

      if (verifyData.success) {
        alert(`2FA enabled! Recovery code: ${verifyData.scratch_token}\n\nSave this code in a safe place!`);
        window.location.reload();
      } else {
        alert('Invalid passcode');
      }
    });

    // Cancel
    modal.querySelector('#cancel-totp')?.addEventListener('click', () => {
      modal.remove();
    });
  });

  // Add GPG key
  document.getElementById('add-gpg-key')?.addEventListener('click', () => {
    const content = prompt('Paste your GPG public key (armored format):');
    if (!content) return;

    fetch('/api/security/gpg', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ content }),
    }).then(() => window.location.reload());
  });

  // Add SSH key
  document.getElementById('add-ssh-key')?.addEventListener('click', () => {
    const name = prompt('Key name:');
    if (!name) return;

    const content = prompt('Paste your SSH public key:');
    if (!content) return;

    fetch('/api/security/ssh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ name, content }),
    }).then(() => window.location.reload());
  });
</script>
```

### 2. Repository deploy keys page

**File**: `/Users/williamcory/plue/ui/pages/[user]/[repo]/settings/keys.astro` (new)

```astro
---
import Layout from '../../../../layouts/Layout.astro';

const { user, repo } = Astro.params;

// TODO: Fetch from API
const deployKeys = [];
---

<Layout title={`Deploy Keys - ${user}/${repo}`}>
  <div class="container">
    <h1>Deploy Keys - {user}/{repo}</h1>

    <p>
      Deploy keys are SSH keys that grant access to a single repository.
      They can be read-only or read-write.
    </p>

    <section class="section">
      <h2>Deploy Keys</h2>

      <div id="deploy-keys">
        {deployKeys.length === 0 ? (
          <p>No deploy keys configured</p>
        ) : (
          <ul>
            {deployKeys.map((key: any) => (
              <li>
                <strong>{key.name}</strong> - <code>{key.fingerprint}</code>
                <span>{key.is_read_only ? '(read-only)' : '(read-write)'}</span>
                <button class="btn-delete-deploy" data-id={key.id}>Delete</button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <button id="add-deploy-key" class="btn btn-primary">Add Deploy Key</button>
    </section>
  </div>
</Layout>

<style>
  .container {
    max-width: 900px;
    margin: 0 auto;
    padding: 2rem;
  }

  .section {
    margin-top: 2rem;
    padding: 1.5rem;
    border: 2px solid black;
  }
</style>

<script>
  const { user, repo } = Astro.params;

  document.getElementById('add-deploy-key')?.addEventListener('click', () => {
    const name = prompt('Key name:');
    if (!name) return;

    const content = prompt('Paste SSH public key:');
    if (!content) return;

    const readOnly = confirm('Read-only access? (Cancel for read-write)');

    // Get repo ID (TODO: from page data)
    const repoId = 1;

    fetch(`/api/repos/${repoId}/deploy-keys`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ name, content, is_read_only: readOnly }),
    }).then(() => window.location.reload());
  });
</script>
```

### 3. Signed commit badge component

**File**: `/Users/williamcory/plue/ui/components/SignedCommitBadge.astro` (new)

```astro
---
interface Props {
  verified: boolean;
  keyId?: string;
  signer?: string;
}

const { verified, keyId, signer } = Astro.props;
---

{verified ? (
  <span class="badge badge-verified" title={`Signed with key ${keyId}`}>
    ✓ Verified
    {signer && <span class="signer">by {signer}</span>}
  </span>
) : (
  <span class="badge badge-unverified">
    ✗ Unverified
  </span>
)}

<style>
  .badge {
    display: inline-block;
    padding: 0.25rem 0.5rem;
    border: 1px solid;
    font-size: 0.8rem;
    font-family: monospace;
  }

  .badge-verified {
    background: #d4edda;
    border-color: #28a745;
    color: #155724;
  }

  .badge-unverified {
    background: #f8d7da;
    border-color: #dc3545;
    color: #721c24;
  }

  .signer {
    margin-left: 0.5rem;
    font-style: italic;
  }
</style>
```

Usage in commit view:

```astro
---
import SignedCommitBadge from '../components/SignedCommitBadge.astro';

// Check if commit has GPG signature
const commit = {
  // ... commit data
  gpg_signature: 'signature-data',
  verified: true,
  key_id: 'ABCD1234ABCD1234',
  signer: 'evilrabbit',
};
---

<div class="commit">
  <h3>{commit.message}</h3>
  <SignedCommitBadge verified={commit.verified} keyId={commit.key_id} signer={commit.signer} />
</div>
```

## Dependencies

Add to `/Users/williamcory/plue/package.json`:

```json
{
  "dependencies": {
    "otpauth": "^9.2.3",
    "openpgp": "^5.11.1",
    "ssh2": "^1.15.0",
    "qrcode": "^1.5.3"
  }
}
```

Install:

```bash
bun install
```

## Migration Script

**File**: `/Users/williamcory/plue/db/migrations/007_security_features.sql` (new)

```sql
-- Security Features Migration

-- TOTP credentials
CREATE TABLE IF NOT EXISTS totp_credentials (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  secret_encrypted TEXT NOT NULL,
  secret_iv VARCHAR(32) NOT NULL,
  scratch_salt VARCHAR(32) NOT NULL,
  scratch_hash VARCHAR(128) NOT NULL,
  last_used_passcode VARCHAR(10),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id)
);

CREATE INDEX idx_totp_credentials_user_id ON totp_credentials(user_id);

-- GPG keys
CREATE TABLE IF NOT EXISTS gpg_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_id VARCHAR(16) NOT NULL,
  primary_key_id VARCHAR(16),
  fingerprint VARCHAR(40) NOT NULL,
  content TEXT NOT NULL,
  expires_at TIMESTAMP,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  can_sign BOOLEAN NOT NULL DEFAULT false,
  can_encrypt_comms BOOLEAN NOT NULL DEFAULT false,
  can_encrypt_storage BOOLEAN NOT NULL DEFAULT false,
  can_certify BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(key_id),
  UNIQUE(fingerprint)
);

CREATE INDEX idx_gpg_keys_user_id ON gpg_keys(user_id);
CREATE INDEX idx_gpg_keys_key_id ON gpg_keys(key_id);
CREATE INDEX idx_gpg_keys_fingerprint ON gpg_keys(fingerprint);

-- GPG key emails
CREATE TABLE IF NOT EXISTS gpg_key_emails (
  id SERIAL PRIMARY KEY,
  gpg_key_id INTEGER NOT NULL REFERENCES gpg_keys(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_gpg_key_emails_key_id ON gpg_key_emails(gpg_key_id);

-- SSH keys
CREATE TABLE IF NOT EXISTS ssh_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  fingerprint VARCHAR(128) NOT NULL,
  content TEXT NOT NULL,
  key_type VARCHAR(50) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_used_at TIMESTAMP,
  UNIQUE(fingerprint),
  UNIQUE(user_id, name)
);

CREATE INDEX idx_ssh_keys_user_id ON ssh_keys(user_id);
CREATE INDEX idx_ssh_keys_fingerprint ON ssh_keys(fingerprint);

-- Deploy keys
CREATE TABLE IF NOT EXISTS deploy_keys (
  id SERIAL PRIMARY KEY,
  repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  fingerprint VARCHAR(128) NOT NULL,
  content TEXT NOT NULL,
  is_read_only BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_used_at TIMESTAMP,
  UNIQUE(fingerprint),
  UNIQUE(repository_id, name)
);

CREATE INDEX idx_deploy_keys_repository_id ON deploy_keys(repository_id);
CREATE INDEX idx_deploy_keys_fingerprint ON deploy_keys(fingerprint);

-- Update access tokens (if not already added)
ALTER TABLE access_tokens
  ADD COLUMN IF NOT EXISTS scope VARCHAR(512) NOT NULL DEFAULT 'all';

CREATE INDEX IF NOT EXISTS idx_access_tokens_scope ON access_tokens(scope);

-- Audit logs
CREATE TABLE IF NOT EXISTS audit_logs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(100) NOT NULL,
  category VARCHAR(50) NOT NULL,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB,
  success BOOLEAN NOT NULL DEFAULT true,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_category ON audit_logs(category);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
```

Run migration:

```bash
bun run db/migrate.ts
```

## Environment Variables

Add to `/Users/williamcory/plue/.env`:

```bash
# Security secret key (for encrypting TOTP secrets)
PLUE_SECRET_KEY="your-secret-key-here-min-32-chars"
```

**Important**: Generate a strong random key:

```bash
openssl rand -base64 32
```

## Testing

### Manual testing checklist:

**2FA:**
- [ ] Enroll in 2FA with QR code
- [ ] Verify passcode works
- [ ] Test replay protection (same passcode twice)
- [ ] Test scratch token recovery
- [ ] Disable 2FA

**GPG Keys:**
- [ ] Add GPG public key
- [ ] Verify key emails match user emails
- [ ] View signed commit badge in UI
- [ ] Delete GPG key

**SSH Keys:**
- [ ] Add SSH public key (RSA, Ed25519)
- [ ] Test duplicate fingerprint rejection
- [ ] Delete SSH key

**Deploy Keys:**
- [ ] Add read-only deploy key
- [ ] Add read-write deploy key
- [ ] Test duplicate fingerprint rejection
- [ ] Delete deploy key

**Audit Logs:**
- [ ] View audit logs after login
- [ ] View audit logs after key operations
- [ ] View audit logs after 2FA operations

## Implementation Checklist

### Phase 1: Database & Core Utilities
- [ ] Create migration script (007_security_features.sql)
- [ ] Run migration on PostgreSQL
- [ ] Implement `/Users/williamcory/plue/db/security.ts`
- [ ] Implement `/Users/williamcory/plue/server/lib/totp.ts`
- [ ] Implement `/Users/williamcory/plue/server/lib/gpg.ts`
- [ ] Implement `/Users/williamcory/plue/server/lib/ssh.ts`
- [ ] Implement `/Users/williamcory/plue/server/lib/token-scopes.ts`
- [ ] Add `PLUE_SECRET_KEY` to `.env`

### Phase 2: API Routes
- [ ] Implement `/Users/williamcory/plue/server/routes/security.ts`
- [ ] Add 2FA enrollment endpoint
- [ ] Add 2FA verification endpoint
- [ ] Add GPG key CRUD endpoints
- [ ] Add SSH key CRUD endpoints
- [ ] Add deploy key CRUD endpoints
- [ ] Add audit log endpoints
- [ ] Register security routes in `/Users/williamcory/plue/server/routes/index.ts`

### Phase 3: Frontend Pages
- [ ] Create `/Users/williamcory/plue/ui/pages/settings/security.astro`
- [ ] Implement 2FA enrollment modal with QR code
- [ ] Implement GPG key management UI
- [ ] Implement SSH key management UI
- [ ] Implement audit log viewer
- [ ] Create `/Users/williamcory/plue/ui/pages/[user]/[repo]/settings/keys.astro`
- [ ] Implement deploy key management UI
- [ ] Create `/Users/williamcory/plue/ui/components/SignedCommitBadge.astro`

### Phase 4: Git Integration
- [ ] Modify commit view to check GPG signatures
- [ ] Display SignedCommitBadge on verified commits
- [ ] Show key details on hover
- [ ] Link to signer's GPG key page

### Phase 5: Testing & Polish
- [ ] Test 2FA enrollment and verification
- [ ] Test GPG key parsing (RSA, ECDSA, EdDSA)
- [ ] Test SSH key parsing (RSA, Ed25519, ECDSA)
- [ ] Test token scope validation
- [ ] Test audit log creation
- [ ] Add error handling and validation
- [ ] Add rate limiting for 2FA attempts
- [ ] Document security best practices

## Security Considerations

1. **TOTP Secret Encryption**: Always encrypt TOTP secrets at rest using AES-256-GCM
2. **Replay Protection**: Track last used passcode to prevent replay attacks
3. **Recovery Codes**: Generate secure scratch tokens for 2FA recovery
4. **Key Fingerprints**: Validate SSH/GPG key fingerprints before storage
5. **Audit Logging**: Log all security-sensitive operations with IP and user agent
6. **Token Scopes**: Enforce fine-grained permissions on API tokens
7. **Rate Limiting**: Limit 2FA verification attempts to prevent brute force
8. **Timing Attacks**: Use constant-time comparison for sensitive checks

## Future Enhancements

- WebAuthn/FIDO2 support (hardware keys)
- Multiple 2FA methods (TOTP + WebAuthn)
- Email notifications for security events
- IP allowlisting for API tokens
- Audit log export (CSV, JSON)
- Advanced audit log filtering
- Session management (view/revoke sessions)
- OAuth2 scope support
