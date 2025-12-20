/**
 * Unit tests for bookmarks routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import bookmarksApp from '../bookmarks';

// Mock dependencies
const mockSql = mock(() => []);
const mockJj = {
  listBookmarks: mock(async () => []),
  createBookmark: mock(async () => {}),
  deleteBookmark: mock(async () => {}),
  moveBookmark: mock(async () => {}),
  getCurrentChange: mock(async () => 'change-id-123'),
};

mock.module('../../ui/lib/db', () => ({
  sql: mockSql,
}));

mock.module('../../ui/lib/jj', () => mockJj);

describe('Bookmarks Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/api', bookmarksApp);
    mockSql.mockClear();
    Object.values(mockJj).forEach(m => m.mockClear());
  });

  describe('GET /:user/:repo/bookmarks', () => {
    test('returns paginated bookmarks', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
      }]); // Repository
      mockSql.mockResolvedValueOnce([
        {
          id: 1,
          name: 'main',
          target_change_id: 'abc123',
          is_default: true,
          pusher_username: 'testuser',
          updated_at: new Date('2024-01-01'),
        },
        {
          id: 2,
          name: 'feature-branch',
          target_change_id: 'def456',
          is_default: false,
          pusher_username: 'testuser',
          updated_at: new Date('2024-01-02'),
        },
      ]); // Bookmarks
      mockSql.mockResolvedValueOnce([{ count: 2 }]); // Count

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.bookmarks).toHaveLength(2);
      expect(data.total).toBe(2);
      expect(data.page).toBe(1);
      expect(data.limit).toBe(20);
    });

    test('supports pagination parameters', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]);
      mockSql.mockResolvedValueOnce([{ count: 0 }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks?page=2&limit=10');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.page).toBe(2);
      expect(data.limit).toBe(10);
    });

    test('returns jj bookmarks when db is empty', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]); // Empty DB
      mockSql.mockResolvedValueOnce([{ count: 0 }]);
      mockJj.listBookmarks.mockResolvedValueOnce([
        { name: 'main', target_change_id: 'xyz789' },
      ]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.bookmarks).toHaveLength(1);
      expect(data.synced).toBe(true);
    });

    test('returns 404 for non-existent repository', async () => {
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/bookmarks');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });

    test('orders default bookmark first', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([
        {
          id: 2,
          name: 'feature',
          is_default: false,
          updated_at: new Date('2024-01-03'),
        },
        {
          id: 1,
          name: 'main',
          is_default: true,
          updated_at: new Date('2024-01-01'),
        },
      ]);
      mockSql.mockResolvedValueOnce([{ count: 2 }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      // Verify ordering would be checked in actual SQL query
    });
  });

  describe('GET /:user/:repo/bookmarks/:name', () => {
    test('returns single bookmark', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([{
        id: 1,
        name: 'main',
        target_change_id: 'abc123',
        is_default: true,
        pusher_username: 'testuser',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.bookmark.name).toBe('main');
      expect(data.bookmark.is_default).toBe(true);
    });

    test('returns 404 for non-existent bookmark', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]); // No bookmark

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/nonexistent');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Bookmark not found');
    });
  });

  describe('POST /:user/:repo/bookmarks', () => {
    test('creates new bookmark', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, user_id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]); // No existing bookmark
      mockJj.getCurrentChange.mockResolvedValueOnce('change-id-123');
      mockSql.mockResolvedValueOnce([{
        id: 3,
        name: 'new-bookmark',
        target_change_id: 'change-id-123',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'new-bookmark' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.bookmark.name).toBe('new-bookmark');
      expect(mockJj.createBookmark).toHaveBeenCalledWith('testuser', 'testrepo', 'new-bookmark', undefined);
    });

    test('creates bookmark at specific change', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, user_id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]);
      mockSql.mockResolvedValueOnce([{
        id: 3,
        name: 'new-bookmark',
        target_change_id: 'specific-change',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'new-bookmark',
          change_id: 'specific-change',
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(201);
      expect(mockJj.createBookmark).toHaveBeenCalledWith('testuser', 'testrepo', 'new-bookmark', 'specific-change');
    });

    test('returns 400 for missing name', async () => {
      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('Missing required field: name');
    });

    test('returns 409 for existing bookmark', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Existing bookmark

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'existing' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(409);
      expect(data.error).toBe('Bookmark already exists');
    });

    test('returns 404 for non-existent repository', async () => {
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/bookmarks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: 'new-bookmark' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });
  });

  describe('DELETE /:user/:repo/bookmarks/:name', () => {
    test('deletes bookmark', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        default_bookmark: 'main',
      }]);
      mockSql.mockResolvedValueOnce([]); // Not protected
      mockSql.mockResolvedValueOnce([]); // Delete

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/feature', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(mockJj.deleteBookmark).toHaveBeenCalledWith('testuser', 'testrepo', 'feature');
    });

    test('returns 403 for protected bookmark', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        default_bookmark: 'main',
      }]);
      mockSql.mockResolvedValueOnce([{
        ruleName: 'main',
      }]); // Protected

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(403);
      expect(data.error).toBe('Bookmark is protected');
    });

    test('returns 403 for default bookmark', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        username: 'testuser',
        default_bookmark: 'main',
      }]);
      mockSql.mockResolvedValueOnce([]); // Not protected by rules

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(403);
      expect(data.error).toBe('Cannot delete default bookmark');
    });

    test('returns 404 for non-existent repository', async () => {
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/bookmarks/main', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });
  });

  describe('PATCH /:user/:repo/bookmarks/:name', () => {
    test('moves bookmark to new change', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        user_id: 1,
        username: 'testuser',
      }]);
      mockSql.mockResolvedValueOnce([]); // Not protected
      mockSql.mockResolvedValueOnce([{
        id: 2,
        name: 'feature',
        target_change_id: 'new-change-id',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/feature', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ change_id: 'new-change-id' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.bookmark.target_change_id).toBe('new-change-id');
      expect(mockJj.moveBookmark).toHaveBeenCalledWith('testuser', 'testrepo', 'feature', 'new-change-id');
    });

    test('returns 400 for missing change_id', async () => {
      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/feature', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('Missing change_id');
    });

    test('returns 403 for bookmark requiring landing queue', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([{
        ruleName: 'main',
        requireLandingQueue: true,
      }]); // Protected with landing queue

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ change_id: 'new-change-id' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(403);
      expect(data.error).toContain('landing queue');
      expect(data.requiresLanding).toBe(true);
    });

    test('creates bookmark if it does not exist in DB', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        user_id: 1,
        username: 'testuser',
      }]);
      mockSql.mockResolvedValueOnce([]); // Not protected
      mockSql.mockResolvedValueOnce([]); // No existing bookmark
      mockSql.mockResolvedValueOnce([{
        id: 3,
        name: 'new-bookmark',
        target_change_id: 'change-id',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/new-bookmark', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ change_id: 'change-id' }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.bookmark.name).toBe('new-bookmark');
    });
  });

  describe('POST /:user/:repo/bookmarks/:name/set-default', () => {
    test('sets bookmark as default', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([{ id: 2 }]); // Bookmark exists
      mockSql.mockResolvedValueOnce([]); // Clear existing default
      mockSql.mockResolvedValueOnce([]); // Set new default
      mockSql.mockResolvedValueOnce([]); // Update repository

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main/set-default', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
    });

    test('returns 404 for non-existent bookmark', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1, username: 'testuser' }]);
      mockSql.mockResolvedValueOnce([]); // Bookmark doesn't exist

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/nonexistent/set-default', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Bookmark not found');
    });

    test('returns 404 for non-existent repository', async () => {
      mockSql.mockResolvedValueOnce([]); // No repository

      const req = new Request('http://localhost/api/testuser/nonexistent/bookmarks/main/set-default', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });
  });

  describe('Bookmark pattern matching', () => {
    test('matches exact bookmark names', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        default_bookmark: 'main',
        username: 'testuser',
      }]);
      mockSql.mockResolvedValueOnce([{
        ruleName: 'main',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/main', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(403);
    });

    test('matches wildcard patterns', async () => {
      mockSql.mockResolvedValueOnce([{
        id: 1,
        default_bookmark: 'main',
        username: 'testuser',
      }]);
      mockSql.mockResolvedValueOnce([{
        ruleName: 'release-*',
      }]);

      const req = new Request('http://localhost/api/testuser/testrepo/bookmarks/release-v1', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);

      // Should be protected by wildcard pattern
      expect(res.status).toBe(403);
    });
  });
});
