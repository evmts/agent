import type { APIRoute } from 'astro';
import { randomBytes } from 'crypto';
import { parseSiweMessage, verifySiweMessage } from 'viem/siwe';
import { Porto } from 'porto';
import { RelayClient } from 'porto/viem';
import { siwe } from '@plue/db';
import { createSessionCookie } from '../../../../lib/auth-helpers';

// Porto instance for signature verification
const porto = Porto.create();

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

    // Parse SIWE message using Viem
    let siweMessage: ReturnType<typeof parseSiweMessage>;
    try {
      siweMessage = parseSiweMessage(message);
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

    if (!siweMessage.nonce || !siweMessage.address) {
      return new Response(JSON.stringify({ error: 'Invalid SIWE message: missing nonce or address' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate nonce exists and is not expired/used
    const nonceRecord = await siwe.validateNonce(siweMessage.nonce);

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

    // Verify the signature using Porto's RelayClient (supports ERC-6492/ERC-1271)
    try {
      const client = RelayClient.fromPorto(porto, { chainId: siweMessage.chainId });
      const valid = await verifySiweMessage(client, {
        message,
        signature,
      });

      if (!valid) {
        return new Response(JSON.stringify({ error: 'Invalid signature' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    } catch (verifyError) {
      console.error('Signature verification error:', verifyError);
      return new Response(JSON.stringify({ error: 'Invalid signature' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const walletAddress = siweMessage.address.toLowerCase();

    // Mark nonce as used
    await siwe.markNonceUsed(siweMessage.nonce, walletAddress);

    // Check if user exists, auto-create if not
    const user = await siwe.getOrCreateUserByWallet(walletAddress);

    if (user.prohibit_login) {
      return new Response(JSON.stringify({ error: 'Account is disabled' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create session
    const sessionId = randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    await siwe.createAuthSession(user.id, sessionId, user.username, user.is_admin || false, expiresAt);

    // Update last login
    await siwe.updateLastLogin(user.id);

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
