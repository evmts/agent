# Authentication & Authorization Implementation

## Overview

Implement a complete authentication and authorization system for Plue, transforming it from a seeded-user system to a fully functional multi-user platform with secure login, registration, and session management.

**Scope:**
- User registration with email verification
- Password-based authentication with secure hashing
- Session management with cookie-based authentication
- Password reset/recovery flow
- Access tokens for API authentication
- Protected routes and middleware
- User profile management
- Basic authorization (own repositories/issues only)

**Out of scope (future features):**
- OAuth2 providers
- Two-factor authentication (2FA)
- WebAuthn/Passkeys
- LDAP/SSO integration
- Advanced RBAC/permissions

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server with middleware
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL with `postgres` client
- **Validation**: Zod v4
- **Password Hashing**: `@node-rs/argon2` (native Rust bindings)
- **Session Management**: Cookie-based sessions

## Database Schema Changes

### 1. Update `users` table

**File**: `/Users/williamcory/plue/db/schema.sql`

Replace the existing minimal users table with:

```sql
-- Users table with authentication
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  lower_username VARCHAR(255) UNIQUE NOT NULL, -- for case-insensitive lookups
  email VARCHAR(255) UNIQUE NOT NULL,
  lower_email VARCHAR(255) UNIQUE NOT NULL, -- for case-insensitive lookups

  -- Display info
  display_name VARCHAR(255),
  bio TEXT,
  avatar_url VARCHAR(2048),

  -- Authentication
  password_hash VARCHAR(255) NOT NULL,
  password_algo VARCHAR(50) NOT NULL DEFAULT 'argon2id',
  salt VARCHAR(64) NOT NULL,

  -- Account status
  is_active BOOLEAN NOT NULL DEFAULT false, -- email verified
  is_admin BOOLEAN NOT NULL DEFAULT false,
  prohibit_login BOOLEAN NOT NULL DEFAULT false,
  must_change_password BOOLEAN NOT NULL DEFAULT false,

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_lower_username ON users(lower_username);
CREATE INDEX IF NOT EXISTS idx_users_lower_email ON users(lower_email);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
```

**Migration note**: Existing seeded users will need passwords added or be marked as inactive.

### 2. Email addresses table

Support multiple emails per user (like Gitea):

```sql
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
```

### 3. Sessions table

Replace agent sessions with auth sessions:

```sql
-- Auth sessions (for cookie-based authentication)
CREATE TABLE IF NOT EXISTS auth_sessions (
  session_key VARCHAR(64) PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  data BYTEA,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires_at ON auth_sessions(expires_at);
```

### 4. Access tokens table

For API authentication:

```sql
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
```

### 5. Email verification tokens

For registration and password reset:

```sql
-- Email verification tokens
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token_hash VARCHAR(64) UNIQUE NOT NULL,
  token_type VARCHAR(20) NOT NULL CHECK (token_type IN ('activate', 'reset_password')),
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_user_id ON email_verification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_token_hash ON email_verification_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_expires_at ON email_verification_tokens(expires_at);
```

### 6. Update foreign keys

Update repositories and issues to enforce user ownership:

```sql
-- Add ON DELETE RESTRICT to prevent deleting users with content
ALTER TABLE repositories
  DROP CONSTRAINT repositories_user_id_fkey,
  ADD CONSTRAINT repositories_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE issues
  DROP CONSTRAINT issues_author_id_fkey,
  ADD CONSTRAINT issues_author_id_fkey
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE comments
  DROP CONSTRAINT comments_author_id_fkey,
  ADD CONSTRAINT comments_author_id_fkey
    FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE RESTRICT;
```

## Backend Implementation

### 1. Password Hashing Utility

**File**: `/Users/williamcory/plue/server/lib/password.ts`

```typescript
import { hash, verify } from '@node-rs/argon2';
import { randomBytes } from 'crypto';

/**
 * Argon2id configuration (secure defaults)
 * Based on OWASP recommendations
 */
const ARGON2_CONFIG = {
  memoryCost: 65536, // 64 MiB
  timeCost: 3,       // 3 iterations
  parallelism: 4,    // 4 threads
};

/**
 * Generate a random salt (32 bytes, hex-encoded)
 */
export function generateSalt(): string {
  return randomBytes(32).toString('hex');
}

/**
 * Hash a password with argon2id
 */
export async function hashPassword(password: string, salt: string): Promise<string> {
  const saltBytes = Buffer.from(salt, 'hex');

  return hash(password, {
    ...ARGON2_CONFIG,
    salt: saltBytes,
  });
}

/**
 * Verify a password against a hash
 */
export async function verifyPassword(
  password: string,
  passwordHash: string,
  salt: string
): Promise<boolean> {
  try {
    const saltBytes = Buffer.from(salt, 'hex');
    return verify(passwordHash, password, {
      ...ARGON2_CONFIG,
      salt: saltBytes,
    });
  } catch (error) {
    console.error('Password verification error:', error);
    return false;
  }
}

/**
 * Check password complexity requirements
 * Minimum 8 characters, at least one uppercase, lowercase, digit
 */
export function validatePasswordComplexity(password: string): {
  valid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (password.length < 8) {
    errors.push('Password must be at least 8 characters');
  }

  if (!/[a-z]/.test(password)) {
    errors.push('Password must contain at least one lowercase letter');
  }

  if (!/[A-Z]/.test(password)) {
    errors.push('Password must contain at least one uppercase letter');
  }

  if (!/[0-9]/.test(password)) {
    errors.push('Password must contain at least one digit');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Generate a secure random token (for email verification, password reset)
 */
export function generateToken(): { token: string; tokenHash: string } {
  const token = randomBytes(32).toString('hex');
  const tokenHash = createHash('sha256').update(token).digest('hex');

  return { token, tokenHash };
}
```

**Install dependencies:**
```bash
bun add @node-rs/argon2
```

### 2. Session Management

**File**: `/Users/williamcory/plue/server/lib/session.ts`

```typescript
import { randomBytes } from 'crypto';
import { sql } from '../../ui/lib/db';

export interface SessionData {
  userId: number;
  username: string;
  isAdmin: boolean;
  [key: string]: any;
}

const SESSION_DURATION = 30 * 24 * 60 * 60 * 1000; // 30 days in ms

/**
 * Create a new session
 */
export async function createSession(userId: number, username: string, isAdmin: boolean): Promise<string> {
  const sessionKey = randomBytes(32).toString('hex');
  const data: SessionData = { userId, username, isAdmin };
  const dataBuffer = Buffer.from(JSON.stringify(data));
  const expiresAt = new Date(Date.now() + SESSION_DURATION);

  await sql`
    INSERT INTO auth_sessions (session_key, user_id, data, expires_at)
    VALUES (${sessionKey}, ${userId}, ${dataBuffer}, ${expiresAt})
  `;

  return sessionKey;
}

/**
 * Get session data by key
 */
export async function getSession(sessionKey: string): Promise<SessionData | null> {
  if (!sessionKey) return null;

  const [session] = await sql<Array<{
    user_id: number;
    data: Buffer;
    expires_at: Date;
  }>>`
    SELECT user_id, data, expires_at
    FROM auth_sessions
    WHERE session_key = ${sessionKey}
      AND expires_at > NOW()
  `;

  if (!session) return null;

  try {
    return JSON.parse(session.data.toString());
  } catch (error) {
    console.error('Failed to parse session data:', error);
    return null;
  }
}

/**
 * Update session expiration (refresh on activity)
 */
export async function refreshSession(sessionKey: string): Promise<void> {
  const expiresAt = new Date(Date.now() + SESSION_DURATION);

  await sql`
    UPDATE auth_sessions
    SET expires_at = ${expiresAt}, updated_at = NOW()
    WHERE session_key = ${sessionKey}
  `;
}

/**
 * Delete a session (logout)
 */
export async function deleteSession(sessionKey: string): Promise<void> {
  await sql`
    DELETE FROM auth_sessions
    WHERE session_key = ${sessionKey}
  `;
}

/**
 * Cleanup expired sessions (run periodically)
 */
export async function cleanupExpiredSessions(): Promise<number> {
  const result = await sql`
    DELETE FROM auth_sessions
    WHERE expires_at <= NOW()
  `;

  return result.count;
}
```

### 3. Authentication Middleware

**File**: `/Users/williamcory/plue/server/middleware/auth.ts`

```typescript
import { Context, Next } from 'hono';
import { getSession, refreshSession } from '../lib/session';
import { sql } from '../../ui/lib/db';

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  displayName: string | null;
  isAdmin: boolean;
  isActive: boolean;
}

declare module 'hono' {
  interface ContextVariableMap {
    user: AuthUser | null;
    sessionKey: string | null;
  }
}

const SESSION_COOKIE_NAME = 'plue_session';

/**
 * Auth middleware - loads user from session cookie
 * Does not require authentication, just loads if present
 */
export async function authMiddleware(c: Context, next: Next) {
  const sessionKey = c.req.cookie(SESSION_COOKIE_NAME);

  if (!sessionKey) {
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  const sessionData = await getSession(sessionKey);

  if (!sessionData) {
    // Invalid or expired session
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  // Load fresh user data from database
  const [user] = await sql<Array<{
    id: number;
    username: string;
    email: string;
    display_name: string | null;
    is_admin: boolean;
    is_active: boolean;
    prohibit_login: boolean;
  }>>`
    SELECT id, username, email, display_name, is_admin, is_active, prohibit_login
    FROM users
    WHERE id = ${sessionData.userId}
  `;

  if (!user || user.prohibit_login) {
    c.set('user', null);
    c.set('sessionKey', null);
    await next();
    return;
  }

  // Refresh session expiration
  await refreshSession(sessionKey);

  c.set('user', {
    id: user.id,
    username: user.username,
    email: user.email,
    displayName: user.display_name,
    isAdmin: user.is_admin,
    isActive: user.is_active,
  });
  c.set('sessionKey', sessionKey);

  await next();
}

/**
 * Require authentication - returns 401 if not authenticated
 */
export async function requireAuth(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  await next();
}

/**
 * Require active account - returns 403 if not activated
 */
export async function requireActiveAccount(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  if (!user.isActive) {
    return c.json({ error: 'Account not activated. Please verify your email.' }, 403);
  }

  await next();
}

/**
 * Require admin - returns 403 if not admin
 */
export async function requireAdmin(c: Context, next: Next) {
  const user = c.get('user');

  if (!user) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  if (!user.isAdmin) {
    return c.json({ error: 'Admin access required' }, 403);
  }

  await next();
}

/**
 * Helper to set session cookie
 */
export function setSessionCookie(c: Context, sessionKey: string) {
  c.cookie(SESSION_COOKIE_NAME, sessionKey, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'Lax',
    maxAge: 30 * 24 * 60 * 60, // 30 days
    path: '/',
  });
}

/**
 * Helper to clear session cookie
 */
export function clearSessionCookie(c: Context) {
  c.cookie(SESSION_COOKIE_NAME, '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'Lax',
    maxAge: 0,
    path: '/',
  });
}
```

### 4. Validation Schemas

**File**: `/Users/williamcory/plue/server/lib/validation.ts`

```typescript
import { z } from 'zod';

/**
 * Username validation
 * - 3-39 characters
 * - alphanumeric, hyphens, underscores
 * - cannot start/end with hyphen
 */
export const usernameSchema = z
  .string()
  .min(3, 'Username must be at least 3 characters')
  .max(39, 'Username must be at most 39 characters')
  .regex(/^[a-zA-Z0-9]([a-zA-Z0-9-_]*[a-zA-Z0-9])?$/,
    'Username must start and end with alphanumeric, contain only letters, numbers, hyphens, and underscores');

/**
 * Email validation
 */
export const emailSchema = z
  .string()
  .email('Invalid email address')
  .max(255, 'Email must be at most 255 characters');

/**
 * Password validation (basic - complexity checked separately)
 */
export const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(255, 'Password is too long');

/**
 * Registration request
 */
export const registerSchema = z.object({
  username: usernameSchema,
  email: emailSchema,
  password: passwordSchema,
  displayName: z.string().max(255).optional(),
});

/**
 * Login request
 */
export const loginSchema = z.object({
  usernameOrEmail: z.string().min(1, 'Username or email is required'),
  password: z.string().min(1, 'Password is required'),
  rememberMe: z.boolean().optional(),
});

/**
 * Password reset request
 */
export const passwordResetRequestSchema = z.object({
  email: emailSchema,
});

/**
 * Password reset confirm
 */
export const passwordResetConfirmSchema = z.object({
  token: z.string().min(1, 'Token is required'),
  password: passwordSchema,
});

/**
 * Update profile
 */
export const updateProfileSchema = z.object({
  displayName: z.string().max(255).optional(),
  bio: z.string().max(2000).optional(),
  avatarUrl: z.string().url().max(2048).optional(),
});

/**
 * Change password
 */
export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: passwordSchema,
});
```

### 5. Authentication Routes

**File**: `/Users/williamcory/plue/server/routes/auth.ts`

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import {
  registerSchema,
  loginSchema,
  passwordResetRequestSchema,
  passwordResetConfirmSchema,
} from '../lib/validation';
import {
  hashPassword,
  verifyPassword,
  generateSalt,
  validatePasswordComplexity,
  generateToken,
} from '../lib/password';
import { createSession, deleteSession } from '../lib/session';
import { setSessionCookie, clearSessionCookie } from '../middleware/auth';
import { sql } from '../../ui/lib/db';

const app = new Hono();

/**
 * POST /auth/register
 * Register a new user account
 */
app.post('/register', zValidator('json', registerSchema), async (c) => {
  const { username, email, password, displayName } = c.req.valid('json');

  // Validate password complexity
  const complexity = validatePasswordComplexity(password);
  if (!complexity.valid) {
    return c.json({ error: 'Password complexity requirements not met', details: complexity.errors }, 400);
  }

  // Check if username or email already exists
  const [existing] = await sql<Array<{ count: number }>>`
    SELECT COUNT(*) as count FROM users
    WHERE lower_username = ${username.toLowerCase()}
       OR lower_email = ${email.toLowerCase()}
  `;

  if (existing && existing.count > 0) {
    return c.json({ error: 'Username or email already exists' }, 409);
  }

  // Hash password
  const salt = generateSalt();
  const passwordHash = await hashPassword(password, salt);

  // Create user
  const [user] = await sql<Array<{ id: number }>>`
    INSERT INTO users (
      username, lower_username,
      email, lower_email,
      display_name, password_hash, password_algo, salt,
      is_active, created_at, updated_at
    ) VALUES (
      ${username}, ${username.toLowerCase()},
      ${email}, ${email.toLowerCase()},
      ${displayName || username}, ${passwordHash}, 'argon2id', ${salt},
      false, NOW(), NOW()
    )
    RETURNING id
  `;

  // Create primary email record
  await sql`
    INSERT INTO email_addresses (user_id, email, lower_email, is_primary, is_activated)
    VALUES (${user.id}, ${email}, ${email.toLowerCase()}, true, false)
  `;

  // Generate activation token
  const { token, tokenHash } = generateToken();
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

  await sql`
    INSERT INTO email_verification_tokens (user_id, email, token_hash, token_type, expires_at)
    VALUES (${user.id}, ${email}, ${tokenHash}, 'activate', ${expiresAt})
  `;

  // TODO: Send activation email with token
  console.log(`Activation token for ${email}: ${token}`);

  return c.json({
    message: 'Registration successful. Please check your email to activate your account.',
    userId: user.id,
  }, 201);
});

/**
 * POST /auth/activate
 * Activate user account via email token
 */
app.post('/activate', async (c) => {
  const { token } = await c.req.json();

  if (!token) {
    return c.json({ error: 'Token is required' }, 400);
  }

  const tokenHash = createHash('sha256').update(token).digest('hex');

  // Find valid token
  const [verificationToken] = await sql<Array<{
    user_id: number;
    email: string;
    expires_at: Date;
  }>>`
    SELECT user_id, email, expires_at
    FROM email_verification_tokens
    WHERE token_hash = ${tokenHash}
      AND token_type = 'activate'
      AND expires_at > NOW()
  `;

  if (!verificationToken) {
    return c.json({ error: 'Invalid or expired activation token' }, 400);
  }

  // Activate user
  await sql`
    UPDATE users
    SET is_active = true, updated_at = NOW()
    WHERE id = ${verificationToken.user_id}
  `;

  // Mark email as activated
  await sql`
    UPDATE email_addresses
    SET is_activated = true
    WHERE user_id = ${verificationToken.user_id}
      AND lower_email = ${verificationToken.email.toLowerCase()}
  `;

  // Delete used token
  await sql`
    DELETE FROM email_verification_tokens
    WHERE token_hash = ${tokenHash}
  `;

  return c.json({ message: 'Account activated successfully' });
});

/**
 * POST /auth/login
 * Authenticate user and create session
 */
app.post('/login', zValidator('json', loginSchema), async (c) => {
  const { usernameOrEmail, password } = c.req.valid('json');

  // Find user by username or email
  const isEmail = usernameOrEmail.includes('@');
  const [user] = await sql<Array<{
    id: number;
    username: string;
    email: string;
    password_hash: string;
    salt: string;
    is_active: boolean;
    is_admin: boolean;
    prohibit_login: boolean;
  }>>`
    SELECT id, username, email, password_hash, salt, is_active, is_admin, prohibit_login
    FROM users
    WHERE ${isEmail
      ? sql`lower_email = ${usernameOrEmail.toLowerCase()}`
      : sql`lower_username = ${usernameOrEmail.toLowerCase()}`
    }
  `;

  if (!user) {
    return c.json({ error: 'Invalid username/email or password' }, 401);
  }

  // Check prohibit login
  if (user.prohibit_login) {
    return c.json({ error: 'Account is disabled' }, 403);
  }

  // Verify password
  const valid = await verifyPassword(password, user.password_hash, user.salt);
  if (!valid) {
    return c.json({ error: 'Invalid username/email or password' }, 401);
  }

  // Create session
  const sessionKey = await createSession(user.id, user.username, user.is_admin);

  // Update last login
  await sql`
    UPDATE users
    SET last_login_at = NOW(), updated_at = NOW()
    WHERE id = ${user.id}
  `;

  // Set session cookie
  setSessionCookie(c, sessionKey);

  return c.json({
    message: 'Login successful',
    user: {
      id: user.id,
      username: user.username,
      email: user.email,
      isActive: user.is_active,
      isAdmin: user.is_admin,
    },
  });
});

/**
 * POST /auth/logout
 * Destroy session and clear cookie
 */
app.post('/logout', async (c) => {
  const sessionKey = c.req.cookie('plue_session');

  if (sessionKey) {
    await deleteSession(sessionKey);
  }

  clearSessionCookie(c);

  return c.json({ message: 'Logout successful' });
});

/**
 * GET /auth/me
 * Get current authenticated user
 */
app.get('/me', async (c) => {
  const user = c.get('user');

  if (!user) {
    return c.json({ user: null });
  }

  return c.json({ user });
});

/**
 * POST /auth/password/reset-request
 * Request password reset email
 */
app.post('/password/reset-request', zValidator('json', passwordResetRequestSchema), async (c) => {
  const { email } = c.req.valid('json');

  // Find user (don't reveal if user exists)
  const [user] = await sql<Array<{ id: number }>>`
    SELECT id FROM users
    WHERE lower_email = ${email.toLowerCase()}
  `;

  if (user) {
    // Generate reset token
    const { token, tokenHash } = generateToken();
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

    await sql`
      INSERT INTO email_verification_tokens (user_id, email, token_hash, token_type, expires_at)
      VALUES (${user.id}, ${email}, ${tokenHash}, 'reset_password', ${expiresAt})
    `;

    // TODO: Send password reset email
    console.log(`Password reset token for ${email}: ${token}`);
  }

  // Always return success to avoid user enumeration
  return c.json({ message: 'If the email exists, a password reset link has been sent' });
});

/**
 * POST /auth/password/reset-confirm
 * Confirm password reset with token
 */
app.post('/password/reset-confirm', zValidator('json', passwordResetConfirmSchema), async (c) => {
  const { token, password } = c.req.valid('json');

  // Validate password complexity
  const complexity = validatePasswordComplexity(password);
  if (!complexity.valid) {
    return c.json({ error: 'Password complexity requirements not met', details: complexity.errors }, 400);
  }

  const tokenHash = createHash('sha256').update(token).digest('hex');

  // Find valid token
  const [verificationToken] = await sql<Array<{ user_id: number }>>`
    SELECT user_id
    FROM email_verification_tokens
    WHERE token_hash = ${tokenHash}
      AND token_type = 'reset_password'
      AND expires_at > NOW()
  `;

  if (!verificationToken) {
    return c.json({ error: 'Invalid or expired reset token' }, 400);
  }

  // Hash new password
  const salt = generateSalt();
  const passwordHash = await hashPassword(password, salt);

  // Update password
  await sql`
    UPDATE users
    SET password_hash = ${passwordHash},
        password_algo = 'argon2id',
        salt = ${salt},
        must_change_password = false,
        updated_at = NOW()
    WHERE id = ${verificationToken.user_id}
  `;

  // Delete all reset tokens for this user
  await sql`
    DELETE FROM email_verification_tokens
    WHERE user_id = ${verificationToken.user_id}
      AND token_type = 'reset_password'
  `;

  // Invalidate all sessions for security
  await sql`
    DELETE FROM auth_sessions
    WHERE user_id = ${verificationToken.user_id}
  `;

  return c.json({ message: 'Password reset successful. Please login with your new password.' });
});

export default app;
```

Install Hono validator:
```bash
bun add @hono/zod-validator
```

### 6. User Profile Routes

**File**: `/Users/williamcory/plue/server/routes/users.ts`

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import { updateProfileSchema, changePasswordSchema } from '../lib/validation';
import { hashPassword, verifyPassword, generateSalt, validatePasswordComplexity } from '../lib/password';
import { sql } from '../../ui/lib/db';

const app = new Hono();

/**
 * GET /users/:username
 * Get public user profile
 */
app.get('/:username', async (c) => {
  const { username } = c.req.param();

  const [user] = await sql<Array<{
    id: number;
    username: string;
    display_name: string | null;
    bio: string | null;
    avatar_url: string | null;
    created_at: Date;
  }>>`
    SELECT id, username, display_name, bio, avatar_url, created_at
    FROM users
    WHERE lower_username = ${username.toLowerCase()}
      AND is_active = true
      AND prohibit_login = false
  `;

  if (!user) {
    return c.json({ error: 'User not found' }, 404);
  }

  // Get repository count
  const [stats] = await sql<Array<{ repo_count: number }>>`
    SELECT COUNT(*) as repo_count
    FROM repositories
    WHERE user_id = ${user.id}
      AND is_public = true
  `;

  return c.json({
    user: {
      ...user,
      repoCount: stats?.repo_count || 0,
    },
  });
});

/**
 * PATCH /users/me
 * Update own profile (requires auth)
 */
app.patch('/me', requireAuth, requireActiveAccount, zValidator('json', updateProfileSchema), async (c) => {
  const user = c.get('user')!;
  const updates = c.req.valid('json');

  // Build dynamic update query
  const setClauses: string[] = [];
  const values: any[] = [];

  if (updates.displayName !== undefined) {
    setClauses.push(`display_name = $${values.length + 1}`);
    values.push(updates.displayName);
  }

  if (updates.bio !== undefined) {
    setClauses.push(`bio = $${values.length + 1}`);
    values.push(updates.bio);
  }

  if (updates.avatarUrl !== undefined) {
    setClauses.push(`avatar_url = $${values.length + 1}`);
    values.push(updates.avatarUrl);
  }

  if (setClauses.length === 0) {
    return c.json({ error: 'No updates provided' }, 400);
  }

  setClauses.push(`updated_at = NOW()`);
  values.push(user.id);

  await sql`
    UPDATE users
    SET ${sql.unsafe(setClauses.join(', '))}
    WHERE id = ${user.id}
  `;

  return c.json({ message: 'Profile updated successfully' });
});

/**
 * POST /users/me/password
 * Change password (requires auth)
 */
app.post('/me/password', requireAuth, zValidator('json', changePasswordSchema), async (c) => {
  const user = c.get('user')!;
  const { currentPassword, newPassword } = c.req.valid('json');

  // Validate new password complexity
  const complexity = validatePasswordComplexity(newPassword);
  if (!complexity.valid) {
    return c.json({ error: 'Password complexity requirements not met', details: complexity.errors }, 400);
  }

  // Get current password hash
  const [dbUser] = await sql<Array<{
    password_hash: string;
    salt: string;
  }>>`
    SELECT password_hash, salt
    FROM users
    WHERE id = ${user.id}
  `;

  if (!dbUser) {
    return c.json({ error: 'User not found' }, 404);
  }

  // Verify current password
  const valid = await verifyPassword(currentPassword, dbUser.password_hash, dbUser.salt);
  if (!valid) {
    return c.json({ error: 'Current password is incorrect' }, 401);
  }

  // Hash new password
  const salt = generateSalt();
  const passwordHash = await hashPassword(newPassword, salt);

  // Update password
  await sql`
    UPDATE users
    SET password_hash = ${passwordHash},
        password_algo = 'argon2id',
        salt = ${salt},
        updated_at = NOW()
    WHERE id = ${user.id}
  `;

  // Invalidate all other sessions for security
  const currentSessionKey = c.get('sessionKey');
  await sql`
    DELETE FROM auth_sessions
    WHERE user_id = ${user.id}
      AND session_key != ${currentSessionKey}
  `;

  return c.json({ message: 'Password changed successfully' });
});

export default app;
```

### 7. Update Server Index

**File**: `/Users/williamcory/plue/server/index.ts`

Add auth middleware and routes:

```typescript
import { authMiddleware } from './middleware/auth';
import authRoutes from './routes/auth';
import usersRoutes from './routes/users';

// Apply auth middleware globally (before routes)
app.use('*', authMiddleware);

// Mount auth routes
app.route('/api/auth', authRoutes);
app.route('/api/users', usersRoutes);

// Existing routes...
app.route('/', routes);
```

### 8. Protect Existing Routes

Update `/Users/williamcory/plue/server/routes/sessions.ts` to require auth:

```typescript
import { requireAuth, requireActiveAccount } from '../middleware/auth';

// Apply auth to all session routes
app.use('*', requireAuth, requireActiveAccount);

// Existing routes...
```

## Frontend Implementation

### 1. Update Types

**File**: `/Users/williamcory/plue/ui/lib/types.ts`

```typescript
export interface User {
  id: number;
  username: string;
  email: string;
  displayName: string | null;
  bio: string | null;
  avatarUrl: string | null;
  isAdmin: boolean;
  isActive: boolean;
  createdAt: Date;
}

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  displayName: string | null;
  isAdmin: boolean;
  isActive: boolean;
}
```

### 2. Auth API Client

**File**: `/Users/williamcory/plue/ui/lib/auth.ts`

```typescript
export interface RegisterData {
  username: string;
  email: string;
  password: string;
  displayName?: string;
}

export interface LoginData {
  usernameOrEmail: string;
  password: string;
}

const API_BASE = '/api';

export async function register(data: RegisterData) {
  const response = await fetch(`${API_BASE}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
    credentials: 'include',
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Registration failed');
  }

  return response.json();
}

export async function login(data: LoginData) {
  const response = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
    credentials: 'include',
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Login failed');
  }

  return response.json();
}

export async function logout() {
  const response = await fetch(`${API_BASE}/auth/logout`, {
    method: 'POST',
    credentials: 'include',
  });

  if (!response.ok) {
    throw new Error('Logout failed');
  }

  return response.json();
}

export async function getCurrentUser() {
  const response = await fetch(`${API_BASE}/auth/me`, {
    credentials: 'include',
  });

  if (!response.ok) {
    return null;
  }

  const data = await response.json();
  return data.user;
}
```

### 3. Login Page

**File**: `/Users/williamcory/plue/ui/pages/login.astro`

```astro
---
import Layout from "../layouts/Layout.astro";

// If already logged in, redirect
const sessionCookie = Astro.cookies.get('plue_session');
if (sessionCookie) {
  return Astro.redirect('/');
}
---

<Layout title="Sign In - plue">
  <div class="container">
    <div class="auth-container">
      <h1>Sign In</h1>

      <form id="login-form" class="auth-form">
        <div class="form-group">
          <label for="usernameOrEmail">Username or Email</label>
          <input
            type="text"
            id="usernameOrEmail"
            name="usernameOrEmail"
            required
            autocomplete="username"
          />
        </div>

        <div class="form-group">
          <label for="password">Password</label>
          <input
            type="password"
            id="password"
            name="password"
            required
            autocomplete="current-password"
          />
        </div>

        <div id="error" class="error-message" style="display: none;"></div>

        <button type="submit" class="btn btn-primary btn-block">
          Sign In
        </button>
      </form>

      <div class="auth-links">
        <a href="/register">Don't have an account? Sign up</a>
        <a href="/password/reset">Forgot password?</a>
      </div>
    </div>
  </div>
</Layout>

<style>
  .auth-container {
    max-width: 400px;
    margin: 4rem auto;
    padding: 2rem;
    border: 2px solid #000;
  }

  .auth-form {
    margin-top: 2rem;
  }

  .form-group {
    margin-bottom: 1.5rem;
  }

  .form-group label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: bold;
  }

  .form-group input {
    width: 100%;
    padding: 0.5rem;
    border: 2px solid #000;
    font-family: monospace;
    font-size: 1rem;
  }

  .form-group input:focus {
    outline: none;
    background: #ffffcc;
  }

  .error-message {
    padding: 0.75rem;
    margin-bottom: 1rem;
    background: #ffcccc;
    border: 2px solid #cc0000;
    color: #cc0000;
  }

  .btn-block {
    width: 100%;
  }

  .auth-links {
    margin-top: 2rem;
    text-align: center;
  }

  .auth-links a {
    display: block;
    margin-top: 0.5rem;
  }
</style>

<script>
  import { login } from '../lib/auth';

  const form = document.getElementById('login-form') as HTMLFormElement;
  const errorDiv = document.getElementById('error') as HTMLDivElement;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    const formData = new FormData(form);
    const data = {
      usernameOrEmail: formData.get('usernameOrEmail') as string,
      password: formData.get('password') as string,
    };

    try {
      await login(data);
      window.location.href = '/';
    } catch (error) {
      errorDiv.textContent = error instanceof Error ? error.message : 'Login failed';
      errorDiv.style.display = 'block';
    }
  });
</script>
```

### 4. Registration Page

**File**: `/Users/williamcory/plue/ui/pages/register.astro`

```astro
---
import Layout from "../layouts/Layout.astro";

// If already logged in, redirect
const sessionCookie = Astro.cookies.get('plue_session');
if (sessionCookie) {
  return Astro.redirect('/');
}
---

<Layout title="Sign Up - plue">
  <div class="container">
    <div class="auth-container">
      <h1>Sign Up</h1>

      <form id="register-form" class="auth-form">
        <div class="form-group">
          <label for="username">Username</label>
          <input
            type="text"
            id="username"
            name="username"
            required
            pattern="^[a-zA-Z0-9]([a-zA-Z0-9-_]*[a-zA-Z0-9])?$"
            minlength="3"
            maxlength="39"
            autocomplete="username"
          />
          <small>3-39 characters, alphanumeric with hyphens/underscores</small>
        </div>

        <div class="form-group">
          <label for="email">Email</label>
          <input
            type="email"
            id="email"
            name="email"
            required
            autocomplete="email"
          />
        </div>

        <div class="form-group">
          <label for="password">Password</label>
          <input
            type="password"
            id="password"
            name="password"
            required
            minlength="8"
            autocomplete="new-password"
          />
          <small>At least 8 characters with uppercase, lowercase, and digit</small>
        </div>

        <div class="form-group">
          <label for="displayName">Display Name (optional)</label>
          <input
            type="text"
            id="displayName"
            name="displayName"
            maxlength="255"
          />
        </div>

        <div id="error" class="error-message" style="display: none;"></div>
        <div id="success" class="success-message" style="display: none;"></div>

        <button type="submit" class="btn btn-primary btn-block">
          Sign Up
        </button>
      </form>

      <div class="auth-links">
        <a href="/login">Already have an account? Sign in</a>
      </div>
    </div>
  </div>
</Layout>

<style>
  .auth-container {
    max-width: 400px;
    margin: 4rem auto;
    padding: 2rem;
    border: 2px solid #000;
  }

  .auth-form {
    margin-top: 2rem;
  }

  .form-group {
    margin-bottom: 1.5rem;
  }

  .form-group label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: bold;
  }

  .form-group input {
    width: 100%;
    padding: 0.5rem;
    border: 2px solid #000;
    font-family: monospace;
    font-size: 1rem;
  }

  .form-group input:focus {
    outline: none;
    background: #ffffcc;
  }

  .form-group small {
    display: block;
    margin-top: 0.25rem;
    font-size: 0.875rem;
    color: #666;
  }

  .error-message {
    padding: 0.75rem;
    margin-bottom: 1rem;
    background: #ffcccc;
    border: 2px solid #cc0000;
    color: #cc0000;
  }

  .success-message {
    padding: 0.75rem;
    margin-bottom: 1rem;
    background: #ccffcc;
    border: 2px solid #00cc00;
    color: #00aa00;
  }

  .btn-block {
    width: 100%;
  }

  .auth-links {
    margin-top: 2rem;
    text-align: center;
  }
</style>

<script>
  import { register } from '../lib/auth';

  const form = document.getElementById('register-form') as HTMLFormElement;
  const errorDiv = document.getElementById('error') as HTMLDivElement;
  const successDiv = document.getElementById('success') as HTMLDivElement;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    errorDiv.style.display = 'none';
    successDiv.style.display = 'none';

    const formData = new FormData(form);
    const data = {
      username: formData.get('username') as string,
      email: formData.get('email') as string,
      password: formData.get('password') as string,
      displayName: formData.get('displayName') as string || undefined,
    };

    try {
      const result = await register(data);
      successDiv.textContent = result.message;
      successDiv.style.display = 'block';
      form.reset();
    } catch (error) {
      errorDiv.textContent = error instanceof Error ? error.message : 'Registration failed';
      errorDiv.style.display = 'block';
    }
  });
</script>
```

### 5. Update Header Component

**File**: `/Users/williamcory/plue/ui/components/Header.astro`

Add authentication state and logout:

```astro
---
interface Props {
  currentPath: string;
}

const { currentPath } = Astro.props;

// Check if user is authenticated
let user = null;
const sessionCookie = Astro.cookies.get('plue_session');

if (sessionCookie) {
  try {
    const response = await fetch(`${Astro.url.origin}/api/auth/me`, {
      headers: {
        Cookie: `plue_session=${sessionCookie.value}`,
      },
    });

    if (response.ok) {
      const data = await response.json();
      user = data.user;
    }
  } catch (error) {
    console.error('Failed to fetch user:', error);
  }
}
---

<header class="header">
  <div class="container">
    <div class="flex-between">
      <div class="header-left">
        <a href="/" class="logo">plue</a>
        <nav class="nav">
          <a href="/" class={currentPath === '/' ? 'active' : ''}>Repositories</a>
        </nav>
      </div>

      <div class="header-right">
        {user ? (
          <div class="user-menu">
            <span>Signed in as <strong>{user.username}</strong></span>
            <a href={`/${user.username}`}>Profile</a>
            <a href="/settings">Settings</a>
            <button id="logout-btn" class="btn-link">Sign out</button>
          </div>
        ) : (
          <div class="auth-links">
            <a href="/login">Sign in</a>
            <a href="/register" class="btn btn-primary">Sign up</a>
          </div>
        )}
      </div>
    </div>
  </div>
</header>

<style>
  .header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .user-menu {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .auth-links {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .btn-link {
    background: none;
    border: none;
    padding: 0;
    text-decoration: underline;
    cursor: pointer;
    font-family: inherit;
    font-size: inherit;
  }
</style>

<script>
  import { logout } from '../lib/auth';

  const logoutBtn = document.getElementById('logout-btn');

  if (logoutBtn) {
    logoutBtn.addEventListener('click', async () => {
      try {
        await logout();
        window.location.href = '/login';
      } catch (error) {
        console.error('Logout failed:', error);
      }
    });
  }
</script>
```

### 6. Password Reset Pages

**File**: `/Users/williamcory/plue/ui/pages/password/reset.astro`

```astro
---
import Layout from "../../layouts/Layout.astro";
---

<Layout title="Reset Password - plue">
  <div class="container">
    <div class="auth-container">
      <h1>Reset Password</h1>
      <p>Enter your email address and we'll send you a link to reset your password.</p>

      <form id="reset-form" class="auth-form">
        <div class="form-group">
          <label for="email">Email</label>
          <input
            type="email"
            id="email"
            name="email"
            required
            autocomplete="email"
          />
        </div>

        <div id="error" class="error-message" style="display: none;"></div>
        <div id="success" class="success-message" style="display: none;"></div>

        <button type="submit" class="btn btn-primary btn-block">
          Send Reset Link
        </button>
      </form>

      <div class="auth-links">
        <a href="/login">Back to sign in</a>
      </div>
    </div>
  </div>
</Layout>

<script>
  const form = document.getElementById('reset-form') as HTMLFormElement;
  const errorDiv = document.getElementById('error') as HTMLDivElement;
  const successDiv = document.getElementById('success') as HTMLDivElement;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    errorDiv.style.display = 'none';
    successDiv.style.display = 'none';

    const formData = new FormData(form);
    const email = formData.get('email') as string;

    try {
      const response = await fetch('/api/auth/password/reset-request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Failed to send reset link');
      }

      successDiv.textContent = data.message;
      successDiv.style.display = 'block';
      form.reset();
    } catch (error) {
      errorDiv.textContent = error instanceof Error ? error.message : 'Failed to send reset link';
      errorDiv.style.display = 'block';
    }
  });
</script>
```

**File**: `/Users/williamcory/plue/ui/pages/password/reset/[token].astro`

```astro
---
import Layout from "../../../layouts/Layout.astro";

const { token } = Astro.params;

if (!token) {
  return Astro.redirect('/password/reset');
}
---

<Layout title="Set New Password - plue">
  <div class="container">
    <div class="auth-container">
      <h1>Set New Password</h1>

      <form id="reset-confirm-form" class="auth-form">
        <input type="hidden" name="token" value={token} />

        <div class="form-group">
          <label for="password">New Password</label>
          <input
            type="password"
            id="password"
            name="password"
            required
            minlength="8"
            autocomplete="new-password"
          />
          <small>At least 8 characters with uppercase, lowercase, and digit</small>
        </div>

        <div id="error" class="error-message" style="display: none;"></div>
        <div id="success" class="success-message" style="display: none;"></div>

        <button type="submit" class="btn btn-primary btn-block">
          Reset Password
        </button>
      </form>

      <div class="auth-links">
        <a href="/login">Back to sign in</a>
      </div>
    </div>
  </div>
</Layout>

<script>
  const form = document.getElementById('reset-confirm-form') as HTMLFormElement;
  const errorDiv = document.getElementById('error') as HTMLDivElement;
  const successDiv = document.getElementById('success') as HTMLDivElement;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    errorDiv.style.display = 'none';
    successDiv.style.display = 'none';

    const formData = new FormData(form);
    const data = {
      token: formData.get('token') as string,
      password: formData.get('password') as string,
    };

    try {
      const response = await fetch('/api/auth/password/reset-confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.error || 'Failed to reset password');
      }

      successDiv.textContent = result.message + ' Redirecting...';
      successDiv.style.display = 'block';

      setTimeout(() => {
        window.location.href = '/login';
      }, 2000);
    } catch (error) {
      errorDiv.textContent = error instanceof Error ? error.message : 'Failed to reset password';
      errorDiv.style.display = 'block';
    }
  });
</script>
```

## Security Considerations

### 1. Password Security

- **Argon2id hashing**: Use `@node-rs/argon2` for native performance and security
- **Salt generation**: 32 bytes of cryptographically secure randomness per password
- **Complexity requirements**: Configurable, default requires mixed case + digits
- **Timing attack prevention**: Use constant-time comparison for password verification
- **Password history**: Consider storing last 3 password hashes to prevent reuse

### 2. Session Security

- **HttpOnly cookies**: Prevent XSS access to session tokens
- **Secure flag**: Enable in production (HTTPS only)
- **SameSite=Lax**: CSRF protection while allowing top-level navigation
- **Session rotation**: Regenerate session ID after login/privilege escalation
- **Expiration**: 30-day default, but refresh on activity
- **Cleanup**: Periodic job to remove expired sessions

### 3. Token Security

- **Email verification tokens**: SHA-256 hashed, 24-hour expiration
- **Password reset tokens**: SHA-256 hashed, 1-hour expiration
- **Access tokens**: SHA-256 hashed, store only last 8 characters for display
- **Single-use tokens**: Delete verification tokens after use
- **Rate limiting**: Implement on token generation endpoints

### 4. API Security

- **Input validation**: Zod schemas on all endpoints
- **SQL injection**: Use parameterized queries (postgres template strings)
- **CSRF protection**: SameSite cookies + consider CSRF tokens for state-changing operations
- **Rate limiting**: Implement on auth endpoints (login, register, password reset)
- **Account enumeration**: Don't reveal if email/username exists on password reset

### 5. Authorization Patterns

Reference implementation from Gitea:

```typescript
// Check if user owns a repository
export async function canModifyRepository(userId: number, repoId: number): Promise<boolean> {
  const [repo] = await sql<Array<{ user_id: number }>>`
    SELECT user_id FROM repositories WHERE id = ${repoId}
  `;

  if (!repo) return false;
  return repo.user_id === userId;
}

// Check if user can view a repository
export async function canViewRepository(userId: number | null, repoId: number): Promise<boolean> {
  const [repo] = await sql<Array<{ user_id: number; is_public: boolean }>>`
    SELECT user_id, is_public FROM repositories WHERE id = ${repoId}
  `;

  if (!repo) return false;
  if (repo.is_public) return true;
  if (!userId) return false;
  return repo.user_id === userId;
}
```

## Implementation Checklist

### Phase 1: Database & Core Auth

- [ ] Update database schema (`db/schema.sql`)
- [ ] Create migration script to update existing users
- [ ] Implement password hashing utilities (`server/lib/password.ts`)
- [ ] Implement session management (`server/lib/session.ts`)
- [ ] Create validation schemas (`server/lib/validation.ts`)

### Phase 2: Backend Routes

- [ ] Create auth middleware (`server/middleware/auth.ts`)
- [ ] Implement auth routes (`server/routes/auth.ts`)
  - [ ] POST /auth/register
  - [ ] POST /auth/activate
  - [ ] POST /auth/login
  - [ ] POST /auth/logout
  - [ ] GET /auth/me
  - [ ] POST /auth/password/reset-request
  - [ ] POST /auth/password/reset-confirm
- [ ] Implement user routes (`server/routes/users.ts`)
  - [ ] GET /users/:username
  - [ ] PATCH /users/me
  - [ ] POST /users/me/password
- [ ] Update server index to mount routes and middleware

### Phase 3: Frontend Pages

- [ ] Create auth API client (`ui/lib/auth.ts`)
- [ ] Update type definitions (`ui/lib/types.ts`)
- [ ] Create login page (`ui/pages/login.astro`)
- [ ] Create registration page (`ui/pages/register.astro`)
- [ ] Create password reset request page (`ui/pages/password/reset.astro`)
- [ ] Create password reset confirm page (`ui/pages/password/reset/[token].astro`)
- [ ] Update Header component with auth state
- [ ] Create settings page for profile updates

### Phase 4: Protect Existing Routes

- [ ] Apply auth middleware to repository creation
- [ ] Apply auth middleware to issue creation
- [ ] Apply auth middleware to comment posting
- [ ] Update repository pages to check ownership
- [ ] Update issue pages to check ownership
- [ ] Hide edit/delete buttons for non-owners

### Phase 5: Email Integration

- [ ] Set up email service (Resend, SendGrid, or SMTP)
- [ ] Create email templates
  - [ ] Account activation email
  - [ ] Password reset email
  - [ ] Welcome email
- [ ] Implement email sending in auth routes
- [ ] Add email verification status UI

### Phase 6: Testing & Polish

- [ ] Write Bun tests for password hashing
- [ ] Write Bun tests for session management
- [ ] Write integration tests for auth flow
- [ ] Test registration → activation → login flow
- [ ] Test password reset flow
- [ ] Test authorization on protected routes
- [ ] Add loading states to forms
- [ ] Add proper error handling
- [ ] Implement rate limiting
- [ ] Add CSRF protection

### Phase 7: Documentation

- [ ] Document environment variables needed
- [ ] Document email configuration
- [ ] Update README with auth setup instructions
- [ ] Add API documentation for auth endpoints
- [ ] Create migration guide for existing deployments

## Environment Variables

Add to `.env`:

```bash
# Session
SESSION_SECRET=your-random-secret-here

# Email (choose provider)
EMAIL_FROM=noreply@plue.local

# Resend (recommended)
RESEND_API_KEY=re_...

# Or SMTP
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user
SMTP_PASS=pass

# Security
ENVIRONMENT=development # or production
SECURE_COOKIES=false # true in production
```

## References

This implementation is based on Gitea's authentication system, adapted for Plue's Bun/Hono/Astro stack:

- **Gitea User Model**: `/Users/williamcory/plue/gitea/models/user/user.go`
- **Gitea Auth Routes**: `/Users/williamcory/plue/gitea/routers/web/auth/auth.go`
- **Gitea Session Management**: `/Users/williamcory/plue/gitea/models/auth/session.go`
- **Gitea Password Hashing**: `/Users/williamcory/plue/gitea/modules/auth/password/hash/`
- **Gitea Sign-In Logic**: `/Users/williamcory/plue/gitea/services/auth/signin.go`

Key differences from Gitea:
- Using Argon2id instead of multiple hash algorithms
- Using PostgreSQL instead of multiple DB backends
- Using cookie sessions instead of go-chi/session
- Simplified to essential features (no OAuth2, 2FA, LDAP initially)
- TypeScript instead of Go
- Bun runtime instead of Go runtime
