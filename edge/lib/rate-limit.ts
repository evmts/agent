import type { Env } from '../types';

export interface RateLimitResult {
  allowed: boolean;
  limit: number;
  remaining: number;
  retryAfter?: number;
}

export type LimitType = 'auth' | 'api' | 'api:write' | 'default';

/**
 * Check rate limit for a request
 *
 * @param env - Worker environment with RATE_LIMIT_DO binding
 * @param clientIP - Client IP address (from CF-Connecting-IP)
 * @param endpoint - Endpoint being accessed (for per-endpoint limits)
 * @param limitType - Type of limit to apply
 */
export async function checkRateLimit(
  env: Env,
  clientIP: string,
  endpoint: string,
  limitType: LimitType = 'default'
): Promise<RateLimitResult> {
  // Use consistent hashing to distribute across DOs
  // Each IP gets its own "bucket" but we shard by IP prefix for scale
  const shard = clientIP.split('.').slice(0, 2).join('.');
  const doId = env.RATE_LIMIT_DO.idFromName(`shard:${shard}`);
  const rateLimitDO = env.RATE_LIMIT_DO.get(doId);

  const key = `${clientIP}:${endpoint}`;
  const response = await rateLimitDO.fetch(
    new Request(`https://do/check?key=${encodeURIComponent(key)}&type=${limitType}`)
  );

  return response.json();
}

/**
 * Get rate limit headers to include in response
 */
export function getRateLimitHeaders(result: RateLimitResult): Record<string, string> {
  const headers: Record<string, string> = {
    'X-RateLimit-Limit': result.limit.toString(),
    'X-RateLimit-Remaining': result.remaining.toString(),
  };

  if (result.retryAfter) {
    headers['Retry-After'] = result.retryAfter.toString();
  }

  return headers;
}
