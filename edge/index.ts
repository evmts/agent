import type { Env } from './types';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Only cache GET/HEAD requests
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return proxyToOrigin(request, env);
    }

    // Skip cache for API routes (they handle their own caching)
    if (url.pathname.startsWith('/api/')) {
      return proxyToOrigin(request, env);
    }

    // Skip cache for authenticated users - they get personalized content
    if (hasSessionCookie(request)) {
      const response = await proxyToOrigin(request, env);
      const finalResponse = new Response(response.body, response);
      finalResponse.headers.set('X-Cache', 'BYPASS');
      return finalResponse;
    }

    const cache = caches.default;

    // Create cache key with version for deploy invalidation
    const cacheKey = createCacheKey(request, env);

    // Check cache first
    const cached = await cache.match(cacheKey);
    if (cached) {
      // Add header to indicate cache hit
      const response = new Response(cached.body, cached);
      response.headers.set('X-Cache', 'HIT');
      return response;
    }

    // Fetch from origin
    const response = await proxyToOrigin(request, env);

    // Cache if origin says it's cacheable
    if (shouldCache(response)) {
      // Clone before caching (body can only be read once)
      const responseToCache = response.clone();
      ctx.waitUntil(cache.put(cacheKey, responseToCache));
    }

    // Add header to indicate cache miss
    const finalResponse = new Response(response.body, response);
    finalResponse.headers.set('X-Cache', 'MISS');
    return finalResponse;
  },
};

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

function hasSessionCookie(request: Request): boolean {
  const cookies = request.headers.get('Cookie') || '';
  return cookies.includes('session=');
}

async function proxyToOrigin(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const originUrl = new URL(url.pathname + url.search, `https://${env.ORIGIN_HOST}`);

  const proxyRequest = new Request(originUrl.toString(), {
    method: request.method,
    headers: request.headers,
    body: request.body,
    redirect: 'manual',
  });

  const response = await fetch(proxyRequest);

  // Rewrite redirect URLs back to edge
  if (response.status >= 300 && response.status < 400) {
    const location = response.headers.get('Location');
    if (location?.includes(env.ORIGIN_HOST)) {
      const headers = new Headers(response.headers);
      headers.set('Location', location.replace(`https://${env.ORIGIN_HOST}`, url.origin));
      return new Response(response.body, { status: response.status, headers });
    }
  }

  return response;
}
