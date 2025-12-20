/**
 * SSH Public Key Authentication.
 *
 * Validates SSH public keys against the database.
 */

import { timingSafeEqual, createHash } from 'crypto';
import type { AuthContext } from 'ssh2';
import { utils } from 'ssh2';
import sql from '../db/client';

// The SSH username must be 'git' (like GitHub)
const ALLOWED_USER = Buffer.from('git');

// Store authenticated user info in a WeakMap keyed by client
export const authenticatedUsers = new WeakMap<object, { userId: number; keyId: number }>();

/**
 * Calculate SSH key fingerprint (SHA256).
 */
function getFingerprint(key: Buffer): string {
  const hash = createHash('sha256').update(key).digest('base64');
  return `SHA256:${hash.replace(/=+$/, '')}`;
}

/**
 * Handle SSH authentication.
 */
export async function authenticate(ctx: AuthContext): Promise<void> {
  const user = Buffer.from(ctx.username);

  // Only allow 'git' as username
  if (user.length !== ALLOWED_USER.length || !timingSafeEqual(user, ALLOWED_USER)) {
    console.log(`SSH auth failed: invalid username '${ctx.username}'`);
    ctx.reject(['publickey']);
    return;
  }

  // Only allow public key authentication
  if (ctx.method !== 'publickey') {
    console.log(`SSH auth failed: method '${ctx.method}' not allowed`);
    ctx.reject(['publickey']);
    return;
  }

  try {
    const keyData = ctx.key;
    if (!keyData) {
      ctx.reject(['publickey']);
      return;
    }

    // Get fingerprint of the presented key
    const fingerprint = getFingerprint(keyData.data);

    // Look up key in database
    const keys = await sql`
      SELECT id, user_id, public_key FROM ssh_keys WHERE fingerprint = ${fingerprint}
    `;

    if (keys.length === 0) {
      console.log(`SSH auth failed: unknown key ${fingerprint}`);
      ctx.reject(['publickey']);
      return;
    }

    const dbKey = keys[0];

    // Parse the stored public key
    const storedKey = utils.parseKey(dbKey.public_key);
    if (!storedKey || storedKey instanceof Error) {
      console.log(`SSH auth failed: could not parse stored key`);
      ctx.reject(['publickey']);
      return;
    }

    const storedPublicSSH = storedKey.getPublicSSH();

    // Verify key matches
    if (keyData.data.length !== storedPublicSSH.length ||
        !timingSafeEqual(keyData.data, storedPublicSSH)) {
      console.log(`SSH auth failed: key mismatch`);
      ctx.reject(['publickey']);
      return;
    }

    // Verify signature if present (actual authentication vs just checking)
    if (ctx.signature) {
      const verified = storedKey.verify(ctx.blob!, ctx.signature, ctx.hashAlgo);
      if (!verified) {
        console.log(`SSH auth failed: signature verification failed`);
        ctx.reject(['publickey']);
        return;
      }
    }

    // Store authenticated user info for later use in session handler
    // We'll attach it to the auth context's client
    const clientInfo = { userId: dbKey.user_id, keyId: dbKey.id };
    (ctx as any)._plueUser = clientInfo;

    console.log(`SSH auth success: user_id=${dbKey.user_id}, key_id=${dbKey.id}`);
    ctx.accept();
  } catch (error) {
    console.error('SSH auth error:', error);
    ctx.reject(['publickey']);
  }
}
