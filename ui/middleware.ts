import { defineMiddleware } from 'astro:middleware';

/**
 * Security headers middleware
 * Adds Content-Security-Policy and other security headers to all responses
 */
export const onRequest = defineMiddleware(async (_context, next) => {
  const response = await next();

  // Clone response to add headers
  const headers = new Headers(response.headers);

  // Content-Security-Policy
  // Note: 'unsafe-inline' for scripts/styles is required for Astro's hydration
  const csp = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'", // unsafe-inline needed for Astro hydration
    "style-src 'self' 'unsafe-inline'",  // unsafe-inline needed for component styles
    "img-src 'self' data: https:",       // Allow images from self, data URIs, and HTTPS
    "connect-src 'self' https://api.anthropic.com", // API calls
    "font-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",            // Prevent clickjacking
    "upgrade-insecure-requests"          // Upgrade HTTP to HTTPS
  ].join('; ');

  headers.set('Content-Security-Policy', csp);

  // Prevent MIME type sniffing
  headers.set('X-Content-Type-Options', 'nosniff');

  // Prevent clickjacking
  headers.set('X-Frame-Options', 'DENY');

  // Referrer policy - only send origin on cross-origin requests
  headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');

  // Prevent browsers from performing MIME sniffing
  headers.set('X-XSS-Protection', '1; mode=block');

  // Enforce HTTPS
  headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
});
