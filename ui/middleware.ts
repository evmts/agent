import { defineMiddleware } from 'astro:middleware';
import { getCurrentUser } from './lib/api';

/**
 * Security headers middleware
 * Adds Content-Security-Policy and other security headers to all responses
 * Also reads user from X-Plue-User-Address header set by edge worker
 */
export const onRequest = defineMiddleware(async (context, next) => {
  // Check if edge worker passed authenticated user via header
  const walletAddress = context.request.headers.get('X-Plue-User-Address');
  if (walletAddress) {
    try {
      // Call API to get user by wallet address
      const user = await getCurrentUser(context.request.headers);
      if (user) {
        context.locals.user = {
          id: user.id,
          username: user.username,
          email: null, // API doesn't return email
          displayName: user.displayName,
          isAdmin: false, // API doesn't return this field
          isActive: true, // Assume active if returned
          walletAddress: walletAddress,
        };
      }
    } catch (error) {
      console.error('Failed to fetch user by wallet address:', error);
    }
  }

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
