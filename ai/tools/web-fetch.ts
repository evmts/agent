/**
 * Web fetch tool with size limits.
 *
 * Implements a 5MB size limit for web fetch operations to prevent
 * memory exhaustion and denial-of-service issues.
 */

import { tool } from 'ai';
import { z } from 'zod';

// Constants
const MAX_RESPONSE_SIZE = 5 * 1024 * 1024; // 5MB
const DEFAULT_TIMEOUT_MS = 30000; // 30 seconds

interface WebFetchResult {
  success: boolean;
  content?: string;
  error?: string;
  statusCode?: number;
  contentType?: string;
}

async function webFetchImpl(
  url: string,
  timeoutMs?: number
): Promise<WebFetchResult> {
  // Validate URL
  if (!url || typeof url !== 'string') {
    return { success: false, error: 'URL must be a non-empty string' };
  }

  // Ensure URL has a scheme
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return { success: false, error: 'URL must start with http:// or https://' };
  }

  const timeout = timeoutMs ?? DEFAULT_TIMEOUT_MS;

  try {
    // Create abort controller for timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      // First, try HEAD request to check Content-Length
      try {
        const headResponse = await fetch(url, {
          method: 'HEAD',
          signal: controller.signal,
          redirect: 'follow',
        });

        const contentLength = headResponse.headers.get('content-length');
        if (contentLength) {
          const size = parseInt(contentLength, 10);
          if (size > MAX_RESPONSE_SIZE) {
            return {
              success: false,
              error: 'Response too large (exceeds 5MB limit)',
            };
          }
        }
      } catch {
        // HEAD request failed, continue with GET
      }

      // Perform GET request
      const response = await fetch(url, {
        method: 'GET',
        signal: controller.signal,
        redirect: 'follow',
      });

      if (!response.ok) {
        return {
          success: false,
          error: `HTTP error ${response.status}: ${response.statusText}`,
          statusCode: response.status,
        };
      }

      // Check Content-Length from GET response
      const contentLength = response.headers.get('content-length');
      if (contentLength) {
        const size = parseInt(contentLength, 10);
        if (size > MAX_RESPONSE_SIZE) {
          return {
            success: false,
            error: 'Response too large (exceeds 5MB limit)',
          };
        }
      }

      // Read response with size limit
      const reader = response.body?.getReader();
      if (!reader) {
        return { success: false, error: 'Failed to read response body' };
      }

      const chunks: Uint8Array[] = [];
      let totalSize = 0;

      while (true) {
        const { done, value } = await reader.read();

        if (done) break;

        chunks.push(value);
        totalSize += value.length;

        if (totalSize > MAX_RESPONSE_SIZE) {
          reader.cancel();
          return {
            success: false,
            error: 'Response too large (exceeds 5MB limit)',
          };
        }
      }

      // Combine chunks
      const combined = new Uint8Array(totalSize);
      let offset = 0;
      for (const chunk of chunks) {
        combined.set(chunk, offset);
        offset += chunk.length;
      }

      // Decode to string
      const contentType = response.headers.get('content-type') ?? '';
      let encoding = 'utf-8';

      if (contentType.includes('charset=')) {
        const match = contentType.match(/charset=([^;]+)/);
        if (match?.[1]) {
          encoding = match[1].trim();
        }
      }

      let content: string;
      try {
        const decoder = new TextDecoder(encoding);
        content = decoder.decode(combined);
      } catch {
        // Fallback to latin1
        const decoder = new TextDecoder('latin1');
        content = decoder.decode(combined);
      }

      return {
        success: true,
        content,
        statusCode: response.status,
        contentType,
      };
    } finally {
      clearTimeout(timeoutId);
    }
  } catch (error) {
    if (error instanceof Error) {
      if (error.name === 'AbortError') {
        return {
          success: false,
          error: `Request timed out after ${timeout}ms`,
        };
      }
      return {
        success: false,
        error: `Request failed: ${error.message}`,
      };
    }
    return {
      success: false,
      error: `Request failed: ${error}`,
    };
  }
}

const webFetchParameters = z.object({
  url: z.string().describe('URL to fetch (must start with http:// or https://)'),
  timeoutMs: z.number().optional().describe('Request timeout in milliseconds (default: 30000)'),
});

export const webFetchTool = tool({
  description: `Fetch content from a URL.

Downloads and returns the content of a web page or API endpoint.
Enforces a 5MB size limit to prevent memory issues.

Use this for:
- Fetching documentation
- API responses
- Web page content

Note: For large files or binary content, this tool will return an error.`,
  parameters: webFetchParameters,
  // @ts-expect-error - Zod v4 type inference issue with AI SDK
  execute: async (args: z.infer<typeof webFetchParameters>) => {
    const result = await webFetchImpl(args.url, args.timeoutMs);
    return result.success
      ? result.content!
      : `Error: ${result.error}`;
  },
});

export { webFetchImpl };
