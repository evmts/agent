import { Hono } from 'hono';
import { createHash, randomBytes } from 'crypto';
import { zValidator } from '@hono/zod-validator';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import { sql } from '../../db/client';
import { createAccessTokenSchema } from '../lib/validation';

const app = new Hono();

// GET /user/tokens - List current user's access tokens
app.get('/', requireAuth, requireActiveAccount, async (c) => {
  const user = c.get('user');

  const tokens = await sql`
    SELECT
      id,
      name,
      token_last_eight,
      scopes,
      created_at,
      last_used_at
    FROM access_tokens
    WHERE user_id = ${user.id}
    ORDER BY created_at DESC
  `;

  return c.json({ tokens });
});

// POST /user/tokens - Create new access token
app.post('/', requireAuth, requireActiveAccount, zValidator('json', createAccessTokenSchema), async (c) => {
  const user = c.get('user');
  const { name, scopes } = c.req.valid('json');

  // Generate random token (32 bytes = 64 hex characters)
  const token = randomBytes(32).toString('hex');
  const tokenHash = createHash('sha256').update(token).digest('hex');
  const tokenLastEight = token.slice(-8);

  // Insert into database
  const result = await sql`
    INSERT INTO access_tokens (
      user_id,
      name,
      token_hash,
      token_last_eight,
      scopes
    )
    VALUES (
      ${user.id},
      ${name.trim()},
      ${tokenHash},
      ${tokenLastEight},
      ${scopes.join(',')}
    )
    RETURNING id, name, token_last_eight, scopes, created_at
  `;

  // Return the full token ONCE (this is the only time it will be shown)
  return c.json({
    token: result[0],
    fullToken: token,
    message: 'Token created successfully. Save it now - you won\'t be able to see it again!'
  }, 201);
});

// DELETE /user/tokens/:id - Revoke an access token
app.delete('/:id', requireAuth, requireActiveAccount, async (c) => {
  const user = c.get('user');
  const tokenId = c.req.param('id');

  // Validate tokenId is a number
  const id = parseInt(tokenId, 10);
  if (isNaN(id)) {
    return c.json({ error: 'Invalid token ID' }, 400);
  }

  // Delete the token (only if it belongs to the user)
  const result = await sql`
    DELETE FROM access_tokens
    WHERE id = ${id} AND user_id = ${user.id}
    RETURNING id
  `;

  if (result.length === 0) {
    return c.json({ error: 'Token not found' }, 404);
  }

  return c.json({ message: 'Token revoked successfully' });
});

export default app;
