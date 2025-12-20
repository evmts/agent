/**
 * Unit tests for stars and watch routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import starsApp from '../stars';

// Mock dependencies
const mockSql = mock(() => []);
const mockGetUserBySession = mock(async () => null);

mock.module('../../ui/lib/db', () => ({
  sql: mockSql,
}));

mock.module('../../ui/lib/auth-helpers', () => ({
  getUserBySession: mockGetUserBySession,
}));

describe('Stars Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/api', starsApp);
    mockSql.mockClear();
    mockGetUserBySession.mockClear();
  });

  describe('GET /:user/:repo/stargazers', () => {
    test('returns list of stargazers', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
      mockSql.mockResolvedValueOnce([
        {
          id: 1,
          username: 'user1',
          display_name: 'User One',
          avatar_url: 'https://example.com/avatar1.jpg',
          created_at: new Date('2024-01-01'),
        },
        {
          id: 2,
          username: 'user2',
          display_name: 'User Two',
          avatar_url: null,
          created_at: new Date('2024-01-02'),
        },
      ]); // Stargazers

      const req = new Request('http://localhost/api/testuser/testrepo/stargazers');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.stargazers).toHaveLength(2);
      expect(data.total).toBe(2);
      expect(data.stargazers[0].username).toBe('user1');
    });

    test('returns empty list when no stars', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
      mockSql.mockResolvedValueOnce([]); // No stargazers

      const req = new Request('http://localhost/api/testuser/testrepo/stargazers');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.stargazers).toEqual([]);
      expect(data.total).toBe(0);
    });

    test('returns 404 for non-existent user', async () => {
      mockSql.mockResolvedValueOnce([]); // No user

      const req = new Request('http://localhost/api/nonexistent/testrepo/stargazers');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('User not found');
    });

    test('returns 404 for non-existent repository', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User exists
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/stargazers');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });

    test('handles database errors', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/api/testuser/testrepo/stargazers');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Failed to fetch stargazers');
    });
  });

  describe('POST /:user/:repo/star', () => {
    test('requires authentication', async () => {
      mockGetUserBySession.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(401);
      expect(data.error).toBe('Unauthorized');
    });

    test('stars a repository', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([]); // No existing star
      mockSql.mockResolvedValueOnce([]); // Insert star
      mockSql.mockResolvedValueOnce([{ count: 5 }]); // Star count

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.message).toBe('Repository starred');
      expect(data.starCount).toBe(5);
    });

    test('returns 200 if already starred', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // Existing star

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Already starred');
    });

    test('returns 404 for non-existent user', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([]); // No user

      const req = new Request('http://localhost/api/nonexistent/testrepo/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('User not found');
    });

    test('returns 404 for non-existent repository', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // User exists
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });

    test('handles database errors', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Failed to star repository');
    });
  });

  describe('DELETE /:user/:repo/star', () => {
    test('requires authentication', async () => {
      mockGetUserBySession.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(401);
      expect(data.error).toBe('Unauthorized');
    });

    test('unstars a repository', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([]); // Delete star
      mockSql.mockResolvedValueOnce([{ count: 4 }]); // Updated star count

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.message).toBe('Repository unstarred');
      expect(data.starCount).toBe(4);
    });

    test('handles deleting non-existent star', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([]); // Delete (no rows affected)
      mockSql.mockResolvedValueOnce([{ count: 5 }]); // Star count

      const req = new Request('http://localhost/api/testuser/testrepo/star', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
    });
  });

  describe('GET /user/starred', () => {
    test('requires authentication', async () => {
      mockGetUserBySession.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/api/user/starred');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(401);
      expect(data.error).toBe('Unauthorized');
    });

    test('returns starred repositories', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([
        {
          id: 1,
          name: 'repo1',
          username: 'owner1',
          starred_at: new Date('2024-01-01'),
          star_count: 10,
        },
        {
          id: 2,
          name: 'repo2',
          username: 'owner2',
          starred_at: new Date('2024-01-02'),
          star_count: 25,
        },
      ]);

      const req = new Request('http://localhost/api/user/starred');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.repositories).toHaveLength(2);
      expect(data.total).toBe(2);
    });

    test('returns empty list when no starred repos', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([]);

      const req = new Request('http://localhost/api/user/starred');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.repositories).toEqual([]);
      expect(data.total).toBe(0);
    });
  });

  describe('Watch Routes', () => {
    describe('GET /:user/:repo/watchers', () => {
      test('returns list of watchers', async () => {
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // User
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
        mockSql.mockResolvedValueOnce([
          {
            id: 1,
            username: 'watcher1',
            display_name: 'Watcher One',
            avatar_url: null,
            level: 'all',
            created_at: new Date('2024-01-01'),
          },
        ]);

        const req = new Request('http://localhost/api/testuser/testrepo/watchers');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.watchers).toHaveLength(1);
        expect(data.watchers[0].level).toBe('all');
      });

      test('excludes ignored watchers', async () => {
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // User
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
        mockSql.mockResolvedValueOnce([
          { id: 1, username: 'watcher1', level: 'all', created_at: new Date() },
        ]); // Only non-ignored

        const req = new Request('http://localhost/api/testuser/testrepo/watchers');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.watchers.every((w: any) => w.level !== 'ignore')).toBe(true);
      });
    });

    describe('POST /:user/:repo/watch', () => {
      test('requires authentication', async () => {
        mockGetUserBySession.mockResolvedValueOnce(null);

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: 'all' }),
        });
        const res = await app.fetch(req);

        expect(res.status).toBe(401);
      });

      test('watches repository with specified level', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([]); // Insert/update watch

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: 'releases' }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.message).toBe('Watch preferences updated');
        expect(data.level).toBe('releases');
      });

      test('defaults to "all" when level not specified', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([]); // Insert/update watch

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.level).toBe('all');
      });

      test('rejects invalid watch level', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: 'invalid' }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(400);
        expect(data.error).toBe('Invalid watch level');
      });

      test('updates existing watch preference', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([]); // Upsert watch

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: 'ignore' }),
        });
        const res = await app.fetch(req);

        expect(res.status).toBe(200);
      });
    });

    describe('DELETE /:user/:repo/watch', () => {
      test('requires authentication', async () => {
        mockGetUserBySession.mockResolvedValueOnce(null);

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'DELETE',
        });
        const res = await app.fetch(req);

        expect(res.status).toBe(401);
      });

      test('unwatches repository', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([]); // Delete watch

        const req = new Request('http://localhost/api/testuser/testrepo/watch', {
          method: 'DELETE',
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.message).toBe('Repository unwatched');
      });
    });

    describe('GET /:user/:repo/watch/status', () => {
      test('returns false when not authenticated', async () => {
        mockGetUserBySession.mockResolvedValueOnce(null);

        const req = new Request('http://localhost/api/testuser/testrepo/watch/status');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.watching).toBe(false);
        expect(data.level).toBeNull();
      });

      test('returns watch status for authenticated user', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([{ level: 'releases' }]); // Watch record

        const req = new Request('http://localhost/api/testuser/testrepo/watch/status');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.watching).toBe(true);
        expect(data.level).toBe('releases');
      });

      test('returns false when not watching', async () => {
        mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
        mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
        mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
        mockSql.mockResolvedValueOnce([]); // No watch record

        const req = new Request('http://localhost/api/testuser/testrepo/watch/status');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.watching).toBe(false);
      });
    });
  });

  describe('GET /:user/:repo/star/status', () => {
    test('returns false when not authenticated', async () => {
      mockGetUserBySession.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/api/testuser/testrepo/star/status');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.starred).toBe(false);
    });

    test('returns star status for authenticated user', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // Star record
      mockSql.mockResolvedValueOnce([{ count: 42 }]); // Star count

      const req = new Request('http://localhost/api/testuser/testrepo/star/status');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.starred).toBe(true);
      expect(data.starCount).toBe(42);
    });

    test('returns star count when not starred', async () => {
      mockGetUserBySession.mockResolvedValueOnce({ id: 1, username: 'currentuser' });
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Repo owner
      mockSql.mockResolvedValueOnce([{ id: 10 }]); // Repository
      mockSql.mockResolvedValueOnce([]); // No star record
      mockSql.mockResolvedValueOnce([{ count: 15 }]); // Star count

      const req = new Request('http://localhost/api/testuser/testrepo/star/status');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.starred).toBe(false);
      expect(data.starCount).toBe(15);
    });
  });
});
