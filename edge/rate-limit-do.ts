/**
 * RateLimitDO - Sliding window rate limiter using Durable Object
 *
 * Why DO over KV:
 * - Atomic increment operations
 * - Strong consistency (critical for rate limiting)
 * - Per-key isolation
 */

interface RateLimitConfig {
  windowMs: number;     // Time window in milliseconds
  maxRequests: number;  // Max requests per window
}

interface RateLimitEntry {
  count: number;
  windowStart: number;
}

export class RateLimitDO implements DurableObject {
  private state: DurableObjectState;

  // Default limits by endpoint type
  private static readonly LIMITS: Record<string, RateLimitConfig> = {
    'auth': { windowMs: 60_000, maxRequests: 10 },      // 10 auth attempts/min
    'api': { windowMs: 60_000, maxRequests: 100 },      // 100 API calls/min
    'api:write': { windowMs: 60_000, maxRequests: 30 }, // 30 writes/min
    'default': { windowMs: 60_000, maxRequests: 200 },  // 200 requests/min
  };

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const key = url.searchParams.get('key');
    const limitType = url.searchParams.get('type') || 'default';

    if (!key) {
      return new Response('Missing key', { status: 400 });
    }

    const config = RateLimitDO.LIMITS[limitType] || RateLimitDO.LIMITS['default'];
    const now = Date.now();

    // Get current entry
    let entry = await this.state.storage.get<RateLimitEntry>(key);

    // Check if we're in a new window
    if (!entry || now - entry.windowStart > config.windowMs) {
      entry = { count: 0, windowStart: now };
    }

    // Check limit
    if (entry.count >= config.maxRequests) {
      const retryAfter = Math.ceil((entry.windowStart + config.windowMs - now) / 1000);
      return new Response(JSON.stringify({
        allowed: false,
        retryAfter,
        limit: config.maxRequests,
        remaining: 0,
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Increment and save
    entry.count++;
    await this.state.storage.put(key, entry);

    return new Response(JSON.stringify({
      allowed: true,
      limit: config.maxRequests,
      remaining: config.maxRequests - entry.count,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
