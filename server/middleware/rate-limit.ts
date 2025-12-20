import { Context, Next } from 'hono';

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

interface RateLimitStore {
  [key: string]: RateLimitEntry;
}

// Configuration
const MAX_STORE_SIZE = 10000; // Maximum number of entries to prevent memory exhaustion
const TRUSTED_PROXIES = process.env.TRUSTED_PROXIES?.split(',').map(s => s.trim()) || [];

// In-memory store - for production with multiple servers, use Redis
// WARNING: This store is local to each server instance
const store: RateLimitStore = {};
let storeSize = 0;

interface RateLimitOptions {
  windowMs: number; // Time window in milliseconds
  maxRequests: number; // Max requests per window
  skipSuccessfulRequests?: boolean;
  skipFailedRequests?: boolean;
  keyGenerator?: (c: Context) => string;
}

/**
 * Rate limiting middleware factory
 */
export function rateLimit(options: RateLimitOptions) {
  const {
    windowMs,
    maxRequests,
    skipSuccessfulRequests = false,
    skipFailedRequests = false,
    keyGenerator = (c) => getClientIP(c),
  } = options;

  return async (c: Context, next: Next) => {
    let key: string;
    try {
      key = keyGenerator(c);
    } catch (error) {
      // If key generation fails, return 500 error
      return c.json({
        error: 'Internal server error',
      }, 500);
    }

    const now = Date.now();

    // Clean up old entries (do this periodically, not on every request)
    if (Math.random() < 0.01) { // 1% chance per request
      cleanupExpiredEntries(now);
    }

    // Get or create entry for this key
    let entry = store[key];
    if (!entry || entry.resetTime <= now) {
      // Check if we need to make room (enforce max store size)
      if (!entry && storeSize >= MAX_STORE_SIZE) {
        // Force cleanup and evict oldest entries if still over limit
        cleanupExpiredEntries(now);
        if (storeSize >= MAX_STORE_SIZE) {
          evictOldestEntries(Math.floor(MAX_STORE_SIZE * 0.1)); // Evict 10%
        }
      }

      entry = {
        count: 0,
        resetTime: now + windowMs,
      };
      if (!store[key]) {
        storeSize++;
      }
      store[key] = entry;
    }

    // Check if limit exceeded
    if (entry.count >= maxRequests) {
      return c.json({
        error: 'Too many requests',
        retryAfter: Math.ceil((entry.resetTime - now) / 1000),
      }, 429);
    }

    // Continue with request
    await next();

    // Increment counter after request (unless configured to skip)
    const shouldSkip = 
      (skipSuccessfulRequests && c.res.status < 400) ||
      (skipFailedRequests && c.res.status >= 400);

    if (!shouldSkip) {
      entry.count++;
    }
  };
}

/**
 * Clean up expired entries from the store
 */
function cleanupExpiredEntries(now: number): void {
  for (const [key, entry] of Object.entries(store)) {
    if (entry.resetTime <= now) {
      delete store[key];
      storeSize--;
    }
  }
}

/**
 * Evict oldest entries when store is full
 */
function evictOldestEntries(count: number): void {
  const entries = Object.entries(store)
    .sort((a, b) => a[1].resetTime - b[1].resetTime);

  for (let i = 0; i < Math.min(count, entries.length); i++) {
    delete store[entries[i][0]];
    storeSize--;
  }
}

/**
 * Get client IP address with security considerations
 */
function getClientIP(c: Context): string {
  // If we have trusted proxies configured, check them
  const cfIp = c.req.header('cf-connecting-ip');
  if (cfIp && TRUSTED_PROXIES.includes('cloudflare')) {
    return cfIp.trim();
  }

  const xRealIp = c.req.header('x-real-ip');
  if (xRealIp && TRUSTED_PROXIES.length > 0) {
    return xRealIp.trim();
  }

  const xForwardedFor = c.req.header('x-forwarded-for');
  if (xForwardedFor && TRUSTED_PROXIES.length > 0) {
    // Take the first IP (client IP in a properly configured proxy chain)
    return xForwardedFor.split(',')[0].trim();
  }

  // When no trusted proxy is configured, don't trust forwarded headers
  // This prevents header spoofing attacks
  // In production behind a proxy, configure TRUSTED_PROXIES env var

  // Generate a unique identifier from request characteristics
  // This is a fallback - not perfect but better than grouping all users
  const userAgent = c.req.header('user-agent') || '';
  const acceptLanguage = c.req.header('accept-language') || '';
  const fingerprint = `${userAgent.slice(0, 50)}:${acceptLanguage.slice(0, 20)}`;

  return `fallback:${fingerprint}`;
}

/**
 * Preset rate limiters
 */

// Strict rate limit for auth endpoints
export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  maxRequests: 5, // 5 attempts per 15 minutes
  skipSuccessfulRequests: true,
});

// General API rate limit
export const apiRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  maxRequests: 100, // 100 requests per 15 minutes
});

// Email rate limit
export const emailRateLimit = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  maxRequests: 3, // 3 emails per hour
});