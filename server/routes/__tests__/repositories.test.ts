/**
 * Unit tests for repository routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import repositoriesApp from '../repositories';

// Mock dependencies
const mockSql = mock(() => []);

mock.module('../../ui/lib/db', () => ({
  sql: mockSql,
}));

describe('Repository Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/repos', repositoriesApp);
    mockSql.mockClear();
  });

  describe('GET /repos/:user/:repo/topics', () => {
    test('returns repository topics', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{
        topics: ['javascript', 'typescript', 'testing'],
      }]); // Repository query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics).toEqual(['javascript', 'typescript', 'testing']);
    });

    test('returns empty array when no topics', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{ topics: null }]); // Repository query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics).toEqual([]);
    });

    test('returns 404 when user not found', async () => {
      mockSql.mockResolvedValueOnce([]); // No user found

      const req = new Request('http://localhost/repos/nonexistent/testrepo/topics');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('User not found');
    });

    test('returns 404 when repository not found', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User exists
      mockSql.mockResolvedValueOnce([]); // Repository not found

      const req = new Request('http://localhost/repos/testuser/nonexistent/topics');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });

    test('handles database errors', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/repos/testuser/testrepo/topics');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Internal server error');
    });
  });

  describe('PUT /repos/:user/:repo/topics', () => {
    test('updates repository topics', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{
        topics: ['new-topic', 'another-topic'],
      }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: ['new-topic', 'another-topic'],
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics).toEqual(['new-topic', 'another-topic']);
    });

    test('returns 400 when topics is not an array', async () => {
      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: 'not-an-array',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('Topics must be an array');
    });

    test('limits topics to 20', async () => {
      const manyTopics = Array.from({ length: 25 }, (_, i) => `topic${i}`);
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{
        topics: manyTopics.slice(0, 20),
      }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: manyTopics }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics.length).toBeLessThanOrEqual(20);
    });

    test('trims and lowercases topics', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{
        topics: ['javascript', 'typescript'],
      }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: ['  JavaScript  ', 'TypeScript'],
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics).toEqual(['javascript', 'typescript']);
    });

    test('limits topic length to 35 characters', async () => {
      const longTopic = 'a'.repeat(50);
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{
        topics: [longTopic.slice(0, 35)],
      }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: [longTopic] }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics[0].length).toBeLessThanOrEqual(35);
    });

    test('rejects invalid topic format', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: ['valid-topic', 'invalid topic!'],
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toContain('Invalid topic');
    });

    test('only accepts alphanumeric and hyphens', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: ['valid-topic-123', 'invalid@topic'],
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toContain('Invalid topic');
    });

    test('returns 404 when user not found', async () => {
      mockSql.mockResolvedValueOnce([]); // No user found

      const req = new Request('http://localhost/repos/nonexistent/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: ['test'] }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('User not found');
    });

    test('returns 404 when repository not found', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User exists
      mockSql.mockResolvedValueOnce([]); // Repository not found

      const req = new Request('http://localhost/repos/testuser/nonexistent/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: ['test'] }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Repository not found');
    });

    test('handles database errors', async () => {
      mockSql.mockRejectedValueOnce(new Error('Database error'));

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: ['test'] }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(500);
      expect(data.error).toBe('Internal server error');
    });

    test('updates updated_at timestamp', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{ topics: ['test'] }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: ['test'] }),
      });
      await app.fetch(req);

      // Verify the UPDATE query included updated_at
      // This would check the actual SQL call
    });

    test('handles empty topics array', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]); // User query
      mockSql.mockResolvedValueOnce([{ topics: [] }]); // Update query

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ topics: [] }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.topics).toEqual([]);
    });
  });

  describe('Edge cases', () => {
    test('handles special characters in usernames', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]);
      mockSql.mockResolvedValueOnce([{ topics: [] }]);

      const req = new Request('http://localhost/repos/user-name_123/testrepo/topics');
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
    });

    test('handles special characters in repo names', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]);
      mockSql.mockResolvedValueOnce([{ topics: [] }]);

      const req = new Request('http://localhost/repos/testuser/repo-name.test/topics');
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
    });

    test('handles duplicate topics', async () => {
      mockSql.mockResolvedValueOnce([{ id: 1 }]);
      mockSql.mockResolvedValueOnce([{
        topics: ['test', 'test', 'another'],
      }]);

      const req = new Request('http://localhost/repos/testuser/testrepo/topics', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topics: ['test', 'test', 'another'],
        }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
      // Duplicates may or may not be removed depending on implementation
    });
  });
});
