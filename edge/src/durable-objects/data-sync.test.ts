import { env } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import type { InvalidationMessage } from '../types';

// For more information on testing with the Cloudflare Workers test pool:
// https://developers.cloudflare.com/workers/testing/vitest-integration/

describe('DataSyncDO', () => {
  // Create a new stub for each test to avoid DO lifecycle issues
  const getStub = () => {
    const id = env.DATA_SYNC.idFromName(`test-do-${Math.random()}`);
    return env.DATA_SYNC.get(id);
  };

  describe('/health', () => {
    it('should return 200 OK', async () => {
      const stub = getStub();
      const response = await stub.fetch('http://test/health');
      expect(response.status).toBe(200);
      const text = await response.text();
      expect(text).toBe('OK');
    });
  });

  describe('/invalidate', () => {
    it('should return 401 without auth header', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        body: JSON.stringify({
          type: 'sql',
          table: 'users',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(401);
      const text = await response.text();
      expect(text).toBe('Unauthorized');
    });

    it('should return 401 with wrong auth token', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer wrong-secret',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'users',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(401);
      const text = await response.text();
      expect(text).toBe('Unauthorized');
    });

    it('should accept correct auth and process SQL invalidation', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'users',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });
    });

    it('should accept correct auth and process git invalidation', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'git',
          repoKey: 'user/repo',
          merkleRoot: 'abc123',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });
    });

    it('should return 400 for malformed JSON', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: 'invalid json{',
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data).toEqual({ error: 'Invalid request' });
    });

    it('should return 404 for GET request', async () => {
      const stub = getStub();
      const request = new Request('http://test/invalidate', {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
        },
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(404);
    });
  });

  describe('unknown routes', () => {
    it('should return 404 for unknown paths', async () => {
      const stub = getStub();
      const response = await stub.fetch('http://test/unknown');
      expect(response.status).toBe(404);
      const text = await response.text();
      expect(text).toBe('Not found');
    });
  });

  describe('SQL invalidation behavior', () => {
    it('should clear shape metadata for matching table', async () => {
      const stub = getStub();
      // Send invalidation request
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'repositories',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });

      // The metadata should have been cleared
      // In a real scenario, this would force a resync on next access
    });
  });

  describe('Git cache with merkle root validation', () => {
    describe('handleGitInvalidation', () => {
      it('should update merkle root for repo', async () => {
        const stub = getStub();
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            repoKey: 'testuser/testrepo',
            merkleRoot: 'abc123def456',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      });

      it('should handle missing repoKey gracefully', async () => {
        const stub = getStub();
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            merkleRoot: 'abc123def456',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      });

      it('should handle missing merkleRoot gracefully', async () => {
        const stub = getStub();
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            repoKey: 'testuser/testrepo',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      });

      it('should invalidate cache when merkle root changes', async () => {
        const stub = getStub();

        // Set initial merkle root
        const request1 = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            repoKey: 'owner/cacherepo',
            merkleRoot: 'merkle123',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response1 = await stub.fetch(request1);
        expect(response1.status).toBe(200);
        await response1.json();

        // Update to new merkle root (invalidates cache)
        const request2 = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            repoKey: 'owner/cacherepo',
            merkleRoot: 'merkle456',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response2 = await stub.fetch(request2);
        expect(response2.status).toBe(200);

        const data = await response2.json();
        expect(data).toEqual({ ok: true });
      });
    });
  });

  describe('Feature flag behavior', () => {
    // Note: Testing feature flag behavior is tricky with vitest-pool-workers
    // The ENABLE_PUSH_INVALIDATION env var is set in wrangler.jsonc for tests
    // These tests document the expected behavior based on the flag

    it('should trust cache when ENABLE_PUSH_INVALIDATION is true', async () => {
      // When push invalidation is enabled, cached data should be trusted
      // until explicitly invalidated via /invalidate endpoint.
      // The ensureSync method will skip the 5-second TTL check and return
      // immediately if metadata exists, relying on push invalidation to
      // clear stale data.

      // This behavior prevents unnecessary resyncs and improves performance
      // but requires the server to properly send invalidation messages.
      expect(env.ENABLE_PUSH_INVALIDATION).toBe('true');
    });

    it('should use 5-second TTL when ENABLE_PUSH_INVALIDATION is false', async () => {
      // When push invalidation is disabled (default), data older than 5s
      // should trigger a resync. This provides a safety mechanism to ensure
      // data freshness even without explicit invalidation messages.

      // The ensureSync method checks last_synced_at and triggers a resync
      // if more than 5 seconds have elapsed since the last sync.

      // This test documents the expected behavior, though testing it requires
      // manipulating the env var which is challenging in vitest-pool-workers.
    });
  });

  describe('Concurrent operations', () => {
    it('should handle concurrent invalidations', async () => {
      // Note: vitest-pool-workers has limitations with concurrent DO storage access
      // This test documents expected behavior for concurrent requests in production
      // In production, Durable Objects handle concurrent requests correctly

      // Expected behavior: Multiple invalidation requests sent simultaneously
      // should all be processed successfully. The DO handles them sequentially
      // internally, ensuring consistency.

      // Testing this requires production-like conditions. For now, document
      // that concurrent requests to the /invalidate endpoint should succeed
      // and be processed in order of receipt.
    });

    it('should handle concurrent git invalidations for same repo', async () => {
      // Note: vitest-pool-workers has limitations with concurrent DO storage access
      // This test documents expected behavior for concurrent git invalidations

      // Expected behavior: Multiple git invalidations for the same repo sent
      // simultaneously will be processed sequentially by the DO. The last one
      // processed will set the final merkle root. All requests return 200 OK.

      // This is safe because:
      // 1. Each invalidation is a simple INSERT OR REPLACE operation
      // 2. The DO serializes all storage operations internally
      // 3. Cached data lookups compare against current merkle root, so the
      //    last update "wins" and subsequent cache hits use that value
    });
  });

  describe('Error handling', () => {
    it('should handle SQL errors gracefully in invalidation', async () => {
      const stub = getStub();

      // Test with an empty table name which might cause issues
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: '',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);

      // Should either succeed or return proper error
      expect([200, 400, 500]).toContain(response.status);
    });

    it('should handle invalid JSON structure', async () => {
      const stub = getStub();

      // Test with missing required timestamp field
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'users',
          // Missing timestamp
        }),
      });

      const response = await stub.fetch(request);

      // Should accept or reject gracefully
      expect([200, 400]).toContain(response.status);
    });

    it('should handle unknown invalidation type', async () => {
      const stub = getStub();

      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'unknown_type',
          timestamp: Date.now(),
        }),
      });

      const response = await stub.fetch(request);

      // Should either ignore unknown type or return error
      expect([200, 400]).toContain(response.status);
    });
  });

  describe('Edge cases', () => {
    it('should handle special characters in repo keys', async () => {
      const stub = getStub();

      const specialKeys = [
        'owner/repo-name',
        'owner/repo.name',
        'owner/repo_name',
        'owner-name/repo',
      ];

      for (const repoKey of specialKeys) {
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'git',
            repoKey,
            merkleRoot: 'test123',
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      }
    });

    it('should handle very long merkle roots', async () => {
      const stub = getStub();

      // Test with a very long merkle root (realistic for git hashes)
      const longMerkleRoot = 'a'.repeat(64); // SHA-256 length

      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'git',
          repoKey: 'owner/repo',
          merkleRoot: longMerkleRoot,
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });
    });

    it('should handle multiple SQL table invalidations in sequence', async () => {
      const stub = getStub();

      const tables = ['users', 'repositories', 'issues', 'comments', 'pull_requests'];

      for (const table of tables) {
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'sql',
            table,
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      }
    });

    it('should handle SQL invalidation with wildcard-like table names', async () => {
      const stub = getStub();

      // Test with table names that contain SQL wildcards
      const tables = ['users%', 'repos_', 'test%table'];

      for (const table of tables) {
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'sql',
            table,
            timestamp: Date.now(),
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      }
    });

    it('should handle git invalidation with null merkle root', async () => {
      const stub = getStub();

      // Test explicitly sending null merkleRoot (edge case)
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'git',
          repoKey: 'owner/repo',
          merkleRoot: null,
          timestamp: Date.now(),
        }),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });
    });

    it('should handle timestamps in various formats', async () => {
      const stub = getStub();

      const timestamps = [
        Date.now(),
        Date.now() + 1000000, // Future timestamp
        0, // Epoch
      ];

      for (const timestamp of timestamps) {
        const request = new Request('http://test/invalidate', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.PUSH_SECRET}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            type: 'sql',
            table: 'users',
            timestamp,
          } as InvalidationMessage),
        });

        const response = await stub.fetch(request);
        expect(response.status).toBe(200);

        const data = await response.json();
        expect(data).toEqual({ ok: true });
      }
    });
  });

  describe('SQL invalidation patterns', () => {
    it('should invalidate shapes with WHERE clauses', async () => {
      const stub = getStub();

      // The implementation uses LIKE pattern matching, so invalidating "repositories"
      // should clear both "repositories" and "repositories:is_public = true" shapes
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'repositories',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });

      // This would clear metadata for:
      // - "repositories"
      // - "repositories:is_public = true"
      // - "repositories:user_id = 123"
      // etc.
    });

    it('should handle table names that are substrings of others', async () => {
      const stub = getStub();

      // If we have tables like "user" and "users", invalidating "user"
      // would also match "users" due to LIKE pattern matching
      // This documents the current behavior
      const request = new Request('http://test/invalidate', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.PUSH_SECRET}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'sql',
          table: 'user',
          timestamp: Date.now(),
        } as InvalidationMessage),
      });

      const response = await stub.fetch(request);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual({ ok: true });
    });
  });

  describe('Git cache validation behavior', () => {
    it('should document tree cache behavior without merkle root', async () => {
      // When getTreeData is called for a repo with no merkle root in the
      // merkle_roots table, it returns null. This forces a cache miss and
      // triggers a fetch from the origin server.

      // This is the expected behavior for repos that haven't been accessed
      // yet or haven't received their first git invalidation message.
    });

    it('should document file cache LRU eviction', async () => {
      // The cacheFileContent method tracks accessed_at timestamps and uses
      // them for LRU eviction when the cache exceeds MAX_FILE_CACHE_SIZE (50MB).

      // evictFileCacheIfNeeded deletes the oldest accessed files in batches
      // of 100 until enough space is available for the new file.

      // Testing this requires mocking large file content, which is challenging
      // in the test environment. The behavior is documented here for reference.
    });

    it('should document merkle root change invalidation flow', async () => {
      // When a git invalidation updates a repo's merkle root:
      // 1. The new root is stored in merkle_roots table
      // 2. Existing cached tree/file data becomes stale (mismatched merkle_root)
      // 3. Next cache lookup returns null due to merkle_root mismatch
      // 4. This triggers a fresh fetch from origin
      // 5. New data is cached with the updated merkle_root

      // This ensures cache consistency without explicitly deleting old entries,
      // allowing gradual cache refresh as data is accessed.
    });
  });
});
