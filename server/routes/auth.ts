import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { getCookie } from 'hono/cookie';
import { createHash } from 'crypto';
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
import { sendActivationEmail, sendPasswordResetEmail } from '../lib/email';
import { authRateLimit, emailRateLimit } from '../middleware/rate-limit';
import sql from '../../db/client';

const app = new Hono();

/**
 * POST /auth/register
 * Register a new user account
 */
app.post('/register', authRateLimit, zValidator('json', registerSchema), async (c) => {
  try {
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

    // Send activation email
    try {
      await sendActivationEmail(email, username, token);
    } catch (emailError) {
      console.error('Failed to send activation email:', emailError);
      // Don't fail registration if email fails
    }

    return c.json({
      message: 'Registration successful. Please check your email to activate your account.',
      userId: user.id,
    }, 201);
  } catch (error) {
    console.error('Registration error:', error);
    return c.json({ error: 'Registration failed' }, 500);
  }
});

/**
 * POST /auth/activate
 * Activate user account via email token
 */
app.post('/activate', async (c) => {
  try {
    const body = await c.req.json();
    const { token } = body;

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
  } catch (error) {
    console.error('Activation error:', error);
    return c.json({ error: 'Activation failed' }, 500);
  }
});

/**
 * POST /auth/login
 * Authenticate user and create session
 */
app.post('/login', authRateLimit, zValidator('json', loginSchema), async (c) => {
  try {
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
  } catch (error) {
    console.error('Login error:', error);
    return c.json({ error: 'Login failed' }, 500);
  }
});

/**
 * POST /auth/logout
 * Destroy session and clear cookie
 */
app.post('/logout', async (c) => {
  try {
    const sessionKey = getCookie(c, 'plue_session');

    if (sessionKey) {
      await deleteSession(sessionKey);
    }

    clearSessionCookie(c);

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

/**
 * POST /auth/password/reset-request
 * Request password reset email
 */
app.post('/password/reset-request', emailRateLimit, zValidator('json', passwordResetRequestSchema), async (c) => {
  try {
    const { email } = c.req.valid('json');

    // Find user (don't reveal if user exists)
    const [user] = await sql<Array<{ id: number; username: string }>>`
      SELECT id, username FROM users
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

      // Send password reset email
      try {
        await sendPasswordResetEmail(email, user.username, token);
      } catch (emailError) {
        console.error('Failed to send password reset email:', emailError);
        // Don't reveal email send failure
      }
    }

    // Always return success to avoid user enumeration
    return c.json({ message: 'If the email exists, a password reset link has been sent' });
  } catch (error) {
    console.error('Password reset request error:', error);
    return c.json({ error: 'Failed to process password reset request' }, 500);
  }
});

/**
 * POST /auth/password/reset-confirm
 * Confirm password reset with token
 */
app.post('/password/reset-confirm', zValidator('json', passwordResetConfirmSchema), async (c) => {
  try {
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
  } catch (error) {
    console.error('Password reset confirm error:', error);
    return c.json({ error: 'Password reset failed' }, 500);
  }
});

export default app;