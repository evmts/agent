/**
 * Public routes that don't require authentication
 *
 * These routes are accessible without a valid session.
 */

/** Routes that bypass authentication */
export const PUBLIC_ROUTES: (string | RegExp)[] = [
  // Landing and static pages
  '/',
  '/about',
  '/pricing',
  '/docs',

  // Auth endpoints (handled by edge worker)
  '/api/auth/nonce',
  '/api/auth/verify',
  '/api/auth/logout',

  // Health checks and observability
  '/api/health',
  '/api/ready',
  '/metrics',

  // Public repository pages (pattern: /owner/repo)
  // Uses negative lookahead to exclude reserved paths like /api/, /settings/
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+$/,

  // Public tree view: /owner/repo/tree/branch/path
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/tree\/.*/,

  // Public blob view: /owner/repo/blob/branch/path
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/blob\/.*/,

  // Public commits: /owner/repo/commits
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/commits$/,

  // Public commit view: /owner/repo/commit/sha
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/commit\/[a-f0-9]+$/,

  // Public issues list: /owner/repo/issues
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/issues$/,

  // Public issue view: /owner/repo/issues/123
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/issues\/\d+$/,

  // Raw file access (for git operations)
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\/raw\/.*/,

  // Git info refs (for git clone)
  /^\/(?!api\/|settings\/)[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\.git\/info\/refs$/,
];

/**
 * Check if a path is public (doesn't require authentication)
 */
export function isPublicRoute(pathname: string): boolean {
  for (const route of PUBLIC_ROUTES) {
    if (typeof route === 'string') {
      if (pathname === route) return true;
    } else {
      if (route.test(pathname)) return true;
    }
  }
  return false;
}

/**
 * Routes that should be handled by the edge worker (not proxied to origin)
 */
export const EDGE_HANDLED_ROUTES = [
  '/api/auth/nonce',
  '/api/auth/verify',
  '/api/auth/logout',
];

/**
 * Check if a path should be handled by the edge worker
 */
export function isEdgeHandledRoute(pathname: string): boolean {
  return EDGE_HANDLED_ROUTES.includes(pathname);
}
