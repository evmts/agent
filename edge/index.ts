import type { Env } from './types';
import { handleAuthRoute, getAuthenticatedUser } from './routes/auth';
import { isEdgeHandledRoute, isPublicRoute } from './lib/public-routes';
import { checkRateLimit, getRateLimitHeaders, type RateLimitResult } from './lib/rate-limit';
import { getLimitType } from './lib/limit-type';
import { Logger } from './lib/logger';
import { Analytics, createAnalyticsEvent, type CacheStatus, type EventType } from './lib/analytics';
import { handleMetrics } from './routes/metrics';
import type { IncrementPayload } from './metrics-do';

// Export Durable Objects for Cloudflare to discover
export { AuthDO } from './auth-do';
export { RateLimitDO } from './rate-limit-do';
export { MetricsDO } from './metrics-do';

/** Header name for passing authenticated user address to origin */
const USER_ADDRESS_HEADER = 'X-Plue-User-Address';

/**
 * Add security headers to response
 * These headers protect against XSS, clickjacking, and other attacks
 */
function addSecurityHeaders(headers: Headers): void {
  // Content-Security-Policy
  const csp = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'", // unsafe-inline needed for Astro hydration
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "connect-src 'self' https://api.anthropic.com",
    "font-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests"
  ].join('; ');

  headers.set('Content-Security-Policy', csp);
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('X-Frame-Options', 'DENY');
  headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  headers.set('X-XSS-Protection', '1; mode=block');
  headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
}

/**
 * Add rate limit headers to response
 */
function addRateLimitHeaders(headers: Headers, result: RateLimitResult): void {
  for (const [key, value] of Object.entries(getRateLimitHeaders(result))) {
    headers.set(key, value);
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const logger = new Logger(request);
    const analytics = new Analytics(env);
    const url = new URL(request.url);

    try {
      // Handle metrics endpoint (no auth/rate limiting needed)
      if (url.pathname === '/metrics') {
        const response = await handleMetrics(request, env);
        response.headers.set('X-Request-ID', logger.getRequestId());
        return response;
      }

      logger.info('Request started');

      // Get client IP (Cloudflare provides this)
      const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';

      // Check rate limit early to protect origin
      const limitType = getLimitType(request);
      const rateLimitResult = await checkRateLimit(env, clientIP, url.pathname, limitType);

      if (!rateLimitResult.allowed) {
        logger.warn('Rate limited', { limitType });

        const headers = new Headers({
          'Content-Type': 'application/json',
          'X-Request-ID': logger.getRequestId(),
          ...getRateLimitHeaders(rateLimitResult),
        });
        addSecurityHeaders(headers);

        const response = new Response(JSON.stringify({
          error: 'Too Many Requests',
          retryAfter: rateLimitResult.retryAfter,
        }), {
          status: 429,
          headers,
        });

        // Track rate limit event
        trackMetrics(env, ctx, logger, response, 'rate_limited');
        ctx.waitUntil(analytics.flush(ctx));

        return response;
      }

      // Handle auth routes at the edge (don't proxy to origin)
      if (isEdgeHandledRoute(url.pathname)) {
        const response = await handleAuthRoute(request, env, url.pathname);
        addRateLimitHeaders(response.headers, rateLimitResult);
        addSecurityHeaders(response.headers);
        response.headers.set('X-Request-ID', logger.getRequestId());

        // Track auth events
        const isAuthSuccess = response.status === 200 && url.pathname === '/api/auth/verify';
        const isAuthFailure = response.status >= 400 && url.pathname === '/api/auth/verify';
        const eventType: EventType = isAuthSuccess ? 'auth_success' : isAuthFailure ? 'auth_failure' : 'request';

        trackMetrics(env, ctx, logger, response, eventType);
        logger.info('Auth route handled', { status: response.status, eventType });
        ctx.waitUntil(analytics.flush(ctx));

        return response;
      }

      // Get authenticated user from session
      const user = await getAuthenticatedUser(request, env);
      if (user) {
        logger.setUserAddress(user.address);
      }

      // Check authentication for protected routes
      if (!isPublicRoute(url.pathname) && !user) {
        // Return 401 for API routes, redirect for pages
        if (url.pathname.startsWith('/api/')) {
          const headers = new Headers({
            'Content-Type': 'application/json',
            'X-Request-ID': logger.getRequestId(),
          });
          addRateLimitHeaders(headers, rateLimitResult);
          addSecurityHeaders(headers);

          const response = new Response(JSON.stringify({ error: 'Authentication required' }), {
            status: 401,
            headers,
          });

          trackMetrics(env, ctx, logger, response, 'auth_failure');
          logger.info('Auth required', { status: 401 });
          ctx.waitUntil(analytics.flush(ctx));

          return response;
        }
        // For page routes, let origin handle the redirect
      }

      // Only cache GET/HEAD requests
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        const response = await proxyToOrigin(request, env, user, undefined, undefined, logger.getRequestId());
        const finalResponse = new Response(response.body, response);
        addRateLimitHeaders(finalResponse.headers, rateLimitResult);
        addSecurityHeaders(finalResponse.headers);
        finalResponse.headers.set('X-Request-ID', logger.getRequestId());

        trackMetrics(env, ctx, logger, finalResponse, 'request');
        logger.info('Request completed', { status: finalResponse.status, method: request.method });
        ctx.waitUntil(analytics.flush(ctx));

        return finalResponse;
      }

      // Skip cache for API routes (they handle their own caching)
      if (url.pathname.startsWith('/api/')) {
        const response = await proxyToOrigin(request, env, user, undefined, undefined, logger.getRequestId());
        const finalResponse = new Response(response.body, response);
        addRateLimitHeaders(finalResponse.headers, rateLimitResult);
        addSecurityHeaders(finalResponse.headers);
        finalResponse.headers.set('X-Request-ID', logger.getRequestId());

        trackMetrics(env, ctx, logger, finalResponse, 'request');
        logger.info('API request completed', { status: finalResponse.status });
        ctx.waitUntil(analytics.flush(ctx));

        return finalResponse;
      }

      const cache = caches.default;
      const cacheKey = createCacheKey(request, env);

      // Skip cache for authenticated users - they get personalized content
      if (user) {
        const response = await proxyToOrigin(request, env, user, cache, cacheKey);
        const finalResponse = new Response(response.body, response);
        if (!finalResponse.headers.has('X-Cache')) {
          finalResponse.headers.set('X-Cache', 'BYPASS');
        }
        addRateLimitHeaders(finalResponse.headers, rateLimitResult);
        addSecurityHeaders(finalResponse.headers);
        finalResponse.headers.set('X-Request-ID', logger.getRequestId());

        trackMetrics(env, ctx, logger, finalResponse, 'cache_bypass');
        logger.info('Cache bypassed (authenticated)', { status: finalResponse.status });
        ctx.waitUntil(analytics.flush(ctx));

        return finalResponse;
      }

      // Check cache first
      const cached = await cache.match(cacheKey);
      if (cached) {
        // Add header to indicate cache hit
        const response = new Response(cached.body, cached);
        response.headers.set('X-Cache', 'HIT');
        addRateLimitHeaders(response.headers, rateLimitResult);
        addSecurityHeaders(response.headers);
        response.headers.set('X-Request-ID', logger.getRequestId());

        trackMetrics(env, ctx, logger, response, 'cache_hit');
        logger.info('Cache hit', { status: response.status });
        ctx.waitUntil(analytics.flush(ctx));

        return response;
      }

      // Fetch from origin (with error handling and stale-while-revalidate fallback)
      const response = await proxyToOrigin(request, env, user, cache, cacheKey);

      // Cache if origin says it's cacheable
      if (shouldCache(response)) {
        // Clone before caching (body can only be read once)
        const responseToCache = response.clone();
        ctx.waitUntil(cache.put(cacheKey, responseToCache));
      }

      // Add header to indicate cache miss
      const finalResponse = new Response(response.body, response);
      finalResponse.headers.set('X-Cache', 'MISS');
      addRateLimitHeaders(finalResponse.headers, rateLimitResult);
      addSecurityHeaders(finalResponse.headers);
      finalResponse.headers.set('X-Request-ID', logger.getRequestId());

      trackMetrics(env, ctx, logger, finalResponse, 'cache_miss');
      logger.info('Cache miss', { status: finalResponse.status });
      ctx.waitUntil(analytics.flush(ctx));

      return finalResponse;
    } catch (error) {
      logger.error('Request failed', error as Error);

      const response = new Response(JSON.stringify({
        error: 'Internal Server Error',
        requestId: logger.getRequestId(),
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'X-Request-ID': logger.getRequestId(),
        },
      });
      addSecurityHeaders(response.headers);

      trackMetrics(env, ctx, logger, response, 'error');
      ctx.waitUntil(analytics.flush(ctx));

      return response;
    }
  },
};

/**
 * Track metrics via Durable Object
 */
function trackMetrics(
  env: Env,
  ctx: ExecutionContext,
  logger: Logger,
  response: Response,
  type: EventType
): void {
  // Fire-and-forget metrics tracking
  ctx.waitUntil((async () => {
    try {
      const metricsId = env.METRICS_DO.idFromName('global');
      const metricsDO = env.METRICS_DO.get(metricsId);

      const payload: IncrementPayload = {
        type: type as IncrementPayload['type'],
        status: response.status,
        duration_ms: logger.getDuration(),
      };

      await metricsDO.fetch(new Request('https://do/increment', {
        method: 'POST',
        body: JSON.stringify(payload),
        headers: { 'Content-Type': 'application/json' },
      }));
    } catch (error) {
      // Don't let metrics failures affect the response
      console.error('Failed to track metrics:', error);
    }
  })());
}

function createCacheKey(request: Request, env: Env): Request {
  const url = new URL(request.url);

  // Include build version in cache key for deploy invalidation
  // When BUILD_VERSION changes, all old cache keys become invalid
  url.searchParams.set('_v', env.BUILD_VERSION || 'dev');

  return new Request(url.toString(), {
    method: request.method,
    headers: request.headers,
  });
}

function shouldCache(response: Response): boolean {
  // Only cache successful responses
  if (response.status !== 200) {
    return false;
  }

  const cacheControl = response.headers.get('Cache-Control');
  if (!cacheControl) {
    return false;
  }

  // Cache if public and has max-age or s-maxage
  if (cacheControl.includes('public') &&
      (cacheControl.includes('max-age') || cacheControl.includes('s-maxage'))) {
    return true;
  }

  return false;
}

async function proxyToOrigin(
  request: Request,
  env: Env,
  user: { address: string } | null,
  cache?: Cache,
  cacheKey?: Request,
  requestId?: string
): Promise<Response> {
  const url = new URL(request.url);
  const originUrl = new URL(url.pathname + url.search, `https://${env.ORIGIN_HOST}`);

  // Clone headers and add user address if authenticated
  const headers = new Headers(request.headers);
  if (user) {
    headers.set(USER_ADDRESS_HEADER, user.address);
  }

  // Propagate request ID to origin
  if (requestId) {
    headers.set('X-Request-ID', requestId);
  }

  const proxyRequest = new Request(originUrl.toString(), {
    method: request.method,
    headers,
    body: request.body,
    redirect: 'manual',
  });

  try {
    const response = await fetch(proxyRequest);

    // Rewrite redirect URLs back to edge
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('Location');
      if (location?.includes(env.ORIGIN_HOST)) {
        const responseHeaders = new Headers(response.headers);
        responseHeaders.set('Location', location.replace(`https://${env.ORIGIN_HOST}`, url.origin));
        return new Response(response.body, { status: response.status, headers: responseHeaders });
      }
    }

    return response;
  } catch (error) {
    // Log the origin failure for debugging
    console.error('Origin fetch failed', {
      url: url.pathname,
      origin: env.ORIGIN_HOST,
      error: error instanceof Error ? error.message : String(error),
      timestamp: new Date().toISOString(),
    });

    // Try to serve stale content if available
    if (cache && cacheKey) {
      const stale = await cache.match(cacheKey);
      if (stale) {
        console.error('Serving stale content due to origin failure', {
          url: url.pathname,
          timestamp: new Date().toISOString(),
        });

        const response = new Response(stale.body, stale);
        response.headers.set('X-Cache', 'STALE');
        response.headers.set('X-Cache-Reason', 'origin-failure');
        addSecurityHeaders(response.headers);
        return response;
      }
    }

    // No stale content available - return friendly error response
    return createErrorResponse();
  }
}

function createErrorResponse(): Response {
  const body = JSON.stringify({
    error: 'Service Unavailable',
    message: 'The origin server is currently unavailable. Please try again in a few moments.',
  });

  const headers = new Headers({
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'Retry-After': '30',
  });
  addSecurityHeaders(headers);

  return new Response(body, {
    status: 503,
    headers,
  });
}
