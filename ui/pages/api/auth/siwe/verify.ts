import type { APIRoute } from 'astro';
import { SiweMessage } from 'siwe';
import { randomBytes } from 'crypto';
import sql from '../../../../lib/db';
import { createSessionCookie } from '../../../../lib/auth-helpers';

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { message, signature } = body;

    if (!message || !signature) {
      return new Response(JSON.stringify({ error: 'Missing message or signature' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Parse and verify SIWE message
    // SiweMessage can accept either a string (EIP-4361) or an object
    let siweMessage: InstanceType<typeof SiweMessage>;
    try {
      siweMessage = new SiweMessage(message);
    } catch (parseError) {
      console.error('SIWE parse error:', parseError);
      console.error('Raw message:', message);
      return new Response(JSON.stringify({
        error: 'Invalid SIWE message format',
        details: parseError instanceof Error ? parseError.message : 'Unknown error'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate nonce exists and is not expired/used
    const [nonceRecord] = await sql`
      SELECT nonce, used_at
      FROM siwe_nonces
      WHERE nonce = ${siweMessage.nonce} AND expires_at > NOW()
    `;

    if (!nonceRecord) {
      return new Response(JSON.stringify({ error: 'Invalid or expired nonce' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (nonceRecord.used_at) {
      return new Response(JSON.stringify({ error: 'Nonce already used' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Verify the signature
    try {
      await siweMessage.verify({ signature });
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid signature' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const walletAddress = siweMessage.address.toLowerCase();

    // Mark nonce as used
    await sql`
      UPDATE siwe_nonces SET used_at = NOW(), wallet_address = ${walletAddress}
      WHERE nonce = ${siweMessage.nonce}
    `;

    // Check if user exists, auto-create if not
    let [user] = await sql`
      SELECT id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
      FROM users
      WHERE wallet_address = ${walletAddress}
    `;

    if (!user) {
      // Generate username from wallet address
      const username = walletAddress.slice(0, 6) + walletAddress.slice(-4);

      // Create user
      [user] = await sql`
        INSERT INTO users (username, lower_username, wallet_address, is_active)
        VALUES (${username}, ${username.toLowerCase()}, ${walletAddress}, true)
        RETURNING id, username, email, display_name, is_admin, is_active, prohibit_login, wallet_address
      `;
    }

    if (user.prohibit_login) {
      return new Response(JSON.stringify({ error: 'Account is disabled' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create session
    const sessionId = randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    await sql`
      INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
      VALUES (${sessionId}, ${user.id}, ${user.username}, ${user.is_admin || false}, ${expiresAt})
    `;

    // Update last login
    await sql`UPDATE users SET last_login_at = NOW() WHERE id = ${user.id}`;

    const responseData = {
      message: 'Login successful',
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        isActive: user.is_active,
        isAdmin: user.is_admin,
        walletAddress: user.wallet_address
      }
    };

    return new Response(JSON.stringify(responseData), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Set-Cookie': createSessionCookie(sessionId)
      }
    });
  } catch (error) {
    console.error('SIWE verification error:', error);
    return new Response(JSON.stringify({ error: 'Verification failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
