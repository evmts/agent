import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import { updateProfileSchema } from '../lib/validation';
import sql from '../../db/client';

const app = new Hono();

/**
 * GET /users/search?q=query
 * Search users by username (for autocomplete)
 */
app.get('/search', async (c) => {
  try {
    const query = c.req.query('q') || '';

    // Return empty array if query is too short
    if (query.length < 1) {
      return c.json({ users: [] });
    }

    // Search users by username prefix (case-insensitive)
    const users = await sql<Array<{
      username: string;
      display_name: string | null;
    }>>`
      SELECT username, display_name
      FROM users
      WHERE lower_username LIKE ${query.toLowerCase() + '%'}
        AND is_active = true
        AND prohibit_login = false
      ORDER BY lower_username
      LIMIT 10
    `;

    return c.json({ users });
  } catch (error) {
    console.error('User search error:', error);
    return c.json({ error: 'Failed to search users' }, 500);
  }
});

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
      wallet_address: string | null;
      created_at: Date;
    }>>`
      SELECT id, username, display_name, bio, avatar_url, wallet_address, created_at
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

    if (updates.email !== undefined) {
      setClauses.push(`email = $${values.length + 1}`);
      values.push(updates.email);
      setClauses.push(`lower_email = $${values.length + 1}`);
      values.push(updates.email.toLowerCase());
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

export default app;
