/**
 * Cache utilities for Astro pages.
 *
 * Usage in .astro files:
 * ```astro
 * ---
 * import { cacheStatic, cacheWithTags, noCache } from '../lib/cache';
 *
 * // Static page - cache forever until deploy
 * cacheStatic(Astro);
 *
 * // Page with DB data - cache with tags for targeted invalidation
 * cacheWithTags(Astro, ['user:123', 'repo:456']);
 *
 * // Dynamic page - no cache
 * noCache(Astro);
 * ---
 * ```
 */

interface AstroContext {
  response: {
    headers: Headers;
  };
}

/** One year in seconds */
const ONE_YEAR = 31536000;

/** One hour in seconds */
const ONE_HOUR = 3600;

/**
 * Cache static pages forever (until deploy invalidates via version key).
 * Use for: login, register, landing pages, static content
 */
export function cacheStatic(astro: AstroContext): void {
  astro.response.headers.set('Cache-Control', `public, max-age=${ONE_YEAR}, immutable`);
}

/**
 * Cache page with specific tags for targeted invalidation.
 * Use for: user profiles, repo pages, issue pages
 *
 * @param tags - Cache tags for invalidation (e.g., ['user:123', 'repo:456'])
 * @param maxAge - Max age in seconds (default: 1 year)
 */
export function cacheWithTags(
  astro: AstroContext,
  tags: string[],
  maxAge: number = ONE_YEAR
): void {
  astro.response.headers.set('Cache-Control', `public, max-age=${maxAge}`);
  astro.response.headers.set('Cache-Tag', tags.join(','));
}

/**
 * Cache for a short duration with stale-while-revalidate.
 * Use for: frequently changing lists (issues, activity feeds)
 *
 * Note: SWR is not fully supported by CF Cache API but works with CF CDN.
 *
 * @param maxAge - Fresh duration in seconds (default: 60)
 * @param staleAge - Stale-while-revalidate duration (default: 1 hour)
 */
export function cacheShort(
  astro: AstroContext,
  tags: string[] = [],
  maxAge: number = 60,
  staleAge: number = ONE_HOUR
): void {
  astro.response.headers.set(
    'Cache-Control',
    `public, max-age=${maxAge}, stale-while-revalidate=${staleAge}`
  );
  if (tags.length > 0) {
    astro.response.headers.set('Cache-Tag', tags.join(','));
  }
}

/**
 * Disable caching entirely.
 * Use for: dashboards, personalized content, auth-dependent pages
 */
export function noCache(astro: AstroContext): void {
  astro.response.headers.set('Cache-Control', 'private, no-store, no-cache, must-revalidate');
}

/**
 * Helper to generate common cache tags.
 */
export const CacheTags = {
  user: (id: number | string) => `user:${id}`,
  repo: (owner: string, name: string) => `repo:${owner}/${name}`,
  repoById: (id: number | string) => `repo:${id}`,
  issues: (repoId: number | string) => `repo:${repoId}:issues`,
  issue: (repoId: number | string, issueNum: number) => `issue:${repoId}:${issueNum}`,
  pulls: (repoId: number | string) => `repo:${repoId}:pulls`,
  commits: (repoId: number | string) => `repo:${repoId}:commits`,
};
