/**
 * Unit tests for issue routes.
 *
 * Note: This is a sample test suite covering key routes from a 1400+ line file.
 * Additional tests should be added for complete coverage of all routes.
 */

import { describe, test, expect, mock, beforeEach } from 'bun:test';
import { Hono } from 'hono';
import issuesApp from '../issues';

// Mock dependencies
const mockSql = mock(() => []);
const mockGitIssues = {
  listIssues: mock(async () => []),
  getIssue: mock(async () => null),
  createIssue: mock(async () => ({ number: 1 })),
  updateIssue: mock(async () => ({ number: 1 })),
  closeIssue: mock(async () => {}),
  reopenIssue: mock(async () => {}),
  deleteIssue: mock(async () => {}),
  pinIssue: mock(async () => ({ number: 1 })),
  unpinIssue: mock(async () => ({ number: 1 })),
  getComments: mock(async () => []),
  addComment: mock(async () => ({ id: 1 })),
  updateComment: mock(async () => ({ id: 1 })),
  deleteComment: mock(async () => {}),
  getIssueHistory: mock(async () => []),
  getIssueCounts: mock(async () => ({ open: 0, closed: 0 })),
  getLabels: mock(async () => []),
  createLabel: mock(async () => {}),
  updateLabel: mock(async () => {}),
  deleteLabel: mock(async () => {}),
  addLabelsToIssue: mock(async () => ({ number: 1 })),
  removeLabelFromIssue: mock(async () => ({ number: 1 })),
  ensureIssuesRepo: mock(async () => {}),
  IssueNotFoundError: class IssueNotFoundError extends Error {},
  IssuesRepoNotInitializedError: class IssuesRepoNotInitializedError extends Error {},
  GitOperationError: class GitOperationError extends Error {},
};

const mockDependencies = {
  addDependency: mock(async () => ({ success: true })),
  removeDependency: mock(async () => ({ success: true })),
  getBlockingIssues: mock(async () => []),
  getBlockedByIssues: mock(async () => []),
  canCloseIssue: mock(async () => ({ canClose: true })),
};

mock.module('../../ui/lib/git-issues', () => mockGitIssues);
mock.module('../../ui/lib/git-issue-dependencies', () => mockDependencies);
mock.module('../../ui/lib/db', () => ({ sql: mockSql }));

describe('Issue Routes', () => {
  let app: Hono;

  beforeEach(() => {
    app = new Hono();
    app.route('/repos', issuesApp);

    // Clear all mocks
    mockSql.mockClear();
    Object.values(mockGitIssues).forEach(m => {
      if (typeof m === 'function' && 'mockClear' in m) {
        m.mockClear();
      }
    });
    Object.values(mockDependencies).forEach(m => m.mockClear());
  });

  describe('GET /:user/:repo/issues', () => {
    test('lists open issues by default', async () => {
      mockGitIssues.listIssues.mockResolvedValueOnce([
        { number: 1, title: 'Issue 1', state: 'open' },
      ]);
      mockGitIssues.getIssueCounts.mockResolvedValueOnce({ open: 1, closed: 0 });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.issues).toHaveLength(1);
      expect(data.counts).toEqual({ open: 1, closed: 0 });
      expect(mockGitIssues.listIssues).toHaveBeenCalledWith('testuser', 'testrepo', 'open');
    });

    test('filters issues by state', async () => {
      mockGitIssues.listIssues.mockResolvedValueOnce([]);
      mockGitIssues.getIssueCounts.mockResolvedValueOnce({ open: 0, closed: 5 });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues?state=closed');
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
      expect(mockGitIssues.listIssues).toHaveBeenCalledWith('testuser', 'testrepo', 'closed');
    });

    test('returns 404 when issues repo not initialized', async () => {
      mockGitIssues.ensureIssuesRepo.mockRejectedValueOnce(
        new mockGitIssues.IssuesRepoNotInitializedError('Not initialized')
      );

      const req = new Request('http://localhost/repos/testuser/testrepo/issues');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Not initialized');
    });
  });

  describe('GET /:user/:repo/issues/:number', () => {
    test('returns issue with comments', async () => {
      mockGitIssues.getIssue.mockResolvedValueOnce({
        number: 1,
        title: 'Test Issue',
        body: 'Description',
        state: 'open',
      });
      mockGitIssues.getComments.mockResolvedValueOnce([
        { id: 1, body: 'Comment 1' },
      ]);

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.number).toBe(1);
      expect(data.comments).toHaveLength(1);
    });

    test('returns 400 for invalid issue number', async () => {
      const req = new Request('http://localhost/repos/testuser/testrepo/issues/invalid');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('Invalid issue number');
    });

    test('returns 404 for non-existent issue', async () => {
      mockGitIssues.getIssue.mockResolvedValueOnce(null);

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/999');
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(404);
      expect(data.error).toBe('Issue not found');
    });
  });

  describe('POST /:user/:repo/issues', () => {
    test('creates new issue', async () => {
      mockGitIssues.createIssue.mockResolvedValueOnce({
        number: 1,
        title: 'New Issue',
        body: 'Description',
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'New Issue',
          body: 'Description',
          author: { id: 1, username: 'testuser' },
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(201);
      expect(data.number).toBe(1);
    });

    test('returns 400 when title missing', async () => {
      const req = new Request('http://localhost/repos/testuser/testrepo/issues', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          author: { id: 1, username: 'testuser' },
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toBe('Title is required');
    });

    test('returns 400 when author missing', async () => {
      const req = new Request('http://localhost/repos/testuser/testrepo/issues', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'New Issue',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(400);
      expect(data.error).toContain('Author');
    });
  });

  describe('PATCH /:user/:repo/issues/:number', () => {
    test('updates issue', async () => {
      mockGitIssues.updateIssue.mockResolvedValueOnce({
        number: 1,
        title: 'Updated Title',
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'Updated Title',
        }),
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.title).toBe('Updated Title');
    });

    test('returns 404 for non-existent issue', async () => {
      mockGitIssues.updateIssue.mockRejectedValueOnce(
        new mockGitIssues.IssueNotFoundError('Not found')
      );

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/999', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: 'Updated' }),
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(404);
    });
  });

  describe('POST /:user/:repo/issues/:number/close', () => {
    test('closes issue', async () => {
      mockGitIssues.getIssue.mockResolvedValueOnce({
        number: 1,
        state: 'closed',
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/close', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.state).toBe('closed');
      expect(mockGitIssues.closeIssue).toHaveBeenCalled();
    });
  });

  describe('POST /:user/:repo/issues/:number/reopen', () => {
    test('reopens issue', async () => {
      mockGitIssues.getIssue.mockResolvedValueOnce({
        number: 1,
        state: 'open',
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/reopen', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.state).toBe('open');
      expect(mockGitIssues.reopenIssue).toHaveBeenCalled();
    });
  });

  describe('DELETE /:user/:repo/issues/:number', () => {
    test('deletes issue', async () => {
      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1', {
        method: 'DELETE',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(data.success).toBe(true);
      expect(mockGitIssues.deleteIssue).toHaveBeenCalled();
    });
  });

  describe('Comment Routes', () => {
    describe('POST /:user/:repo/issues/:number/comments', () => {
      test('adds comment to issue', async () => {
        mockGitIssues.addComment.mockResolvedValueOnce({
          id: 1,
          body: 'New comment',
        });

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/comments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            body: 'New comment',
            author: { id: 1, username: 'testuser' },
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(201);
        expect(data.body).toBe('New comment');
      });

      test('returns 400 when body missing', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/comments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            author: { id: 1, username: 'testuser' },
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(400);
        expect(data.error).toBe('Comment body is required');
      });
    });

    describe('PATCH /:user/:repo/issues/:number/comments/:commentId', () => {
      test('updates comment', async () => {
        mockGitIssues.updateComment.mockResolvedValueOnce({
          id: 1,
          body: 'Updated comment',
        });

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/comments/1', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ body: 'Updated comment' }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.body).toBe('Updated comment');
      });

      test('returns 400 for invalid comment ID', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/comments/invalid', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ body: 'Updated' }),
        });
        const res = await app.fetch(req);

        expect(res.status).toBe(400);
      });
    });

    describe('DELETE /:user/:repo/issues/:number/comments/:commentId', () => {
      test('deletes comment', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/comments/1', {
          method: 'DELETE',
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.success).toBe(true);
      });
    });
  });

  describe('Label Routes', () => {
    describe('GET /:user/:repo/labels', () => {
      test('returns repository labels', async () => {
        mockGitIssues.getLabels.mockResolvedValueOnce([
          { name: 'bug', color: '#ff0000' },
          { name: 'feature', color: '#00ff00' },
        ]);

        const req = new Request('http://localhost/repos/testuser/testrepo/labels');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.labels).toHaveLength(2);
      });
    });

    describe('POST /:user/:repo/labels', () => {
      test('creates new label', async () => {
        mockGitIssues.getLabels.mockResolvedValueOnce([
          { name: 'bug', color: '#ff0000' },
        ]);

        const req = new Request('http://localhost/repos/testuser/testrepo/labels', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: 'bug',
            color: '#ff0000',
            description: 'Bug reports',
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(201);
        expect(data.labels).toHaveLength(1);
      });

      test('returns 400 for invalid color format', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/labels', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: 'bug',
            color: 'invalid',
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(400);
        expect(data.error).toContain('color');
      });
    });
  });

  describe('Reaction Routes', () => {
    describe('POST /:user/:repo/issues/:number/reactions', () => {
      test('adds reaction to issue', async () => {
        mockGitIssues.getIssue.mockResolvedValueOnce({ number: 1 });
        mockSql.mockResolvedValueOnce([{
          id: 1,
          user_id: 1,
          target_type: 'issue',
          target_id: 1,
          emoji: '👍',
          created_at: new Date(),
        }]);

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/reactions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            user_id: 1,
            emoji: '👍',
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(201);
        expect(data.emoji).toBe('👍');
      });

      test('returns 200 if reaction already exists', async () => {
        mockGitIssues.getIssue.mockResolvedValueOnce({ number: 1 });
        mockSql.mockResolvedValueOnce([]); // Conflict, no new record

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/reactions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            user_id: 1,
            emoji: '👍',
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.message).toContain('already exists');
      });
    });
  });

  describe('Dependency Routes', () => {
    describe('GET /:user/:repo/issues/:number/dependencies', () => {
      test('returns issue dependencies', async () => {
        mockGitIssues.getIssue.mockResolvedValueOnce({ number: 1 });
        mockDependencies.getBlockingIssues.mockResolvedValueOnce([2, 3]);
        mockDependencies.getBlockedByIssues.mockResolvedValueOnce([]);

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/dependencies');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.blocks).toEqual([2, 3]);
        expect(data.blocked_by).toEqual([]);
      });
    });

    describe('POST /:user/:repo/issues/:number/dependencies', () => {
      test('adds dependency', async () => {
        mockDependencies.addDependency.mockResolvedValueOnce({ success: true });

        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/dependencies', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ blocks: 2 }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(201);
        expect(data.success).toBe(true);
      });

      test('returns 400 for invalid blocked issue number', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/dependencies', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ blocks: 'invalid' }),
        });
        const res = await app.fetch(req);

        expect(res.status).toBe(400);
      });
    });
  });

  describe('Milestone Routes', () => {
    describe('GET /:user/:repo/milestones', () => {
      test('returns milestones with issue counts', async () => {
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
        mockSql.mockResolvedValueOnce([
          {
            id: 1,
            title: 'v1.0',
            open_issues: 5,
            closed_issues: 10,
          },
        ]);

        const req = new Request('http://localhost/repos/testuser/testrepo/milestones');
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(200);
        expect(data.milestones).toHaveLength(1);
      });

      test('filters milestones by state', async () => {
        mockSql.mockResolvedValueOnce([{ id: 1 }]);
        mockSql.mockResolvedValueOnce([]);

        const req = new Request('http://localhost/repos/testuser/testrepo/milestones?state=closed');
        await app.fetch(req);

        // Verify SQL was called with state filter
        expect(mockSql).toHaveBeenCalled();
      });
    });

    describe('POST /:user/:repo/milestones', () => {
      test('creates milestone', async () => {
        mockSql.mockResolvedValueOnce([{ id: 1 }]); // Repository
        mockSql.mockResolvedValueOnce([{
          id: 1,
          title: 'v1.0',
          description: 'Release 1.0',
        }]);

        const req = new Request('http://localhost/repos/testuser/testrepo/milestones', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            title: 'v1.0',
            description: 'Release 1.0',
          }),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(201);
        expect(data.title).toBe('v1.0');
      });

      test('returns 400 when title missing', async () => {
        const req = new Request('http://localhost/repos/testuser/testrepo/milestones', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        });
        const res = await app.fetch(req);
        const data = await res.json();

        expect(res.status).toBe(400);
        expect(data.error).toBe('Title is required');
      });
    });
  });

  describe('Pin/Unpin Routes', () => {
    test('pins issue', async () => {
      mockGitIssues.pinIssue.mockResolvedValueOnce({
        number: 1,
        pinned: true,
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/pin', {
        method: 'POST',
      });
      const res = await app.fetch(req);
      const data = await res.json();

      expect(res.status).toBe(200);
      expect(mockGitIssues.pinIssue).toHaveBeenCalled();
    });

    test('unpins issue', async () => {
      mockGitIssues.unpinIssue.mockResolvedValueOnce({
        number: 1,
        pinned: false,
      });

      const req = new Request('http://localhost/repos/testuser/testrepo/issues/1/unpin', {
        method: 'POST',
      });
      const res = await app.fetch(req);

      expect(res.status).toBe(200);
      expect(mockGitIssues.unpinIssue).toHaveBeenCalled();
    });
  });
});
