# Fix JavaScript URI XSS in Markdown Renderer

## Priority: HIGH | Security

## Problem

The markdown renderer allows `javascript:` URIs in links, enabling XSS:

`ui/lib/markdown.ts:65`
```typescript
text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
```

Attack payload: `[Click me](javascript:alert(document.cookie))`

Also affects images at line 71:
```typescript
text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" loading="lazy">');
```

## Task

1. **Create URL sanitization function:**
   ```typescript
   // ui/lib/markdown.ts

   const DANGEROUS_PROTOCOLS = [
     'javascript:',
     'data:',
     'vbscript:',
     'file:',
   ];

   function sanitizeUrl(url: string): string {
     const trimmed = url.trim().toLowerCase();

     // Block dangerous protocols
     for (const protocol of DANGEROUS_PROTOCOLS) {
       if (trimmed.startsWith(protocol)) {
         return '#blocked-unsafe-url';
       }
     }

     // Block data URIs except for safe image types
     if (trimmed.startsWith('data:') && !trimmed.startsWith('data:image/')) {
       return '#blocked-unsafe-url';
     }

     return url;
   }
   ```

2. **Update link replacement:**
   ```typescript
   text = text.replace(
     /\[([^\]]+)\]\(([^)]+)\)/g,
     (match, linkText, url) => {
       const safeUrl = sanitizeUrl(url);
       return `<a href="${escapeHtml(safeUrl)}" target="_blank" rel="noopener">${escapeHtml(linkText)}</a>`;
     }
   );
   ```

3. **Update image replacement:**
   ```typescript
   text = text.replace(
     /!\[([^\]]*)\]\(([^)]+)\)/g,
     (match, alt, src) => {
       const safeSrc = sanitizeUrl(src);
       return `<img src="${escapeHtml(safeSrc)}" alt="${escapeHtml(alt)}" loading="lazy">`;
     }
   );
   ```

4. **Add autolink protection:**
   - Check if autolinks (bare URLs) are also vulnerable
   - Apply same sanitization

5. **Write unit tests:**
   ```typescript
   // ui/lib/__tests__/markdown.test.ts

   describe('URL sanitization', () => {
     it('blocks javascript: URLs', () => {
       const result = renderMarkdown('[click](javascript:alert(1))');
       expect(result).toContain('href="#blocked-unsafe-url"');
       expect(result).not.toContain('javascript:');
     });

     it('blocks data: URLs', () => {
       const result = renderMarkdown('[click](data:text/html,<script>alert(1)</script>)');
       expect(result).toContain('#blocked-unsafe-url');
     });

     it('allows https: URLs', () => {
       const result = renderMarkdown('[link](https://example.com)');
       expect(result).toContain('href="https://example.com"');
     });

     it('allows relative URLs', () => {
       const result = renderMarkdown('[link](/path/to/page)');
       expect(result).toContain('href="/path/to/page"');
     });

     it('escapes HTML in URLs', () => {
       const result = renderMarkdown('[link](https://example.com?q=<script>)');
       expect(result).toContain('&lt;script&gt;');
       expect(result).not.toContain('<script>');
     });
   });
   ```

6. **Add E2E test:**
   - Create issue with XSS payload in body
   - Verify script doesn't execute
   - Verify link is rendered safely

## Acceptance Criteria

- [ ] `javascript:` URLs are blocked
- [ ] `data:` URLs are blocked (except safe images)
- [ ] `vbscript:` URLs are blocked
- [ ] HTML is escaped in URLs
- [ ] Unit tests cover all XSS vectors
- [ ] E2E test verifies protection
- [ ] Existing markdown functionality still works
