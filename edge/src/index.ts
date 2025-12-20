import type { Env, JWTPayload } from './types';
import { matchRoute, getDoName } from './router';
import { validateSession } from './lib/auth';

// Page handlers
import { handleHome } from './pages/home';
import { handleUserProfile } from './pages/user-profile';
import { handleIssuesList } from './pages/issues-list';
import { handleIssueDetail } from './pages/issue-detail';
import { handlePullsList } from './pages/pulls-list';
import { handlePullDetail } from './pages/pull-detail';
import { handleLogin } from './pages/login';
import { handleRegister } from './pages/register';

// Export Durable Object
export { DataSyncDO } from './durable-objects/data-sync';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // All non-GET requests go to origin (writes, form submissions)
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return proxyToOrigin(request, env);
    }

    // Route matching
    const route = matchRoute(url.pathname);

    // If route should go to origin, proxy it
    if (route.type === 'origin') {
      return proxyToOrigin(request, env);
    }

    // Validate session for edge routes
    const user = await validateSession(request, env.JWT_SECRET);

    // Handle edge routes
    try {
      switch (route.handler) {
        case 'home':
          return handleHome(request, env, user);

        case 'login':
          return handleLogin(request, env, user);

        case 'register':
          return handleRegister(request, env, user);

        case 'settings':
          // Settings requires auth, redirect if not logged in
          if (!user) {
            return Response.redirect(`${url.origin}/login?redirect=/settings`, 302);
          }
          // Proxy to origin for now (has form handling)
          return proxyToOrigin(request, env);

        case 'userProfile':
          return handleUserProfile(request, env, user, route.params as { user: string });

        case 'issuesList':
          return handleIssuesList(
            request,
            env,
            user,
            route.params as { user: string; repo: string }
          );

        case 'issueDetail':
          return handleIssueDetail(
            request,
            env,
            user,
            route.params as { user: string; repo: string; number: string }
          );

        case 'pullsList':
          return handlePullsList(
            request,
            env,
            user,
            route.params as { user: string; repo: string }
          );

        case 'pullDetail':
          return handlePullDetail(
            request,
            env,
            user,
            route.params as { user: string; repo: string; number: string }
          );

        default:
          // Unknown edge route, proxy to origin
          return proxyToOrigin(request, env);
      }
    } catch (error) {
      console.error('Edge handler error:', error);
      // On error, fall back to origin
      return proxyToOrigin(request, env);
    }
  },
};

async function proxyToOrigin(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  // Rewrite to origin host
  // In production this goes through Cloudflare Tunnel
  const originUrl = new URL(url.pathname + url.search, `https://${env.ORIGIN_HOST}`);

  // Clone request with new URL
  const proxyRequest = new Request(originUrl.toString(), {
    method: request.method,
    headers: request.headers,
    body: request.body,
    redirect: 'manual', // Handle redirects ourselves
  });

  // Forward to origin
  const response = await fetch(proxyRequest);

  // Return response, potentially rewriting redirect URLs
  if (response.status >= 300 && response.status < 400) {
    const location = response.headers.get('Location');
    if (location) {
      // Rewrite origin URLs back to edge
      const newLocation = location.replace(`https://${env.ORIGIN_HOST}`, url.origin);
      const headers = new Headers(response.headers);
      headers.set('Location', newLocation);
      return new Response(response.body, {
        status: response.status,
        headers,
      });
    }
  }

  return response;
}
