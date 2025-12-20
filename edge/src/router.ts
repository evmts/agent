import type { RouteMatch } from './types';

interface RoutePattern {
  pattern: RegExp;
  handler: string;
  paramNames: string[];
}

// Edge routes - served from Durable Objects with synced SQLite
const EDGE_ROUTES: RoutePattern[] = [
  { pattern: /^\/$/, handler: 'home', paramNames: [] },
  { pattern: /^\/login$/, handler: 'login', paramNames: [] },
  { pattern: /^\/register$/, handler: 'register', paramNames: [] },
  { pattern: /^\/settings$/, handler: 'settings', paramNames: [] },
  { pattern: /^\/([^\/]+)$/, handler: 'userProfile', paramNames: ['user'] },
  {
    pattern: /^\/([^\/]+)\/([^\/]+)\/issues$/,
    handler: 'issuesList',
    paramNames: ['user', 'repo'],
  },
  {
    pattern: /^\/([^\/]+)\/([^\/]+)\/issues\/(\d+)$/,
    handler: 'issueDetail',
    paramNames: ['user', 'repo', 'number'],
  },
  {
    pattern: /^\/([^\/]+)\/([^\/]+)\/pulls$/,
    handler: 'pullsList',
    paramNames: ['user', 'repo'],
  },
  {
    pattern: /^\/([^\/]+)\/([^\/]+)\/pulls\/(\d+)$/,
    handler: 'pullDetail',
    paramNames: ['user', 'repo', 'number'],
  },
];

// Origin routes - must be proxied to GKE (require git operations)
const ORIGIN_PATTERNS: RegExp[] = [
  /^\/new$/, // Create repo - needs initRepo()
  /^\/([^\/]+)\/([^\/]+)$/, // Repo home - needs getTree(), README
  /^\/([^\/]+)\/([^\/]+)\/tree\/.*/, // Directory browser - needs getTree()
  /^\/([^\/]+)\/([^\/]+)\/blob\/.*/, // File viewer - needs getFileContent()
  /^\/([^\/]+)\/([^\/]+)\/commits\/.*/, // Commit history - needs getCommits()
  /^\/([^\/]+)\/([^\/]+)\/branches$/, // Branch management - needs listBranches()
  /^\/([^\/]+)\/([^\/]+)\/pulls\/\d+\/files$/, // PR diff - needs compareRefs()
];

export function matchRoute(pathname: string): RouteMatch {
  // API routes always go to origin
  if (pathname.startsWith('/api/')) {
    return { type: 'origin' };
  }

  // Static assets go to origin (or could be served from R2/KV)
  if (
    pathname.startsWith('/_astro/') ||
    pathname.startsWith('/assets/') ||
    pathname.endsWith('.css') ||
    pathname.endsWith('.js') ||
    pathname.endsWith('.ico')
  ) {
    return { type: 'origin' };
  }

  // Check origin patterns first (more specific git routes)
  for (const pattern of ORIGIN_PATTERNS) {
    if (pattern.test(pathname)) {
      return { type: 'origin' };
    }
  }

  // Check edge routes
  for (const route of EDGE_ROUTES) {
    const match = pathname.match(route.pattern);
    if (match) {
      const params: Record<string, string> = {};
      route.paramNames.forEach((name, index) => {
        params[name] = match[index + 1];
      });
      return { type: 'edge', handler: route.handler, params };
    }
  }

  // Default to origin for unmatched routes (404 handling, etc.)
  return { type: 'origin' };
}

export function getDoName(params?: Record<string, string>): string {
  // Per-repository Durable Objects for repo-scoped data
  if (params?.user && params?.repo) {
    return `repo:${params.user}/${params.repo}`;
  }
  // Global DO for home page, user profiles, etc.
  return 'global';
}
