import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import { updateProfileSchema, changePasswordSchema } from '../lib/validation';
import { hashPassword, verifyPassword, generateSalt, validatePasswordComplexity } from '../lib/password';
import sql from '../../db/client';

const app = new Hono();

/**
 * GET /users/:username
 * Get public user profile
 */
app.get('/:username', async (c) => {
  try {
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
  } catch (error) {
    console.error('Get user profile error:', error);
    return c.json({ error: 'Failed to fetch user profile' }, 500);
  }
});

/**
 * PATCH /users/me
 * Update own profile (requires auth)
 */
app.patch('/me', requireAuth, requireActiveAccount, zValidator('json', updateProfileSchema), async (c) => {
  try {
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

    // Build the SQL update query manually since we need dynamic set clauses
    const setClause = setClauses.join(', ');
    const query = `
      UPDATE users
      SET ${setClause}, updated_at = NOW()
      WHERE id = $${values.length + 1}
    `;
    values.push(user.id);

    // Execute the update using sql.unsafe for dynamic query
    await sql.unsafe(query, values);

    return c.json({ message: 'Profile updated successfully' });
  } catch (error) {
    console.error('Update profile error:', error);
    return c.json({ error: 'Failed to update profile' }, 500);
  }
});

/**
 * POST /users/me/password
 * Change password (requires auth)
 */
app.post('/me/password', requireAuth, zValidator('json', changePasswordSchema), async (c) => {
  try {
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
  } catch (error) {
    console.error('Change password error:', error);
    return c.json({ error: 'Failed to change password' }, 500);
  }
});

export default app;