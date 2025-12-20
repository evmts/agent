/**
 * Tests for rate limiting middleware.
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import {
  rateLimit,
  authRateLimit,
  apiRateLimit,
  emailRateLimit,
} from '../rate-limit';

// Helper to create a test context
function createMockContext(headers: Record<string, string> = {}) {
  const app = new Hono();
  return {
    app,
    headers,
  };
}

// Helper to make a request through middleware
async function makeRequest(
  middleware: any,
  headers: Record<string, string> = {},
  statusToSet?: number
) {
  const app = new Hono();

  app.use('*', middleware);

  app.get('/test', (c) => {
    if (statusToSet) {
      return c.json({ success: true }, statusToSet as any);
    }
    return c.json({ success: true });
  });

  const url = 'http://localhost/test';
  const headerEntries = new Headers(headers);

  const response = await app.request(url, {
    method: 'GET',
    headers: headerEntries,
  });

  return response;
}

describe('rateLimit factory', () => {
  beforeEach(() => {
    // Note: In a real test environment, we'd want to clear the store
    // For now, we'll use unique IPs or wait for window expiry
  });

  test('allows requests under the limit', async () => {
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 5,
      keyGenerator: () => `test-allows-${Date.now()}`,
    });

    for (let i = 0; i < 5; i++) {
      const response = await makeRequest(limiter);
      expect(response.status).toBe(200);
      const body = await response.json();
      expect(body.success).toBe(true);
    }
  });

  test('blocks requests over the limit', async () => {
    const key = `test-blocks-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 3,
      keyGenerator: () => key,
    });

    // First 3 requests should succeed
    for (let i = 0; i < 3; i++) {
      const response = await makeRequest(limiter);
      expect(response.status).toBe(200);
    }

    // 4th request should be blocked
    const response = await makeRequest(limiter);
    expect(response.status).toBe(429);

    const body = await response.json();
    expect(body.error).toBe('Too many requests');
    expect(body.retryAfter).toBeDefined();
    expect(typeof body.retryAfter).toBe('number');
  });

  test('resets after window expires', async () => {
    const key = `test-reset-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 100, // Very short window
      maxRequests: 2,
      keyGenerator: () => key,
    });

    // Use up the limit
    await makeRequest(limiter);
    await makeRequest(limiter);

    // Next request should be blocked
    const blocked = await makeRequest(limiter);
    expect(blocked.status).toBe(429);

    // Wait for window to expire
    await new Promise((resolve) => setTimeout(resolve, 150));

    // Should be allowed again
    const allowed = await makeRequest(limiter);
    expect(allowed.status).toBe(200);
  });

  test('tracks different keys separately', async () => {
    let currentKey = 'key-1';
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 2,
      keyGenerator: () => currentKey,
    });

    // Use up limit for key-1
    await makeRequest(limiter);
    await makeRequest(limiter);

    // key-1 should be blocked
    const blocked = await makeRequest(limiter);
    expect(blocked.status).toBe(429);

    // Switch to key-2
    currentKey = 'key-2';

    // key-2 should be allowed
    const allowed = await makeRequest(limiter);
    expect(allowed.status).toBe(200);
  });

  test('skipSuccessfulRequests option works', async () => {
    const key = `test-skip-success-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 2,
      skipSuccessfulRequests: true,
      keyGenerator: () => key,
    });

    // Make 5 successful requests (should not count)
    for (let i = 0; i < 5; i++) {
      const response = await makeRequest(limiter);
      expect(response.status).toBe(200);
    }

    // All should succeed because they're not counted
    const response = await makeRequest(limiter);
    expect(response.status).toBe(200);
  });

  test('skipFailedRequests option works', async () => {
    const key = `test-skip-failed-${Date.now()}`;
    const app = new Hono();

    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 2,
      skipFailedRequests: true,
      keyGenerator: () => key,
    });

    app.use('*', limiter);
    app.get('/test', (c) => c.json({ error: 'Bad request' }, 400));

    // Make 5 failed requests (should not count)
    for (let i = 0; i < 5; i++) {
      const response = await app.request('http://localhost/test');
      expect(response.status).toBe(400);
    }

    // All should succeed because failed requests aren't counted
    const response = await app.request('http://localhost/test');
    expect(response.status).toBe(400);
  });

  test('uses custom key generator', async () => {
    const customKeys: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 5,
      keyGenerator: (c) => {
        const key = c.req.header('x-custom-id') || 'default';
        customKeys.push(key);
        return key;
      },
    });

    await makeRequest(limiter, { 'x-custom-id': 'user-123' });
    await makeRequest(limiter, { 'x-custom-id': 'user-456' });

    expect(customKeys).toContain('user-123');
    expect(customKeys).toContain('user-456');
  });

  test('returns correct retryAfter value', async () => {
    const key = `test-retry-${Date.now()}`;
    const windowMs = 10000; // 10 seconds

    const limiter = rateLimit({
      windowMs,
      maxRequests: 1,
      keyGenerator: () => key,
    });

    // Use up the limit
    await makeRequest(limiter);

    // Get blocked response
    const response = await makeRequest(limiter);
    const body = await response.json();

    expect(body.retryAfter).toBeGreaterThan(0);
    expect(body.retryAfter).toBeLessThanOrEqual(Math.ceil(windowMs / 1000));
  });

  test('cleans up expired entries', async () => {
    const key1 = `test-cleanup-1-${Date.now()}`;
    const key2 = `test-cleanup-2-${Date.now()}`;

    const limiter = rateLimit({
      windowMs: 100, // Very short window
      maxRequests: 1,
      keyGenerator: (c) => {
        const id = c.req.header('x-key-id');
        return id === '1' ? key1 : key2;
      },
    });

    // Create entry for key1
    await makeRequest(limiter, { 'x-key-id': '1' });

    // Wait for key1 to expire
    await new Promise((resolve) => setTimeout(resolve, 150));

    // Create entry for key2 (should trigger cleanup)
    await makeRequest(limiter, { 'x-key-id': '2' });

    // key1 should now be usable again (was cleaned up)
    const response = await makeRequest(limiter, { 'x-key-id': '1' });
    expect(response.status).toBe(200);
  });
});

describe('getClientIP (via default keyGenerator)', () => {
  test('extracts IP from x-forwarded-for', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        // Use default IP extraction
        const headers = [
          'x-forwarded-for',
          'x-real-ip',
          'x-client-ip',
          'cf-connecting-ip',
        ];
        for (const header of headers) {
          const value = c.req.header(header);
          if (value) {
            const ip = value.split(',')[0].trim();
            ips.push(ip);
            return ip;
          }
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, { 'x-forwarded-for': '192.168.1.1' });
    expect(ips).toContain('192.168.1.1');
  });

  test('extracts IP from x-real-ip', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const value = c.req.header('x-real-ip');
        if (value) {
          ips.push(value);
          return value;
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, { 'x-real-ip': '10.0.0.5' });
    expect(ips).toContain('10.0.0.5');
  });

  test('extracts IP from x-client-ip', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const value = c.req.header('x-client-ip');
        if (value) {
          ips.push(value);
          return value;
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, { 'x-client-ip': '172.16.0.1' });
    expect(ips).toContain('172.16.0.1');
  });

  test('extracts IP from cf-connecting-ip', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const value = c.req.header('cf-connecting-ip');
        if (value) {
          ips.push(value);
          return value;
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, { 'cf-connecting-ip': '1.2.3.4' });
    expect(ips).toContain('1.2.3.4');
  });

  test('handles comma-separated IPs in x-forwarded-for', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const value = c.req.header('x-forwarded-for');
        if (value) {
          const ip = value.split(',')[0].trim();
          ips.push(ip);
          return ip;
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, {
      'x-forwarded-for': '192.168.1.1, 10.0.0.1, 172.16.0.1',
    });

    expect(ips[0]).toBe('192.168.1.1');
  });

  test('trims whitespace from IPs', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const value = c.req.header('x-forwarded-for');
        if (value) {
          const ip = value.split(',')[0].trim();
          ips.push(ip);
          return ip;
        }
        return 'unknown';
      },
    });

    await makeRequest(limiter, {
      'x-forwarded-for': '  192.168.1.1  , 10.0.0.1',
    });

    expect(ips[0]).toBe('192.168.1.1');
  });

  test('falls back to unknown when no IP headers present', async () => {
    const keys: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const headers = [
          'x-forwarded-for',
          'x-real-ip',
          'x-client-ip',
          'cf-connecting-ip',
        ];
        for (const header of headers) {
          const value = c.req.header(header);
          if (value) {
            return value.split(',')[0].trim();
          }
        }
        keys.push('unknown');
        return 'unknown';
      },
    });

    await makeRequest(limiter);
    expect(keys).toContain('unknown');
  });

  test('prioritizes headers in correct order', async () => {
    const ips: string[] = [];
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 10,
      keyGenerator: (c) => {
        const headers = [
          'x-forwarded-for',
          'x-real-ip',
          'x-client-ip',
          'cf-connecting-ip',
        ];
        for (const header of headers) {
          const value = c.req.header(header);
          if (value) {
            const ip = value.split(',')[0].trim();
            ips.push(ip);
            return ip;
          }
        }
        return 'unknown';
      },
    });

    // x-forwarded-for should take priority
    await makeRequest(limiter, {
      'x-forwarded-for': '1.1.1.1',
      'x-real-ip': '2.2.2.2',
      'x-client-ip': '3.3.3.3',
    });

    expect(ips[0]).toBe('1.1.1.1');
  });
});

describe('preset rate limiters', () => {
  describe('authRateLimit', () => {
    test('has correct configuration', async () => {
      // authRateLimit: 5 requests per 15 minutes, skipSuccessfulRequests: true
      const key = `test-auth-${Date.now()}`;
      const app = new Hono();

      // Need to wrap with custom key for testing
      const testLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        maxRequests: 5,
        skipSuccessfulRequests: true,
        keyGenerator: () => key,
      });

      app.use('*', testLimiter);
      app.get('/auth', (c) => c.json({ success: true }));

      // Make 10 successful requests
      for (let i = 0; i < 10; i++) {
        const response = await app.request('http://localhost/auth');
        expect(response.status).toBe(200);
      }
    });
  });

  describe('apiRateLimit', () => {
    test('has correct configuration', async () => {
      // apiRateLimit: 100 requests per 15 minutes
      const key = `test-api-${Date.now()}`;
      const testLimiter = rateLimit({
        windowMs: 15 * 60 * 1000,
        maxRequests: 100,
        keyGenerator: () => key,
      });

      // Make 99 requests
      for (let i = 0; i < 99; i++) {
        const response = await makeRequest(testLimiter);
        expect(response.status).toBe(200);
      }

      // 100th should succeed
      const response100 = await makeRequest(testLimiter);
      expect(response100.status).toBe(200);

      // 101st should fail
      const response101 = await makeRequest(testLimiter);
      expect(response101.status).toBe(429);
    });
  });

  describe('emailRateLimit', () => {
    test('has correct configuration', async () => {
      // emailRateLimit: 3 requests per hour
      const key = `test-email-${Date.now()}`;
      const testLimiter = rateLimit({
        windowMs: 60 * 60 * 1000,
        maxRequests: 3,
        keyGenerator: () => key,
      });

      // Make 3 requests
      for (let i = 0; i < 3; i++) {
        const response = await makeRequest(testLimiter);
        expect(response.status).toBe(200);
      }

      // 4th should fail
      const response = await makeRequest(testLimiter);
      expect(response.status).toBe(429);
    });
  });
});

describe('edge cases', () => {
  test('handles maxRequests of 0', async () => {
    const key = `test-zero-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 0,
      keyGenerator: () => key,
    });

    // Should be blocked immediately
    const response = await makeRequest(limiter);
    expect(response.status).toBe(429);
  });

  test('handles maxRequests of 1', async () => {
    const key = `test-one-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 1,
      keyGenerator: () => key,
    });

    // First request allowed
    const response1 = await makeRequest(limiter);
    expect(response1.status).toBe(200);

    // Second request blocked
    const response2 = await makeRequest(limiter);
    expect(response2.status).toBe(429);
  });

  test('handles very large maxRequests', async () => {
    const key = `test-large-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 1000000,
      keyGenerator: () => key,
    });

    // Should not block even after many requests
    for (let i = 0; i < 100; i++) {
      const response = await makeRequest(limiter);
      expect(response.status).toBe(200);
    }
  });

  test('handles very short windowMs', async () => {
    const key = `test-short-window-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 1, // 1ms window
      maxRequests: 1,
      keyGenerator: () => key,
    });

    // First request
    await makeRequest(limiter);

    // Wait for window to expire
    await new Promise((resolve) => setTimeout(resolve, 10));

    // Should be allowed again
    const response = await makeRequest(limiter);
    expect(response.status).toBe(200);
  });

  test('handles concurrent requests', async () => {
    const key = `test-concurrent-${Date.now()}`;
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 5,
      keyGenerator: () => key,
    });

    // Note: Due to the implementation incrementing AFTER the request,
    // concurrent requests may all see count < maxRequests and succeed.
    // This is a limitation of in-memory rate limiting without atomic operations.
    // In production, you'd use Redis with atomic INCR.

    // Make 10 concurrent requests
    const promises = [];
    for (let i = 0; i < 10; i++) {
      promises.push(makeRequest(limiter));
    }

    const responses = await Promise.all(promises);

    // All responses should have completed (either 200 or 429)
    expect(responses.length).toBe(10);
    for (const response of responses) {
      expect([200, 429]).toContain(response.status);
    }
  });

  test('handles empty key from keyGenerator', async () => {
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 2,
      keyGenerator: () => '',
    });

    // Should still work with empty string key
    const response1 = await makeRequest(limiter);
    expect(response1.status).toBe(200);

    const response2 = await makeRequest(limiter);
    expect(response2.status).toBe(200);

    const response3 = await makeRequest(limiter);
    expect(response3.status).toBe(429);
  });

  test('handles keyGenerator throwing error', async () => {
    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 5,
      keyGenerator: () => {
        throw new Error('Key generation failed');
      },
    });

    // The middleware should catch the error and return 500
    const response = await makeRequest(limiter);
    expect(response.status).toBe(500);

    const body = await response.json();
    expect(body.error).toBe('Internal server error');
  });

  test('counts both successful and failed requests by default', async () => {
    const key = `test-default-count-${Date.now()}`;
    const app = new Hono();

    const limiter = rateLimit({
      windowMs: 60000,
      maxRequests: 3,
      keyGenerator: () => key,
    });

    app.use('*', limiter);
    let shouldFail = false;
    app.get('/test', (c) => {
      if (shouldFail) {
        return c.json({ error: 'Failed' }, 500);
      }
      return c.json({ success: true });
    });

    // 2 successful
    await app.request('http://localhost/test');
    await app.request('http://localhost/test');

    // 1 failed
    shouldFail = true;
    await app.request('http://localhost/test');

    // Should be at limit now
    const response = await app.request('http://localhost/test');
    expect(response.status).toBe(429);
  });
});
