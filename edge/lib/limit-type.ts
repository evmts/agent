import type { LimitType } from './rate-limit';

const WRITE_METHODS = ['POST', 'PUT', 'PATCH', 'DELETE'];

/**
 * Determine the rate limit type based on the request
 */
export function getLimitType(request: Request): LimitType {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  // Auth endpoints get stricter limits
  if (path.startsWith('/api/auth/')) {
    return 'auth';
  }

  // API write operations
  if (path.startsWith('/api/') && WRITE_METHODS.includes(method)) {
    return 'api:write';
  }

  // API read operations
  if (path.startsWith('/api/')) {
    return 'api';
  }

  // Default for page requests
  return 'default';
}
