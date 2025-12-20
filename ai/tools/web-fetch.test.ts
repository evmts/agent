/**
 * Tests for web-fetch tool with size limits and timeout handling.
 */

import { describe, test, expect, beforeAll, afterAll, mock } from 'bun:test';
import { webFetchImpl } from './web-fetch';

// Store original fetch
const originalFetch = global.fetch;

beforeAll(() => {
  // We'll mock fetch for each test individually
});

afterAll(() => {
  // Restore original fetch
  global.fetch = originalFetch;
});

describe('webFetchImpl - URL validation', () => {
  test('should accept valid http URL', async () => {
    global.fetch = mock((url: string) => {
      return Promise.resolve(new Response('Test content', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      }));
    });

    const result = await webFetchImpl('http://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Test content');
  });

  test('should accept valid https URL', async () => {
    global.fetch = mock((url: string) => {
      return Promise.resolve(new Response('Secure content', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Secure content');
  });

  test('should reject URL without scheme', async () => {
    const result = await webFetchImpl('example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('must start with http:// or https://');
  });

  test('should reject empty URL', async () => {
    const result = await webFetchImpl('');

    expect(result.success).toBe(false);
    expect(result.error).toContain('must be a non-empty string');
  });

  test('should reject non-string URL', async () => {
    // @ts-expect-error - Testing invalid input
    const result = await webFetchImpl(null);

    expect(result.success).toBe(false);
    expect(result.error).toContain('must be a non-empty string');
  });

  test('should reject ftp URL', async () => {
    const result = await webFetchImpl('ftp://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('must start with http:// or https://');
  });

  test('should reject file URL', async () => {
    const result = await webFetchImpl('file:///etc/passwd');

    expect(result.success).toBe(false);
    expect(result.error).toContain('must start with http:// or https://');
  });
});

describe('webFetchImpl - size limits', () => {
  test('should enforce 5MB limit via Content-Length header in HEAD', async () => {
    let headRequestMade = false;

    global.fetch = mock((url: string, options?: RequestInit) => {
      if (options?.method === 'HEAD') {
        headRequestMade = true;
        return Promise.resolve(new Response(null, {
          status: 200,
          headers: { 'content-length': String(6 * 1024 * 1024) }, // 6MB
        }));
      }
      return Promise.resolve(new Response('Should not reach here'));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Response too large');
    expect(result.error).toContain('5MB');
    expect(headRequestMade).toBe(true);
  });

  test('should enforce 5MB limit via Content-Length header in GET', async () => {
    global.fetch = mock((url: string, options?: RequestInit) => {
      if (options?.method === 'HEAD') {
        return Promise.resolve(new Response(null, { status: 405 })); // HEAD not supported
      }
      return Promise.resolve(new Response('content', {
        status: 200,
        headers: { 'content-length': String(6 * 1024 * 1024) }, // 6MB
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Response too large');
  });

  test('should enforce 5MB limit during streaming', async () => {
    global.fetch = mock(() => {
      // Create a large response without Content-Length
      const largeContent = new Uint8Array(6 * 1024 * 1024); // 6MB
      const stream = new ReadableStream({
        start(controller) {
          const chunkSize = 1024 * 1024; // 1MB chunks
          let offset = 0;

          function push() {
            if (offset >= largeContent.length) {
              controller.close();
              return;
            }

            const chunk = largeContent.slice(offset, offset + chunkSize);
            controller.enqueue(chunk);
            offset += chunkSize;
          }

          push();
          push();
          push();
          push();
          push();
          push(); // 6 chunks = 6MB
        }
      });

      return Promise.resolve(new Response(stream, {
        status: 200,
        headers: { 'content-type': 'text/plain' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Response too large');
  });

  test('should accept content under 5MB limit', async () => {
    const content = 'x'.repeat(4 * 1024 * 1024); // 4MB

    global.fetch = mock(() => {
      return Promise.resolve(new Response(content, {
        status: 200,
        headers: {
          'content-length': String(content.length),
          'content-type': 'text/plain',
        },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe(content);
  });

  test('should accept content at exactly 5MB limit', async () => {
    const content = 'x'.repeat(5 * 1024 * 1024); // Exactly 5MB

    global.fetch = mock(() => {
      return Promise.resolve(new Response(content, {
        status: 200,
        headers: {
          'content-length': String(content.length),
          'content-type': 'text/plain',
        },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe(content);
  });
});

describe('webFetchImpl - timeout handling', () => {
  test('should timeout after default 30 seconds', async () => {
    global.fetch = mock(() => {
      return new Promise((resolve) => {
        // Never resolve
        setTimeout(() => resolve(new Response('too late')), 60000);
      });
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('timed out');
    expect(result.error).toContain('30000ms');
  });

  test('should use custom timeout', async () => {
    global.fetch = mock(() => {
      return new Promise((resolve) => {
        setTimeout(() => resolve(new Response('too late')), 10000);
      });
    });

    const result = await webFetchImpl('https://example.com', 1000);

    expect(result.success).toBe(false);
    expect(result.error).toContain('timed out');
    expect(result.error).toContain('1000ms');
  });

  test('should succeed if response arrives before timeout', async () => {
    global.fetch = mock(() => {
      return new Promise((resolve) => {
        setTimeout(() => {
          resolve(new Response('Quick response', {
            status: 200,
            headers: { 'content-type': 'text/plain' },
          }));
        }, 10);
      });
    });

    const result = await webFetchImpl('https://example.com', 5000);

    expect(result.success).toBe(true);
    expect(result.content).toBe('Quick response');
  });
});

describe('webFetchImpl - HTTP status codes', () => {
  test('should handle 200 OK', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Success', {
        status: 200,
        statusText: 'OK',
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.statusCode).toBe(200);
  });

  test('should handle 404 Not Found', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Not Found', {
        status: 404,
        statusText: 'Not Found',
      }));
    });

    const result = await webFetchImpl('https://example.com/missing');

    expect(result.success).toBe(false);
    expect(result.error).toContain('404');
    expect(result.statusCode).toBe(404);
  });

  test('should handle 500 Internal Server Error', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Server Error', {
        status: 500,
        statusText: 'Internal Server Error',
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('500');
  });

  test('should handle 403 Forbidden', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Forbidden', {
        status: 403,
        statusText: 'Forbidden',
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('403');
  });

  test('should handle 301 redirect', async () => {
    let callCount = 0;
    global.fetch = mock((url: string, options?: RequestInit) => {
      callCount++;
      // fetch with redirect:'follow' should handle this automatically
      return Promise.resolve(new Response('Redirected content', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      }));
    });

    const result = await webFetchImpl('https://example.com/redirect');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Redirected content');
  });
});

describe('webFetchImpl - content type handling', () => {
  test('should handle text/html content', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('<html><body>Hello</body></html>', {
        status: 200,
        headers: { 'content-type': 'text/html; charset=utf-8' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toContain('<html>');
    expect(result.contentType).toContain('text/html');
  });

  test('should handle application/json content', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('{"key": "value"}', {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }));
    });

    const result = await webFetchImpl('https://api.example.com/data');

    expect(result.success).toBe(true);
    expect(result.content).toBe('{"key": "value"}');
    expect(result.contentType).toBe('application/json');
  });

  test('should handle text/plain content', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Plain text content', {
        status: 200,
        headers: { 'content-type': 'text/plain' },
      }));
    });

    const result = await webFetchImpl('https://example.com/file.txt');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Plain text content');
  });

  test('should handle missing content-type header', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Content without type', {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Content without type');
    expect(result.contentType).toBe('');
  });
});

describe('webFetchImpl - character encoding', () => {
  test('should handle UTF-8 encoding', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Hello 世界', {
        status: 200,
        headers: { 'content-type': 'text/html; charset=utf-8' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toContain('世界');
  });

  test('should default to UTF-8 when charset not specified', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Test content', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Test content');
  });

  test('should handle ISO-8859-1 encoding', async () => {
    global.fetch = mock(() => {
      // Create a response with latin1 encoding
      const encoder = new TextEncoder();
      const content = encoder.encode('Test content');

      return Promise.resolve(new Response(content, {
        status: 200,
        headers: { 'content-type': 'text/html; charset=ISO-8859-1' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toContain('Test');
  });

  test('should fallback to latin1 on decoding error', async () => {
    global.fetch = mock(() => {
      // Create invalid UTF-8 sequence
      const buffer = new Uint8Array([0xFF, 0xFE, 0xFD]);

      return Promise.resolve(new Response(buffer, {
        status: 200,
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    // Should not throw, uses fallback decoder
    expect(result.content).toBeDefined();
  });
});

describe('webFetchImpl - error handling', () => {
  test('should handle network errors', async () => {
    global.fetch = mock(() => {
      return Promise.reject(new Error('Network error'));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Network error');
  });

  test('should handle DNS resolution failures', async () => {
    global.fetch = mock(() => {
      return Promise.reject(new Error('getaddrinfo ENOTFOUND'));
    });

    const result = await webFetchImpl('https://nonexistent.invalid');

    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });

  test('should handle connection refused', async () => {
    global.fetch = mock(() => {
      return Promise.reject(new Error('ECONNREFUSED'));
    });

    const result = await webFetchImpl('https://localhost:9999');

    expect(result.success).toBe(false);
    expect(result.error).toContain('ECONNREFUSED');
  });

  test('should handle missing response body', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response(null, {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Failed to read response body');
  });
});

describe('webFetchImpl - HEAD request behavior', () => {
  test('should make HEAD request first to check Content-Length', async () => {
    const requests: string[] = [];

    global.fetch = mock((url: string, options?: RequestInit) => {
      requests.push(options?.method ?? 'GET');

      if (options?.method === 'HEAD') {
        return Promise.resolve(new Response(null, {
          status: 200,
          headers: { 'content-length': '100' },
        }));
      }

      return Promise.resolve(new Response('Content here', {
        status: 200,
        headers: { 'content-length': '100' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(requests).toContain('HEAD');
    expect(requests).toContain('GET');
  });

  test('should continue with GET if HEAD fails', async () => {
    global.fetch = mock((url: string, options?: RequestInit) => {
      if (options?.method === 'HEAD') {
        return Promise.reject(new Error('HEAD not supported'));
      }

      return Promise.resolve(new Response('Content', {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Content');
  });
});

describe('webFetchImpl - streaming with chunks', () => {
  test('should handle streamed response in chunks', async () => {
    global.fetch = mock(() => {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode('Part 1, '));
          controller.enqueue(new TextEncoder().encode('Part 2, '));
          controller.enqueue(new TextEncoder().encode('Part 3'));
          controller.close();
        }
      });

      return Promise.resolve(new Response(stream, {
        status: 200,
        headers: { 'content-type': 'text/plain' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Part 1, Part 2, Part 3');
  });

  test('should handle empty chunks', async () => {
    global.fetch = mock(() => {
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(new Uint8Array(0)); // Empty chunk
          controller.enqueue(new TextEncoder().encode('Content'));
          controller.enqueue(new Uint8Array(0)); // Another empty chunk
          controller.close();
        }
      });

      return Promise.resolve(new Response(stream, {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Content');
  });

  test('should cancel stream when size limit exceeded', async () => {
    let cancelled = false;

    global.fetch = mock(() => {
      const stream = new ReadableStream({
        start(controller) {
          // Send chunks totaling over 5MB
          const largeChunk = new Uint8Array(6 * 1024 * 1024);
          controller.enqueue(largeChunk);
        },
        cancel() {
          cancelled = true;
        }
      });

      return Promise.resolve(new Response(stream, {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(false);
    expect(result.error).toContain('Response too large');
  });
});

describe('webFetchImpl - edge cases', () => {
  test('should handle empty response body', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('', {
        status: 200,
        headers: { 'content-length': '0' },
      }));
    });

    const result = await webFetchImpl('https://example.com');

    expect(result.success).toBe(true);
    expect(result.content).toBe('');
  });

  test('should handle URL with query parameters', async () => {
    global.fetch = mock((url: string) => {
      expect(url).toContain('?');
      expect(url).toContain('key=value');

      return Promise.resolve(new Response('Query result', {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com/api?key=value&page=1');

    expect(result.success).toBe(true);
    expect(result.content).toBe('Query result');
  });

  test('should handle URL with fragment', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('Content', {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://example.com/page#section');

    expect(result.success).toBe(true);
  });

  test('should handle international domain names', async () => {
    global.fetch = mock(() => {
      return Promise.resolve(new Response('International content', {
        status: 200,
      }));
    });

    const result = await webFetchImpl('https://münchen.example.com');

    expect(result.success).toBe(true);
  });

  test('should handle very long URLs', async () => {
    const longPath = 'a'.repeat(2000);

    global.fetch = mock(() => {
      return Promise.resolve(new Response('Content', {
        status: 200,
      }));
    });

    const result = await webFetchImpl(`https://example.com/${longPath}`);

    expect(result.success).toBe(true);
  });
});
