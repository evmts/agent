# Implement Content Security Policy Headers

## Priority: MEDIUM | Security

## Problem

No Content-Security-Policy headers are set, leaving the app vulnerable to XSS attacks even if one gets through the escaping layer.

## Task

1. **Define CSP policy:**
   ```typescript
   // ui/middleware/security.ts

   export const CSP_POLICY = {
     'default-src': ["'self'"],
     'script-src': [
       "'self'",
       "'unsafe-inline'",  // Required for Astro view transitions
       // Add any CDN scripts here
     ],
     'style-src': [
       "'self'",
       "'unsafe-inline'",  // Required for Astro
     ],
     'img-src': [
       "'self'",
       'data:',
       'https:',  // Allow external images
     ],
     'font-src': ["'self'"],
     'connect-src': [
       "'self'",
       'https://api.anthropic.com',  // Claude API
     ],
     'frame-ancestors': ["'none'"],  // Prevent clickjacking
     'form-action': ["'self'"],
     'base-uri': ["'self'"],
     'object-src': ["'none'"],
   };

   export function buildCSPHeader(): string {
     return Object.entries(CSP_POLICY)
       .map(([key, values]) => `${key} ${values.join(' ')}`)
       .join('; ');
   }
   ```

2. **Add middleware in Astro:**
   ```typescript
   // ui/src/middleware.ts

   import { defineMiddleware } from 'astro:middleware';
   import { buildCSPHeader } from './middleware/security';

   export const onRequest = defineMiddleware(async (context, next) => {
     const response = await next();

     // Clone response to modify headers
     const newResponse = new Response(response.body, response);

     // Add security headers
     newResponse.headers.set('Content-Security-Policy', buildCSPHeader());
     newResponse.headers.set('X-Content-Type-Options', 'nosniff');
     newResponse.headers.set('X-Frame-Options', 'DENY');
     newResponse.headers.set('X-XSS-Protection', '1; mode=block');
     newResponse.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
     newResponse.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');

     return newResponse;
   });
   ```

3. **Add CSP to edge worker:**
   ```typescript
   // edge/index.ts

   async function addSecurityHeaders(response: Response): Promise<Response> {
     const newHeaders = new Headers(response.headers);

     // Only add CSP if not already set by origin
     if (!newHeaders.has('Content-Security-Policy')) {
       newHeaders.set('Content-Security-Policy', buildCSPHeader());
     }

     newHeaders.set('X-Content-Type-Options', 'nosniff');
     newHeaders.set('X-Frame-Options', 'DENY');
     newHeaders.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

     return new Response(response.body, {
       status: response.status,
       headers: newHeaders,
     });
   }
   ```

4. **Use nonces for inline scripts (optional, more secure):**
   ```typescript
   // Generate nonce per request
   const nonce = crypto.randomUUID();

   // Add to CSP
   'script-src': [`'nonce-${nonce}'`],

   // Pass nonce to templates
   <script nonce={nonce}>
     // Inline script
   </script>
   ```

5. **Add CSP violation reporting:**
   ```typescript
   // Add report-uri to CSP
   'report-uri': ['/api/csp-report'],

   // Or use report-to (newer)
   'report-to': ['csp-endpoint'],

   // Create endpoint
   // ui/pages/api/csp-report.ts
   export async function POST({ request }) {
     const report = await request.json();
     console.error('CSP Violation:', JSON.stringify(report));
     // Send to logging service
     return new Response(null, { status: 204 });
   }
   ```

6. **Test CSP doesn't break functionality:**
   - [ ] All pages load without CSP errors
   - [ ] View transitions work
   - [ ] Markdown rendering works
   - [ ] External images load
   - [ ] API calls work

7. **Add E2E test:**
   ```typescript
   // e2e/cases/security.spec.ts

   test('CSP header is set', async ({ page }) => {
     const response = await page.goto('/');
     const csp = response?.headers()['content-security-policy'];

     expect(csp).toContain("default-src 'self'");
     expect(csp).toContain("frame-ancestors 'none'");
   });

   test('inline script without nonce is blocked', async ({ page }) => {
     // Inject script via XSS simulation
     // Verify it doesn't execute
   });
   ```

8. **Document CSP policy:**
   - Explain each directive
   - Document how to add new sources
   - Link to CSP evaluator tools

## Acceptance Criteria

- [ ] CSP header set on all responses
- [ ] No CSP violations in normal operation
- [ ] Violation reporting enabled
- [ ] All security headers present
- [ ] E2E tests verify headers
- [ ] Documentation updated
