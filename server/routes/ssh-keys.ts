import { Hono } from 'hono';
import { createHash } from 'crypto';
import { requireAuth, requireActiveAccount } from '../middleware/auth';
import { sql } from '../../db/client';

const app = new Hono();

function calculateFingerprint(publicKey: string): string {
  // Extract the base64 part of the key
  const parts = publicKey.trim().split(' ');
  if (parts.length < 2) throw new Error('Invalid key format');
  const keyData = Buffer.from(parts[1], 'base64');
  const hash = createHash('sha256').update(keyData).digest('base64');
  return `SHA256:${hash.replace(/=+$/, '')}`;
}

function parseKeyType(publicKey: string): string {
  const parts = publicKey.trim().split(' ');
  if (parts.length < 1) throw new Error('Invalid key format');
  return parts[0];
}

function validatePublicKey(publicKey: string): boolean {
  const validKeyTypes = ['ssh-rsa', 'ssh-ed25519', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521'];
  const keyType = parseKeyType(publicKey);
  return validKeyTypes.includes(keyType);
}

// GET /ssh-keys - List current user's SSH keys
app.get('/', requireAuth, requireActiveAccount, async (c) => {
  const user = c.get('user');

  const keys = await sql`
    SELECT id, name, fingerprint, key_type, created_at
    FROM ssh_keys
    WHERE user_id = ${user.id}
    ORDER BY created_at DESC
  `;

  return c.json({ keys });
});

// POST /ssh-keys - Add new SSH key
app.post('/', requireAuth, requireActiveAccount, async (c) => {
  const user = c.get('user');

  let body;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const { name, publicKey } = body;

  // Validate input
  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return c.json({ error: 'Name is required' }, 400);
  }

  if (!publicKey || typeof publicKey !== 'string') {
    return c.json({ error: 'Public key is required' }, 400);
  }

  // Validate public key format
  if (!validatePublicKey(publicKey)) {
    return c.json({
      error: 'Invalid public key format. Must start with ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp*'
    }, 400);
  }

  // Calculate fingerprint and key type
  let fingerprint: string;
  let keyType: string;

  try {
    fingerprint = calculateFingerprint(publicKey);
    keyType = parseKeyType(publicKey);
  } catch (error) {
    return c.json({
      error: 'Failed to parse public key',
      details: error instanceof Error ? error.message : 'Unknown error'
    }, 400);
  }

  // Check for duplicate fingerprints
  const existing = await sql`
    SELECT id FROM ssh_keys
    WHERE fingerprint = ${fingerprint}
  `;

  if (existing.length > 0) {
    return c.json({ error: 'SSH key already exists' }, 409);
  }

  // Insert the new key
  const result = await sql`
    INSERT INTO ssh_keys (user_id, name, public_key, fingerprint, key_type)
    VALUES (${user.id}, ${name.trim()}, ${publicKey.trim()}, ${fingerprint}, ${keyType})
    RETURNING id, name, fingerprint, key_type, created_at
  `;

  return c.json({ key: result[0] }, 201);
});

// DELETE /ssh-keys/:id - Delete an SSH key
app.delete('/:id', requireAuth, requireActiveAccount, async (c) => {
  const user = c.get('user');
  const keyId = c.req.param('id');

  // Validate keyId is a number
  const id = parseInt(keyId, 10);
  if (isNaN(id)) {
    return c.json({ error: 'Invalid key ID' }, 400);
  }

  // Check if key exists and belongs to user
  const existing = await sql`
    SELECT id FROM ssh_keys
    WHERE id = ${id} AND user_id = ${user.id}
  `;

  if (existing.length === 0) {
    return c.json({ error: 'SSH key not found' }, 404);
  }

  // Delete the key
  await sql`
    DELETE FROM ssh_keys
    WHERE id = ${id} AND user_id = ${user.id}
  `;

  return c.json({ message: 'SSH key deleted' });
});

export default app;
