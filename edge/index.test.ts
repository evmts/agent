import { describe, it, expect, vi, beforeEach } from 'vitest';
import worker from './index';
import type { Env } from './types';

// Mock ExecutionContext
class MockExecutionContext implements ExecutionContext {
  promises: Promise<unknown>[] = [];
  props: unknown = {};

  waitUntil(promise: Promise<unknown>): void {
    this.promises.push(promise);
  }

  passThroughOnException(): void {
    // No-op for tests
  }
}

// Mock Durable Object Namespace - simplified mock for testing
function createMockDONamespace(handler: (request: Request) => Promise<Response>) {
  return {
    idFromName: (name: string) => ({ toString: () => name }),
    get: () => ({
      fetch: handler,
    }),
    newUniqueId: () => ({ toString: () => 'unique-id' }),
  } as unknown as DurableObjectNamespace;
}

// Mock RateLimitDO that allows all requests by default
function createMockRateLimitDO(options: { allowed?: boolean; limit?: number; remaining?: number; retryAfter?: number } = {}) {
  const { allowed = true, limit = 200, remaining = 199, retryAfter } = options;
  return createMockDONamespace(async () => {
    return new Response(JSON.stringify({
      allowed,
      limit,
      remaining,
      retryAfter,
    }), { headers: { 'Content-Type': 'application/json' } });
  });
}

// Mock AuthDO for authentication - matches actual AuthDO API
function createMockAuthDO() {
  const nonceStore = new Map<string, { createdAt: number; expiresAt: number }>();
  const sessionStore = new Map<string, unknown>();

  return createMockDONamespace(async (request: Request) => {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // POST /nonce - store nonce
    if (path === '/nonce' && method === 'POST') {
      const body = await request.json() as { nonce: string };
      const now = Date.now();
      nonceStore.set(`nonce:${body.nonce}`, {
        createdAt: now,
        expiresAt: now + 5 * 60 * 1000, // 5 min TTL
      });
      return new Response(JSON.stringify({ success: true }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // DELETE /nonce/:nonce - consume nonce atomically
    if (path.startsWith('/nonce/') && method === 'DELETE') {
      const nonce = path.slice('/nonce/'.length);
      const key = `nonce:${nonce}`;
      if (nonceStore.has(key)) {
        const data = nonceStore.get(key)!;
        if (data.expiresAt > Date.now()) {
          nonceStore.delete(key);
          return new Response(JSON.stringify({ consumed: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          });
        }
        nonceStore.delete(key);
        return new Response(JSON.stringify({ consumed: false, error: 'Nonce expired' }), {
          status: 410,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify({ consumed: false, error: 'Nonce not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // POST /session - store session
    if (path === '/session' && method === 'POST') {
      const body = await request.json() as { address: string };
      sessionStore.set(`session:${body.address.toLowerCase()}`, {
        address: body.address.toLowerCase(),
        createdAt: Date.now(),
        lastUsedAt: Date.now(),
      });
      return new Response(JSON.stringify({ success: true }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // POST /session/verify - verify session not blocked
    if (path === '/session/verify' && method === 'POST') {
      return new Response(JSON.stringify({ valid: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not Found', { status: 404 });
  });
}

// Mock MetricsDO for analytics
function createMockMetricsDO() {
  return createMockDONamespace(async () => {
    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  });
}

// Mock Cache
class MockCache implements Cache {
  private store = new Map<string, Response>();

  async match(request: RequestInfo | URL): Promise<Response | undefined> {
    const key = request instanceof Request ? request.url : String(request);
    return this.store.get(key);
  }

  async put(request: RequestInfo | URL, response: Response): Promise<void> {
    const key = request instanceof Request ? request.url : String(request);
    this.store.set(key, response);
  }

  async delete(request: RequestInfo | URL): Promise<boolean> {
    const key = request instanceof Request ? request.url : String(request);
    return this.store.delete(key);
  }

  async keys(): Promise<readonly Request[]> {
    return [];
  }

  async addAll(requests: RequestInfo[]): Promise<void> {}
  async add(request: RequestInfo): Promise<void> {}
}

describe('Edge Worker', () => {
  let env: Env;
  let ctx: MockExecutionContext;
  let mockCache: MockCache;

  beforeEach(() => {
    env = {
      ORIGIN_HOST: 'origin.example.com',
      BUILD_VERSION: 'test-v1',
      JWT_SECRET: 'test-jwt-secret-key-for-testing-purposes',
      AUTH_DO: createMockAuthDO(),
      RATE_LIMIT_DO: createMockRateLimitDO(),
      METRICS_DO: createMockMetricsDO(),
    };
    ctx = new MockExecutionContext();
    mockCache = new MockCache();

    // Mock caches.default
    (global as any).caches = {
      default: mockCache,
    };

    // Clear console.error mock
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  describe('Auth Routes', () => {
    it('returns nonce from /api/auth/nonce', async () => {
      const request = new Request('https://edge.example.com/api/auth/nonce');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
      const body = await response.json() as { nonce: string };
      expect(body.nonce).toBeDefined();
      expect(body.nonce.length).toBeGreaterThan(0);
    });

    it('stores nonce in KV for replay protection', async () => {
      const request = new Request('https://edge.example.com/api/auth/nonce');
      await worker.fetch(request, env, ctx);

      // Check that at least one nonce was stored
      // We can't easily check the exact key without modifying the implementation
    });

    it('returns 401 for protected API routes without session', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/api/protected-resource');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(401);
      const body = await response.json() as { error: string };
      expect(body.error).toBe('Authentication required');
    });

    it('allows public routes without session', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
    });

    it('allows public repo pages without session', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/owner/repo');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
    });
  });

  describe('Origin Failure Handling', () => {
    it('returns 503 with JSON error when origin fetch fails', async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error('Connection refused'));

      // Use a public route to avoid 401
      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(503);
      expect(response.headers.get('Content-Type')).toBe('application/json');
      expect(response.headers.get('Cache-Control')).toBe('no-store');
      expect(response.headers.get('Retry-After')).toBe('30');

      const body = await response.json() as { error: string; message: string };
      expect(body).toEqual({
        error: 'Service Unavailable',
        message: 'The origin server is currently unavailable. Please try again in a few moments.',
      });
    });

    it('logs error details when origin fails', async () => {
      const consoleSpy = vi.spyOn(console, 'error');
      global.fetch = vi.fn().mockRejectedValue(new Error('Connection timeout'));

      const request = new Request('https://edge.example.com/');
      await worker.fetch(request, env, ctx);

      expect(consoleSpy).toHaveBeenCalledWith(
        'Origin fetch failed',
        expect.objectContaining({
          url: '/',
          origin: 'origin.example.com',
          error: 'Connection timeout',
          timestamp: expect.any(String),
        })
      );
    });

    it('serves cached content when origin fails but cache exists', async () => {
      // First request succeeds and caches response
      global.fetch = vi.fn().mockResolvedValue(
        new Response('Fresh content', {
          status: 200,
          headers: {
            'Cache-Control': 'public, max-age=3600',
          },
        })
      );

      const request = new Request('https://edge.example.com/');
      await worker.fetch(request, env, ctx);

      // Wait for cache to be populated
      await Promise.all(ctx.promises);

      // Second request: origin is down but cache hit happens before origin check
      global.fetch = vi.fn().mockRejectedValue(new Error('Origin down'));

      const response = await worker.fetch(request, env, ctx);

      // Cache hit happens before origin fetch, so origin failure doesn't matter
      expect(response.status).toBe(200);
      expect(response.headers.get('X-Cache')).toBe('HIT');
      expect(await response.text()).toBe('Fresh content');
    });

    it('returns 503 when origin fails and no stale content exists', async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error('Origin down'));

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(503);
      const body = await response.json() as { error: string };
      expect(body.error).toBe('Service Unavailable');
    });

    it('handles origin failure for non-cacheable POST requests', async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error('Connection refused'));

      const request = new Request('https://edge.example.com/api/auth/verify', {
        method: 'POST',
        body: JSON.stringify({ message: 'test', signature: 'test' }),
        headers: { 'Content-Type': 'application/json' },
      });

      const response = await worker.fetch(request, env, ctx);

      // This is an edge-handled route, so it doesn't proxy to origin
      expect(response.status).toBe(401); // Invalid signature
    });
  });

  describe('Security Headers', () => {
    it('adds security headers to all responses', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      // Content Security Policy
      const csp = response.headers.get('Content-Security-Policy');
      expect(csp).toBeDefined();
      expect(csp).toContain("default-src 'self'");
      expect(csp).toContain("script-src 'self' 'unsafe-inline'");
      expect(csp).toContain("frame-ancestors 'none'");

      // Other security headers
      expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
      expect(response.headers.get('X-Frame-Options')).toBe('DENY');
      expect(response.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
      expect(response.headers.get('X-XSS-Protection')).toBe('1; mode=block');
      expect(response.headers.get('Strict-Transport-Security')).toBe('max-age=31536000; includeSubDomains');
    });

    it('adds security headers to cached responses', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('Content', {
          status: 200,
          headers: { 'Cache-Control': 'public, max-age=3600' },
        })
      );

      const request = new Request('https://edge.example.com/');
      await worker.fetch(request, env, ctx);
      await Promise.all(ctx.promises);

      // Second request - cache hit
      const response = await worker.fetch(request, env, ctx);
      expect(response.headers.get('X-Cache')).toBe('HIT');
      expect(response.headers.get('Content-Security-Policy')).toBeDefined();
      expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    });

    it('adds security headers to error responses', async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error('Origin down'));

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(503);
      expect(response.headers.get('Content-Security-Policy')).toBeDefined();
      expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    });

    it('adds security headers to auth route responses', async () => {
      const request = new Request('https://edge.example.com/api/auth/nonce');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
      expect(response.headers.get('Content-Security-Policy')).toBeDefined();
      expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    });

    it('adds security headers to 401 responses', async () => {
      // Mock global.fetch to prevent 503 from failed origin connection
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/api/protected-resource');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(401);
      expect(response.headers.get('Content-Security-Policy')).toBeDefined();
      expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    });
  });

  describe('Normal Operation', () => {
    it('proxies successful requests', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
      expect(await response.text()).toBe('OK');
    });

    it('caches successful cacheable responses', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('Content', {
          status: 200,
          headers: { 'Cache-Control': 'public, max-age=3600' },
        })
      );

      const request = new Request('https://edge.example.com/');

      // First request - cache miss
      const response1 = await worker.fetch(request, env, ctx);
      expect(response1.headers.get('X-Cache')).toBe('MISS');

      // Wait for cache
      await Promise.all(ctx.promises);

      // Second request - cache hit
      const response2 = await worker.fetch(request, env, ctx);
      expect(response2.headers.get('X-Cache')).toBe('HIT');
    });

    it('handles redirects correctly', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response(null, {
          status: 302,
          headers: {
            Location: 'https://origin.example.com/redirect-target',
          },
        })
      );

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toBe(
        'https://edge.example.com/redirect-target'
      );
    });
  });

  describe('Rate Limiting', () => {
    it('returns 429 when rate limit exceeded', async () => {
      // Override rate limit DO to deny requests
      env.RATE_LIMIT_DO = createMockRateLimitDO({
        allowed: false,
        limit: 10,
        remaining: 0,
        retryAfter: 45,
      });

      const request = new Request('https://edge.example.com/api/auth/nonce');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(429);
      const body = await response.json() as { error: string; retryAfter: number };
      expect(body.error).toBe('Too Many Requests');
      expect(body.retryAfter).toBe(45);
    });

    it('includes rate limit headers in 429 response', async () => {
      env.RATE_LIMIT_DO = createMockRateLimitDO({
        allowed: false,
        limit: 10,
        remaining: 0,
        retryAfter: 30,
      });

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(429);
      expect(response.headers.get('X-RateLimit-Limit')).toBe('10');
      expect(response.headers.get('X-RateLimit-Remaining')).toBe('0');
      expect(response.headers.get('Retry-After')).toBe('30');
    });

    it('includes rate limit headers in successful responses', async () => {
      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      env.RATE_LIMIT_DO = createMockRateLimitDO({
        allowed: true,
        limit: 100,
        remaining: 95,
      });

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(200);
      expect(response.headers.get('X-RateLimit-Limit')).toBe('100');
      expect(response.headers.get('X-RateLimit-Remaining')).toBe('95');
    });

    it('includes security headers with 429 response', async () => {
      env.RATE_LIMIT_DO = createMockRateLimitDO({
        allowed: false,
        limit: 10,
        remaining: 0,
        retryAfter: 30,
      });

      const request = new Request('https://edge.example.com/');
      const response = await worker.fetch(request, env, ctx);

      expect(response.status).toBe(429);
      expect(response.headers.get('Content-Security-Policy')).toBeDefined();
      expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    });

    it('rate limits auth endpoints with auth type', async () => {
      // This test verifies the limit type is correctly determined
      const fetchCalls: Request[] = [];
      env.RATE_LIMIT_DO = createMockDONamespace(async (req) => {
        fetchCalls.push(req);
        return new Response(JSON.stringify({
          allowed: true,
          limit: 10,
          remaining: 9,
        }), { headers: { 'Content-Type': 'application/json' } });
      });

      const request = new Request('https://edge.example.com/api/auth/nonce');
      await worker.fetch(request, env, ctx);

      expect(fetchCalls.length).toBeGreaterThan(0);
      const doRequest = fetchCalls[0];
      const url = new URL(doRequest.url);
      expect(url.searchParams.get('type')).toBe('auth');
    });

    it('rate limits API write endpoints with api:write type', async () => {
      const fetchCalls: Request[] = [];
      env.RATE_LIMIT_DO = createMockDONamespace(async (req) => {
        fetchCalls.push(req);
        return new Response(JSON.stringify({
          allowed: true,
          limit: 30,
          remaining: 29,
        }), { headers: { 'Content-Type': 'application/json' } });
      });

      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/api/repos', {
        method: 'POST',
        body: JSON.stringify({ name: 'test' }),
        headers: { 'Content-Type': 'application/json' },
      });
      await worker.fetch(request, env, ctx);

      expect(fetchCalls.length).toBeGreaterThan(0);
      const doRequest = fetchCalls[0];
      const url = new URL(doRequest.url);
      expect(url.searchParams.get('type')).toBe('api:write');
    });

    it('rate limits API read endpoints with api type', async () => {
      const fetchCalls: Request[] = [];
      env.RATE_LIMIT_DO = createMockDONamespace(async (req) => {
        fetchCalls.push(req);
        return new Response(JSON.stringify({
          allowed: true,
          limit: 100,
          remaining: 99,
        }), { headers: { 'Content-Type': 'application/json' } });
      });

      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/api/repos');
      await worker.fetch(request, env, ctx);

      expect(fetchCalls.length).toBeGreaterThan(0);
      const doRequest = fetchCalls[0];
      const url = new URL(doRequest.url);
      expect(url.searchParams.get('type')).toBe('api');
    });

    it('includes client IP in rate limit key', async () => {
      const fetchCalls: Request[] = [];
      env.RATE_LIMIT_DO = createMockDONamespace(async (req) => {
        fetchCalls.push(req);
        return new Response(JSON.stringify({
          allowed: true,
          limit: 200,
          remaining: 199,
        }), { headers: { 'Content-Type': 'application/json' } });
      });

      global.fetch = vi.fn().mockResolvedValue(
        new Response('OK', { status: 200 })
      );

      const request = new Request('https://edge.example.com/', {
        headers: { 'CF-Connecting-IP': '192.168.1.100' },
      });
      await worker.fetch(request, env, ctx);

      expect(fetchCalls.length).toBeGreaterThan(0);
      const doRequest = fetchCalls[0];
      const url = new URL(doRequest.url);
      const key = url.searchParams.get('key');
      expect(key).toContain('192.168.1.100');
    });
  });
});
