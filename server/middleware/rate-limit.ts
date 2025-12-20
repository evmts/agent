import { Context, Next } from 'hono';

interface RateLimitStore {
  [key: string]: {
    count: number;
    resetTime: number;
  };
}

// In-memory store - for production, use Redis or database
const store: RateLimitStore = {};

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
    const windowStart = now - windowMs;

    // Clean up old entries
    for (const [storeKey, data] of Object.entries(store)) {
      if (data.resetTime <= now) {
        delete store[storeKey];
      }
    }

    // Get or create entry for this key
    let entry = store[key];
    if (!entry || entry.resetTime <= now) {
      entry = {
        count: 0,
        resetTime: now + windowMs,
      };
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
 * Get client IP address
 */
function getClientIP(c: Context): string {
  // Check various headers for client IP
  const headers = [
    'x-forwarded-for',
    'x-real-ip',
    'x-client-ip',
    'cf-connecting-ip',
  ];

  for (const header of headers) {
    const value = c.req.header(header);
    if (value) {
      // Take first IP if comma-separated
      return value.split(',')[0].trim();
    }
  }

  // Fallback to connection IP (may not be available in all environments)
  return 'unknown';
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