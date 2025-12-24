/**
 * AuthDO - Durable Object for authentication state
 *
 * Handles nonces and sessions with strong consistency guarantees.
 * Uses Durable Objects instead of KV because:
 * - Strong consistency (nonces must not be reused - critical for SIWE security)
 * - Per-user isolation for future session/preferences storage
 * - Atomic operations on nonce check-and-delete
 *
 * This DO is keyed by:
 * - "global-nonces" - For nonce storage/validation (global singleton)
 * - Wallet address - For per-user session data (future: preferences, blocklist)
 */

export interface NonceData {
  createdAt: number;
  expiresAt: number;
}

export interface SessionData {
  address: string;
  createdAt: number;
  lastUsedAt: number;
  blocked?: boolean;
}

interface Env {
  // No bindings needed inside DO
}

/** Nonce TTL: 5 minutes */
const NONCE_TTL_MS = 5 * 60 * 1000;

/** Session TTL: 30 days (for cleanup, JWTs have their own expiry) */
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export class AuthDO implements DurableObject {
  private state: DurableObjectState;
  private storage: DurableObjectStorage;

  constructor(state: DurableObjectState, _env: Env) {
    this.state = state;
    this.storage = state.storage;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      // Nonce operations
      if (path === '/nonce' && request.method === 'POST') {
        return this.storeNonce(request);
      }

      if (path.startsWith('/nonce/') && request.method === 'DELETE') {
        const nonce = path.slice('/nonce/'.length);
        return this.consumeNonce(nonce);
      }

      if (path.startsWith('/nonce/') && request.method === 'GET') {
        const nonce = path.slice('/nonce/'.length);
        return this.checkNonce(nonce);
      }

      // Session operations (for future blocklist/invalidation)
      if (path === '/session' && request.method === 'POST') {
        return this.createSession(request);
      }

      if (path === '/session' && request.method === 'DELETE') {
        return this.deleteSession(request);
      }

      if (path === '/session/verify' && request.method === 'POST') {
        return this.verifySession(request);
      }

      // Cleanup old data
      if (path === '/cleanup' && request.method === 'POST') {
        return this.cleanup();
      }

      return new Response('Not Found', { status: 404 });
    } catch (error) {
      console.error('AuthDO error:', error);
      return new Response(
        JSON.stringify({ error: 'Internal error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }
  }

  /**
   * Store a new nonce with TTL
   * POST /nonce { nonce: string }
   */
  private async storeNonce(request: Request): Promise<Response> {
    const { nonce } = await request.json() as { nonce: string };

    if (!nonce || typeof nonce !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Invalid nonce' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const now = Date.now();
    const data: NonceData = {
      createdAt: now,
      expiresAt: now + NONCE_TTL_MS,
    };

    await this.storage.put(`nonce:${nonce}`, data);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 201, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Check if nonce exists (without consuming it)
   * GET /nonce/:nonce
   */
  private async checkNonce(nonce: string): Promise<Response> {
    const data = await this.storage.get<NonceData>(`nonce:${nonce}`);

    if (!data) {
      return new Response(
        JSON.stringify({ valid: false, error: 'Nonce not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const now = Date.now();
    if (data.expiresAt < now) {
      // Clean up expired nonce
      await this.storage.delete(`nonce:${nonce}`);
      return new Response(
        JSON.stringify({ valid: false, error: 'Nonce expired' }),
        { status: 410, headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ valid: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Consume nonce (check and delete atomically)
   * DELETE /nonce/:nonce
   *
   * This is the critical operation for replay protection.
   * Returns 200 if nonce was valid and consumed, 404/410 otherwise.
   */
  private async consumeNonce(nonce: string): Promise<Response> {
    // Use transaction for atomic check-and-delete
    const data = await this.storage.get<NonceData>(`nonce:${nonce}`);

    if (!data) {
      return new Response(
        JSON.stringify({ consumed: false, error: 'Nonce not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const now = Date.now();
    if (data.expiresAt < now) {
      await this.storage.delete(`nonce:${nonce}`);
      return new Response(
        JSON.stringify({ consumed: false, error: 'Nonce expired' }),
        { status: 410, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Delete nonce (consume it)
    await this.storage.delete(`nonce:${nonce}`);

    return new Response(
      JSON.stringify({ consumed: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Store session data for a user
   * POST /session { address: string }
   *
   * Used for future session invalidation and blocklist checking.
   */
  private async createSession(request: Request): Promise<Response> {
    const { address } = await request.json() as { address: string };

    if (!address || typeof address !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Invalid address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const now = Date.now();
    const data: SessionData = {
      address: address.toLowerCase(),
      createdAt: now,
      lastUsedAt: now,
      blocked: false,
    };

    await this.storage.put(`session:${address.toLowerCase()}`, data);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 201, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Delete/invalidate session
   * DELETE /session { address: string }
   */
  private async deleteSession(request: Request): Promise<Response> {
    const { address } = await request.json() as { address: string };

    if (!address) {
      return new Response(
        JSON.stringify({ error: 'Missing address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    await this.storage.delete(`session:${address.toLowerCase()}`);

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Verify session is not blocked
   * POST /session/verify { address: string }
   *
   * Called on sensitive operations to check blocklist.
   */
  private async verifySession(request: Request): Promise<Response> {
    const { address } = await request.json() as { address: string };

    if (!address) {
      return new Response(
        JSON.stringify({ valid: false, error: 'Missing address' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const data = await this.storage.get<SessionData>(`session:${address.toLowerCase()}`);

    // No session data means not blocked (session data is optional)
    if (!data) {
      return new Response(
        JSON.stringify({ valid: true }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (data.blocked) {
      return new Response(
        JSON.stringify({ valid: false, error: 'Session blocked' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Update last used time
    data.lastUsedAt = Date.now();
    await this.storage.put(`session:${address.toLowerCase()}`, data);

    return new Response(
      JSON.stringify({ valid: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  /**
   * Clean up expired nonces and old sessions
   * POST /cleanup
   */
  private async cleanup(): Promise<Response> {
    const now = Date.now();
    let deletedNonces = 0;
    let deletedSessions = 0;

    // Get all keys and clean up expired ones
    const entries = await this.storage.list();

    for (const [key, value] of entries) {
      if (key.startsWith('nonce:')) {
        const data = value as NonceData;
        if (data.expiresAt < now) {
          await this.storage.delete(key);
          deletedNonces++;
        }
      } else if (key.startsWith('session:')) {
        const data = value as SessionData;
        // Clean up sessions not used for 30 days
        if (data.lastUsedAt + SESSION_TTL_MS < now) {
          await this.storage.delete(key);
          deletedSessions++;
        }
      }
    }

    return new Response(
      JSON.stringify({ deletedNonces, deletedSessions }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }
}
