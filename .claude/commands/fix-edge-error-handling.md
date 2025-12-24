# Add Error Handling to Edge Worker

## Priority: HIGH | Reliability

## Problem

Origin fetch failures are not handled in the edge worker:

`edge/index.ts:94-118`
```typescript
async function proxyToOrigin(request: Request, env: Env): Promise<Response> {
    const response = await fetch(proxyRequest);  // What if this fails?
    return response;  // No error handling
}
```

Users see raw Cloudflare 502/504 errors instead of graceful degradation.

## Task

1. **Add try/catch around origin fetch:**
   ```typescript
   async function proxyToOrigin(request: Request, env: Env): Promise<Response> {
     const originUrl = new URL(request.url);
     originUrl.host = env.ORIGIN_HOST;

     const proxyRequest = new Request(originUrl.toString(), {
       method: request.method,
       headers: request.headers,
       body: request.body,
     });

     try {
       const response = await fetch(proxyRequest, {
         cf: {
           cacheTtl: 0,
           cacheEverything: false,
         },
       });
       return response;
     } catch (error) {
       console.error('Origin fetch failed:', error);
       return new Response(
         JSON.stringify({
           error: 'Service temporarily unavailable',
           message: 'Please try again in a few moments',
         }),
         {
           status: 503,
           headers: {
             'Content-Type': 'application/json',
             'Retry-After': '30',
             'Cache-Control': 'no-store',
           },
         }
       );
     }
   }
   ```

2. **Implement stale-while-revalidate fallback:**
   ```typescript
   async function fetchWithFallback(
     request: Request,
     env: Env,
     ctx: ExecutionContext
   ): Promise<Response> {
     const cache = caches.default;
     const cacheKey = new Request(request.url, { method: 'GET' });

     try {
       const response = await proxyToOrigin(request, env);

       if (response.ok) {
         // Store in cache for fallback
         ctx.waitUntil(cache.put(cacheKey, response.clone()));
       }

       return response;
     } catch (error) {
       // Try to serve stale content
       const cached = await cache.match(cacheKey);

       if (cached) {
         console.log('Serving stale content due to origin failure');
         const staleResponse = new Response(cached.body, {
           status: cached.status,
           headers: {
             ...Object.fromEntries(cached.headers),
             'X-Cache-Status': 'STALE',
             'X-Origin-Error': 'true',
           },
         });
         return staleResponse;
       }

       // No cached content, return error
       return createErrorResponse(503, 'Origin unavailable and no cached content');
     }
   }
   ```

3. **Add circuit breaker pattern:**
   ```typescript
   // Track origin health
   const FAILURE_THRESHOLD = 5;
   const RECOVERY_TIME_MS = 30000;

   interface CircuitState {
     failures: number;
     lastFailure: number;
     open: boolean;
   }

   // Use Durable Objects or KV for state
   async function checkCircuitBreaker(env: Env): Promise<boolean> {
     const state = await env.CIRCUIT_STATE.get('origin', { type: 'json' }) as CircuitState | null;

     if (!state) return true; // Circuit closed

     if (state.open) {
       // Check if recovery time has passed
       if (Date.now() - state.lastFailure > RECOVERY_TIME_MS) {
         return true; // Half-open, allow one request
       }
       return false; // Circuit open
     }

     return true;
   }
   ```

4. **Add structured logging:**
   ```typescript
   function logRequest(request: Request, response: Response, duration: number) {
     console.log(JSON.stringify({
       timestamp: new Date().toISOString(),
       method: request.method,
       url: request.url,
       status: response.status,
       duration_ms: duration,
       cache_status: response.headers.get('X-Cache-Status') || 'MISS',
       origin_error: response.headers.get('X-Origin-Error') === 'true',
     }));
   }
   ```

5. **Add custom error pages:**
   ```typescript
   function createErrorPage(status: number, message: string): Response {
     const html = `
       <!DOCTYPE html>
       <html>
       <head>
         <title>${status} - Plue</title>
         <style>
           body { font-family: monospace; max-width: 600px; margin: 100px auto; }
           h1 { color: #333; }
         </style>
       </head>
       <body>
         <h1>${status}</h1>
         <p>${message}</p>
         <p>Please try again in a few moments.</p>
       </body>
       </html>
     `;

     return new Response(html, {
       status,
       headers: {
         'Content-Type': 'text/html',
         'Retry-After': '30',
       },
     });
   }
   ```

6. **Write tests:**
   ```typescript
   // edge/index.test.ts

   describe('error handling', () => {
     it('returns 503 when origin is unreachable', async () => {
       const request = new Request('https://plue.dev/api/test');
       const env = { ORIGIN_HOST: 'unreachable.invalid' };

       const response = await handleRequest(request, env);

       expect(response.status).toBe(503);
       expect(await response.json()).toHaveProperty('error');
     });

     it('serves stale content when origin fails', async () => {
       // Pre-populate cache
       // Simulate origin failure
       // Verify stale content is served
     });
   });
   ```

## Acceptance Criteria

- [ ] Origin failures return friendly 503 page
- [ ] Stale content served when available
- [ ] Circuit breaker prevents thundering herd
- [ ] All errors are logged with context
- [ ] Unit tests cover failure scenarios
- [ ] Retry-After header set appropriately
