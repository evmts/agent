import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { createNonce, verifySiweSignature } from '../lib/siwe';
import { createSession, deleteSession } from '../lib/session';
import { setSessionCookie, clearSessionCookie } from '../middleware/auth';
import { signJWT, setJWTCookie, clearJWTCookie } from '../lib/jwt';
import { authRateLimit } from '../middleware/rate-limit';
import sql from '../../db/client';
import { getCookie } from 'hono/cookie';

const app = new Hono();

// Validation schemas
const verifySchema = z.object({
  message: z.string().min(1, 'Message is required'),
  signature: z.string().regex(/^0x[a-fA-F0-9]+$/, 'Invalid signature format'),
});

const registerSchema = z.object({
  message: z.string().min(1, 'Message is required'),
  signature: z.string().regex(/^0x[a-fA-F0-9]+$/, 'Invalid signature format'),
  username: z.string()
    .min(3, 'Username must be at least 3 characters')
    .max(39, 'Username must be at most 39 characters')
    .regex(
      /^[a-zA-Z0-9]([a-zA-Z0-9-_]*[a-zA-Z0-9])?$/,
      'Username must start and end with alphanumeric characters'
    ),
  displayName: z.string().max(255).optional(),
});

/**
 * GET /auth/siwe/nonce
 * Generate a nonce for SIWE authentication
 */
app.get('/siwe/nonce', async (c) => {
  const nonce = await createNonce();
  return c.json({ nonce });
});

/**
 * POST /auth/siwe/verify
 * Verify SIWE signature and authenticate existing user
 * Returns 404 if wallet not registered (must use /siwe/register)
 */
app.post('/siwe/verify', authRateLimit, zValidator('json', verifySchema), async (c) => {
  try {
    const { message, signature } = c.req.valid('json');

    // Verify the SIWE signature
    const result = await verifySiweSignature(message, signature as `0x${string}`);

    if (!result.valid || !result.address) {
      return c.json({ error: result.error || 'Invalid signature' }, 401);
    }

    const walletAddress = result.address.toLowerCase();

    // Check if user exists
    const [user] = await sql<Array<{
      id: number;
      username: string;
      email: string | null;
      is_admin: boolean;
      is_active: boolean;
      prohibit_login: boolean;
    }>>`
      SELECT id, username, email, is_admin, is_active, prohibit_login
      FROM users
      WHERE wallet_address = ${walletAddress}
    `;

    if (!user) {
      // User needs to register first
      return c.json({
        error: 'Wallet not registered',
        code: 'WALLET_NOT_REGISTERED',
        address: walletAddress,
      }, 404);
    }

    if (user.prohibit_login) {
      return c.json({ error: 'Account is disabled' }, 403);
    }

    // Create session
    const sessionKey = await createSession(user.id, user.username, user.is_admin);

    // Generate JWT for edge authentication
    const jwt = await signJWT({
      userId: user.id,
      username: user.username,
      isAdmin: user.is_admin,
    });

    // Update last login
    await sql`
      UPDATE users SET last_login_at = NOW(), updated_at = NOW()
      WHERE id = ${user.id}
    `;

    // Set cookies
    setSessionCookie(c, sessionKey);
    setJWTCookie(c.res.headers, jwt);

    return c.json({
      message: 'Login successful',
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        isActive: user.is_active,
        isAdmin: user.is_admin,
        walletAddress,
      },
    });
  } catch (error) {
    console.error('SIWE verify error:', error);
    return c.json({ error: 'Verification failed' }, 500);
  }
});

/**
 * POST /auth/siwe/register
 * Register new user with SIWE (requires username)
 */
app.post('/siwe/register', authRateLimit, zValidator('json', registerSchema), async (c) => {
  try {
    const { message, signature, username, displayName } = c.req.valid('json');

    // Verify SIWE signature
    const result = await verifySiweSignature(message, signature as `0x${string}`);

    if (!result.valid || !result.address) {
      return c.json({ error: result.error || 'Invalid signature' }, 401);
    }

    const walletAddress = result.address.toLowerCase();

    // Check if wallet already registered
    const [existingWallet] = await sql<Array<{ id: number }>>`
      SELECT id FROM users WHERE wallet_address = ${walletAddress}
    `;

    if (existingWallet) {
      return c.json({ error: 'Wallet already registered' }, 409);
    }

    // Check if username taken
    const [existingUsername] = await sql<Array<{ id: number }>>`
      SELECT id FROM users WHERE lower_username = ${username.toLowerCase()}
    `;

    if (existingUsername) {
      return c.json({ error: 'Username already taken' }, 409);
    }

    // Create user (SIWE users are active by default - no email verification needed)
    const [user] = await sql<Array<{ id: number }>>`
      INSERT INTO users (
        username, lower_username,
        display_name, wallet_address,
        is_active, created_at, updated_at
      ) VALUES (
        ${username}, ${username.toLowerCase()},
        ${displayName || username}, ${walletAddress},
        true, NOW(), NOW()
      )
      RETURNING id
    `;

    // Create session
    const sessionKey = await createSession(user.id, username, false);

    // Generate JWT
    const jwt = await signJWT({
      userId: user.id,
      username,
      isAdmin: false,
    });

    // Set cookies
    setSessionCookie(c, sessionKey);
    setJWTCookie(c.res.headers, jwt);

    return c.json({
      message: 'Registration successful',
      user: {
        id: user.id,
        username,
        isActive: true,
        isAdmin: false,
        walletAddress,
      },
    }, 201);
  } catch (error) {
    console.error('SIWE register error:', error);
    return c.json({ error: 'Registration failed' }, 500);
  }
});

/**
 * POST /auth/logout
 * Destroy session and clear cookies
 */
app.post('/logout', async (c) => {
  try {
    const sessionKey = getCookie(c, 'plue_session');

    if (sessionKey) {
      await deleteSession(sessionKey);
    }

    // Clear both session cookie (origin) and JWT cookie (edge)
    clearSessionCookie(c);
    clearJWTCookie(c.res.headers);

    return c.json({ message: 'Logout successful' });
  } catch (error) {
    console.error('Logout error:', error);
    return c.json({ error: 'Logout failed' }, 500);
  }
});

/**
 * GET /auth/me
 * Get current authenticated user
 */
app.get('/me', async (c) => {
  const user = c.get('user');
  return c.json({ user: user || null });
});

export default app;
