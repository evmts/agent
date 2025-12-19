# Code Review Feature Implementation

## Overview

Implement a GitHub-style code review system for Plue's Pull Requests, allowing users to submit reviews (approve, request changes, comment), add inline comments on specific lines of code, resolve conversations, and dismiss stale reviews.

**Scope**: Full review lifecycle including pending reviews, inline code comments, review submission with multiple types, conversation resolution, and review dismissal.

**Stack**: Bun runtime, Hono API server, Astro SSR frontend, PostgreSQL database, Git CLI operations.

**Builds On**: Pull Requests feature (02_pull_requests.md) - PRs must be implemented first.

---

## 1. Database Schema Updates

### 1.1 Reviews Table (Already Exists)

The reviews table from the Pull Requests feature needs to be updated to match Gitea's full review model:

```sql
-- Update existing reviews table
ALTER TABLE reviews DROP CONSTRAINT IF EXISTS reviews_type_check;
ALTER TABLE reviews ADD CONSTRAINT reviews_type_check
  CHECK (type IN ('pending', 'comment', 'approve', 'reject'));

-- Rename 'request_changes' to 'reject' for consistency with Gitea
-- Update any existing data:
UPDATE reviews SET type = 'reject' WHERE type = 'request_changes';

-- Add missing columns if they don't exist
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS original_author VARCHAR(255);
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS original_author_id BIGINT DEFAULT 0;

-- Ensure all review columns exist
-- id, pull_request_id, reviewer_id, type, content, commit_id, official, stale, dismissed
-- created_at, updated_at, original_author, original_author_id
```

### 1.2 Review Comments Table

Update the existing review_comments table to support:
- Proper diff side tracking
- Conversation resolution
- Comment invalidation
- Reply threading

```sql
-- Update review_comments table to match Gitea's comment model
DROP TABLE IF EXISTS review_comments CASCADE;

-- Recreate with proper structure
CREATE TABLE IF NOT EXISTS review_comments (
  id SERIAL PRIMARY KEY,
  review_id INTEGER REFERENCES reviews(id) ON DELETE CASCADE,
  pull_request_id INTEGER NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  author_id INTEGER NOT NULL REFERENCES users(id),

  -- Location in code
  commit_id VARCHAR(64) NOT NULL,
  file_path TEXT NOT NULL,
  line BIGINT NOT NULL,           -- Negative for left side (old), positive for right side (new)

  -- Content
  body TEXT NOT NULL,
  patch TEXT,                      -- Diff context around the comment

  -- Status
  invalidated BOOLEAN DEFAULT false,   -- Line changed by subsequent commit
  resolve_doer_id INTEGER REFERENCES users(id), -- Who resolved this conversation

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_review_comments_review ON review_comments(review_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_pr ON review_comments(pull_request_id);
CREATE INDEX IF NOT EXISTS idx_review_comments_file ON review_comments(pull_request_id, file_path);
CREATE INDEX IF NOT EXISTS idx_review_comments_line ON review_comments(pull_request_id, file_path, line);
```

**Key Schema Notes**:
- **line field**: Negative values indicate left side (old code), positive indicates right side (new code)
- **patch field**: Stores diff context around the comment (4-5 lines before/after)
- **resolve_doer_id**: NULL means unresolved, non-NULL means resolved by that user
- **invalidated**: Set to true when the line of code changes in subsequent commits

### 1.3 Schema Migration

Update `/Users/williamcory/plue/db/schema.sql` to include these changes after the pull_requests section.

---

## 2. TypeScript Types

Update `/Users/williamcory/plue/ui/lib/types.ts`:

```typescript
// Update ReviewType to match Gitea
export type ReviewType = 'pending' | 'comment' | 'approve' | 'reject';

export interface Review {
  id: number;
  pull_request_id: number;
  reviewer_id: number;
  type: ReviewType;
  content: string | null;
  commit_id: string | null;
  official: boolean;
  stale: boolean;
  dismissed: boolean;
  original_author: string | null;
  original_author_id: number;
  created_at: Date;
  updated_at: Date;

  // Joined
  reviewer?: User;
  code_comments?: ReviewComment[];
}

export interface ReviewComment {
  id: number;
  review_id: number;
  pull_request_id: number;
  author_id: number;
  commit_id: string;
  file_path: string;
  line: number;  // Negative for left side, positive for right side
  body: string;
  patch: string | null;
  invalidated: boolean;
  resolve_doer_id: number | null;
  created_at: Date;
  updated_at: Date;

  // Joined
  author?: User;
  resolve_doer?: User;
}

export interface CreateReviewOptions {
  pull_request_id: number;
  reviewer_id: number;
  type: ReviewType;
  content?: string;
  commit_id?: string;
}

export interface CreateReviewCommentOptions {
  review_id: number;
  pull_request_id: number;
  author_id: number;
  commit_id: string;
  file_path: string;
  line: number;
  body: string;
}

// Diff side helper
export type DiffSide = 'left' | 'right';

export interface CodeComment {
  path: string;
  line: number;
  side: DiffSide;
  comments: ReviewComment[];
  resolved: boolean;
}
```

---

## 3. API Routes

Extend `/Users/williamcory/plue/server/routes/pulls.ts` with review endpoints:

```typescript
/**
 * Review endpoints - Creating reviews, submitting, adding inline comments,
 * resolving conversations, dismissing reviews
 */

// Get current pending review for a user
app.get('/:user/:repo/pulls/:number/reviews/pending', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();
  const reviewer_id = parseInt(c.req.query('reviewer_id') || '0', 10);

  if (!reviewer_id) {
    return c.json({ error: 'reviewer_id required' }, 400);
  }

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  // Get pending review for this reviewer
  const [review] = await sql`
    SELECT * FROM reviews
    WHERE pull_request_id = ${pr.id}
      AND reviewer_id = ${reviewer_id}
      AND type = 'pending'
    ORDER BY created_at DESC
    LIMIT 1
  ` as Review[];

  return c.json({ review: review || null });
});

// Create or get pending review
app.post('/:user/:repo/pulls/:number/reviews/start', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();
  const body = await c.req.json();
  const { reviewer_id, commit_id } = body;

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  // Check for existing pending review
  let [review] = await sql`
    SELECT * FROM reviews
    WHERE pull_request_id = ${pr.id}
      AND reviewer_id = ${reviewer_id}
      AND type = 'pending'
  ` as Review[];

  // Create if doesn't exist
  if (!review) {
    [review] = await sql`
      INSERT INTO reviews (
        pull_request_id, reviewer_id, type, commit_id, official
      ) VALUES (
        ${pr.id}, ${reviewer_id}, 'pending', ${commit_id || null}, false
      )
      RETURNING *
    ` as Review[];
  }

  return c.json({ review }, 201);
});

// Add inline comment to pending review
app.post('/:user/:repo/pulls/:number/reviews/:reviewId/comments', async (c) => {
  const { user: username, repo: reponame, number, reviewId } = c.req.param();
  const body = await c.req.json();
  const { author_id, commit_id, file_path, line, body: commentBody, patch } = body;

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  const [review] = await sql`
    SELECT * FROM reviews WHERE id = ${parseInt(reviewId, 10)}
  ` as Review[];
  if (!review) return c.json({ error: 'Review not found' }, 404);

  // Create the comment
  const [comment] = await sql`
    INSERT INTO review_comments (
      review_id, pull_request_id, author_id, commit_id, file_path, line, body, patch
    ) VALUES (
      ${review.id}, ${pr.id}, ${author_id}, ${commit_id}, ${file_path}, ${line}, ${commentBody}, ${patch || null}
    )
    RETURNING *
  ` as ReviewComment[];

  return c.json({ comment }, 201);
});

// Submit a review (converts pending to final type)
app.post('/:user/:repo/pulls/:number/reviews/:reviewId/submit', async (c) => {
  const { user: username, repo: reponame, number, reviewId } = c.req.param();
  const body = await c.req.json();
  const { type, content } = body as { type: ReviewType; content?: string };

  if (!['comment', 'approve', 'reject'].includes(type)) {
    return c.json({ error: 'Invalid review type' }, 400);
  }

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*, i.state, i.issue_number
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as any[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  // Cannot submit review on closed/merged PR
  if (pr.state === 'closed' || pr.has_merged) {
    return c.json({ error: 'Cannot submit review on closed/merged PR' }, 400);
  }

  const [review] = await sql`
    SELECT * FROM reviews WHERE id = ${parseInt(reviewId, 10)}
  ` as Review[];
  if (!review) return c.json({ error: 'Review not found' }, 404);

  // Get code comments count
  const [{ count: commentCount }] = await sql`
    SELECT COUNT(*) as count
    FROM review_comments
    WHERE review_id = ${review.id}
  `;

  // Validate: approve/reject without content requires at least one code comment
  if (type !== 'comment' && !content && commentCount === 0) {
    return c.json({ error: 'Review must have content or code comments' }, 400);
  }

  // If approve/reject, dismiss previous approvals/rejections from same reviewer
  if (type === 'approve' || type === 'reject') {
    await sql`
      UPDATE reviews
      SET dismissed = true
      WHERE pull_request_id = ${pr.id}
        AND reviewer_id = ${review.reviewer_id}
        AND type IN ('approve', 'reject')
        AND id != ${review.id}
    `;
  }

  // Update review
  const [updatedReview] = await sql`
    UPDATE reviews
    SET type = ${type}, content = ${content || null}, updated_at = NOW()
    WHERE id = ${review.id}
    RETURNING *
  ` as Review[];

  return c.json({ review: updatedReview });
});

// Get all reviews for a PR (with code comments)
app.get('/:user/:repo/pulls/:number/reviews', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  // Get all reviews except pending ones
  const reviews = await sql`
    SELECT r.*, u.username as reviewer_username
    FROM reviews r
    JOIN users u ON r.reviewer_id = u.id
    WHERE r.pull_request_id = ${pr.id}
      AND r.type != 'pending'
    ORDER BY r.created_at DESC
  ` as Review[];

  // Load code comments for each review
  for (const review of reviews) {
    const comments = await sql`
      SELECT rc.*, u.username as author_username
      FROM review_comments rc
      JOIN users u ON rc.author_id = u.id
      WHERE rc.review_id = ${review.id}
      ORDER BY rc.file_path, rc.line, rc.created_at
    ` as ReviewComment[];
    review.code_comments = comments;
  }

  return c.json({ reviews });
});

// Get code comments for a specific file in a PR
app.get('/:user/:repo/pulls/:number/comments/:path(*)', async (c) => {
  const { user: username, repo: reponame, number, path } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  const comments = await sql`
    SELECT rc.*, u.username as author_username, rd.username as resolve_doer_username
    FROM review_comments rc
    JOIN users u ON rc.author_id = u.id
    LEFT JOIN users rd ON rc.resolve_doer_id = rd.id
    WHERE rc.pull_request_id = ${pr.id}
      AND rc.file_path = ${path}
      AND rc.invalidated = false
    ORDER BY rc.line, rc.created_at
  ` as ReviewComment[];

  return c.json({ comments });
});

// Resolve/unresolve a conversation
app.post('/:user/:repo/pulls/:number/comments/:commentId/resolve', async (c) => {
  const { user: username, repo: reponame, number, commentId } = c.req.param();
  const body = await c.req.json();
  const { resolver_id, resolve } = body as { resolver_id: number; resolve: boolean };

  const [comment] = await sql`
    SELECT rc.*, pr.issue_id
    FROM review_comments rc
    JOIN pull_requests pr ON rc.pull_request_id = pr.id
    WHERE rc.id = ${parseInt(commentId, 10)}
  ` as any[];
  if (!comment) return c.json({ error: 'Comment not found' }, 404);

  // Check permissions (PR author, comment author, or maintainer can resolve)
  // For simplicity, allowing anyone to resolve for now

  const resolveDoerId = resolve ? resolver_id : null;

  await sql`
    UPDATE review_comments
    SET resolve_doer_id = ${resolveDoerId}
    WHERE id = ${comment.id}
  `;

  return c.json({ success: true, resolved: resolve });
});

// Dismiss a review
app.post('/:user/:repo/pulls/:number/reviews/:reviewId/dismiss', async (c) => {
  const { user: username, repo: reponame, number, reviewId } = c.req.param();
  const body = await c.req.json();
  const { message, dismiss } = body as { message?: string; dismiss: boolean };

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [review] = await sql`
    SELECT r.*, pr.has_merged, i.state
    FROM reviews r
    JOIN pull_requests pr ON r.pull_request_id = pr.id
    JOIN issues i ON pr.issue_id = i.id
    WHERE r.id = ${parseInt(reviewId, 10)}
  ` as any[];

  if (!review) return c.json({ error: 'Review not found' }, 404);

  // Cannot dismiss on closed/merged PR
  if (review.state === 'closed' || review.has_merged) {
    return c.json({ error: 'Cannot dismiss review on closed/merged PR' }, 400);
  }

  // Only approve/reject reviews can be dismissed
  if (review.type !== 'approve' && review.type !== 'reject') {
    return c.json({ error: 'Can only dismiss approve/reject reviews' }, 400);
  }

  await sql`
    UPDATE reviews
    SET dismissed = ${dismiss}
    WHERE id = ${review.id}
  `;

  return c.json({ success: true, dismissed: dismiss });
});

// Mark reviews as stale when new commits are pushed
app.post('/:user/:repo/pulls/:number/reviews/mark-stale', async (c) => {
  const { user: username, repo: reponame, number } = c.req.param();

  const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
  if (!user) return c.json({ error: 'User not found' }, 404);

  const [repo] = await sql`
    SELECT * FROM repositories
    WHERE user_id = ${user.id} AND name = ${reponame}
  ` as Repository[];
  if (!repo) return c.json({ error: 'Repository not found' }, 404);

  const [pr] = await sql`
    SELECT pr.*
    FROM pull_requests pr
    JOIN issues i ON pr.issue_id = i.id
    WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number, 10)}
  ` as PullRequest[];
  if (!pr) return c.json({ error: 'Pull request not found' }, 404);

  // Mark all non-pending reviews as stale
  await sql`
    UPDATE reviews
    SET stale = true
    WHERE pull_request_id = ${pr.id}
      AND type != 'pending'
  `;

  return c.json({ success: true });
});
```

Register these routes in the existing pulls.ts file or ensure they're properly routed in `/Users/williamcory/plue/server/index.ts`.

---

## 4. UI Components

### 4.1 Review Form Component

Create `/Users/williamcory/plue/ui/components/ReviewForm.astro`:

```astro
---
interface Props {
  prNumber: number;
  username: string;
  reponame: string;
  reviewerId: number;
  currentReview?: any;
}

const { prNumber, username, reponame, reviewerId, currentReview } = Astro.props;
---

<div class="review-form" id="review-form">
  <h3>Submit Review</h3>

  <form id="submit-review-form">
    <input type="hidden" name="reviewer_id" value={reviewerId} />

    <div class="form-group">
      <label for="review-content">Review Summary (optional)</label>
      <textarea
        id="review-content"
        name="content"
        rows="4"
        placeholder="Leave a comment about this pull request..."
      ></textarea>
    </div>

    <div class="review-type-group">
      <label>
        <input type="radio" name="type" value="comment" checked />
        <strong>Comment</strong> - Submit general feedback without explicit approval
      </label>
      <label>
        <input type="radio" name="type" value="approve" />
        <strong>Approve</strong> - Submit feedback and approve merging these changes
      </label>
      <label>
        <input type="radio" name="type" value="reject" />
        <strong>Request Changes</strong> - Submit feedback that must be addressed before merging
      </label>
    </div>

    {currentReview && (
      <div class="pending-comments">
        <p><strong>{currentReview.comment_count || 0}</strong> pending code comments</p>
      </div>
    )}

    <div class="form-actions">
      <button type="submit" class="btn btn-primary">Submit Review</button>
      <button type="button" class="btn" id="cancel-review">Cancel</button>
    </div>
  </form>
</div>

<script>
  const form = document.getElementById('submit-review-form') as HTMLFormElement;
  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(form);
    const type = formData.get('type') as string;
    const content = formData.get('content') as string;

    // Get or create pending review
    const reviewRes = await fetch(window.location.href + '/reviews/pending?reviewer_id=' + formData.get('reviewer_id'));
    const { review } = await reviewRes.json();

    if (!review) {
      alert('No pending review found');
      return;
    }

    // Submit the review
    const submitRes = await fetch(`${window.location.href}/reviews/${review.id}/submit`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, content })
    });

    if (submitRes.ok) {
      window.location.reload();
    } else {
      const error = await submitRes.json();
      alert(error.error || 'Failed to submit review');
    }
  });

  document.getElementById('cancel-review')?.addEventListener('click', () => {
    document.getElementById('review-form')?.remove();
  });
</script>

<style>
  .review-form {
    border: 1px solid black;
    padding: 1rem;
    margin: 2rem 0;
  }

  .form-group {
    margin-bottom: 1rem;
  }

  .form-group label {
    display: block;
    font-weight: bold;
    margin-bottom: 0.5rem;
  }

  .form-group textarea {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid black;
    font-family: inherit;
  }

  .review-type-group {
    margin: 1.5rem 0;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .review-type-group label {
    padding: 0.75rem;
    border: 1px solid black;
    cursor: pointer;
  }

  .review-type-group label:hover {
    background: #f5f5f5;
  }

  .pending-comments {
    margin: 1rem 0;
    padding: 0.75rem;
    background: #fff3cd;
    border: 1px solid black;
  }

  .form-actions {
    display: flex;
    gap: 0.5rem;
  }
</style>
```

### 4.2 Inline Comment Component

Create `/Users/williamcory/plue/ui/components/InlineComment.astro`:

```astro
---
interface Props {
  comment: any;
  canResolve: boolean;
  resolved: boolean;
  resolverId?: number;
}

const { comment, canResolve, resolved, resolverId } = Astro.props;
---

<div class="inline-comment" data-comment-id={comment.id}>
  <div class="comment-header">
    <strong>{comment.author_username}</strong>
    <span class="comment-meta">
      commented on line {Math.abs(comment.line)}
    </span>
    {resolved && (
      <span class="resolved-badge">Resolved</span>
    )}
  </div>

  <div class="comment-body">
    <p>{comment.body}</p>
  </div>

  {canResolve && (
    <div class="comment-actions">
      <button
        class="btn btn-sm resolve-btn"
        data-comment-id={comment.id}
        data-resolved={resolved}
      >
        {resolved ? 'Unresolve' : 'Resolve'}
      </button>
    </div>
  )}
</div>

<script>
  document.querySelectorAll('.resolve-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const target = e.target as HTMLButtonElement;
      const commentId = target.dataset.commentId;
      const isResolved = target.dataset.resolved === 'true';

      // Would need resolver_id from context
      const resolverId = 1; // Hardcoded for now

      const res = await fetch(`/api${window.location.pathname}/comments/${commentId}/resolve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          resolver_id: resolverId,
          resolve: !isResolved
        })
      });

      if (res.ok) {
        window.location.reload();
      }
    });
  });
</script>

<style>
  .inline-comment {
    border: 1px solid black;
    padding: 0.75rem;
    margin: 0.5rem 0;
    background: #fffbf0;
  }

  .comment-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .comment-meta {
    font-size: 0.875rem;
    color: #666;
  }

  .resolved-badge {
    background: #d4edda;
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    border: 1px solid black;
  }

  .comment-body {
    margin: 0.5rem 0;
  }

  .comment-actions {
    margin-top: 0.5rem;
    padding-top: 0.5rem;
    border-top: 1px solid #ccc;
  }

  .btn-sm {
    padding: 0.25rem 0.5rem;
    font-size: 0.875rem;
  }
</style>
```

### 4.3 Review Summary Component

Create `/Users/williamcory/plue/ui/components/ReviewSummary.astro`:

```astro
---
interface Props {
  review: any;
}

const { review } = Astro.props;

const getReviewIcon = (type: string) => {
  switch (type) {
    case 'approve': return '✓';
    case 'reject': return '✗';
    case 'comment': return '💬';
    default: return '';
  }
};

const getReviewClass = (type: string) => {
  switch (type) {
    case 'approve': return 'approve';
    case 'reject': return 'reject';
    case 'comment': return 'comment';
    default: return '';
  }
};
---

<div class:list={['review-summary', getReviewClass(review.type), {
  'stale': review.stale,
  'dismissed': review.dismissed
}]}>
  <div class="review-header">
    <span class="review-icon">{getReviewIcon(review.type)}</span>
    <strong>{review.reviewer_username}</strong>
    <span class="review-type">{review.type.replace('_', ' ')}</span>
    {review.stale && <span class="badge">Stale</span>}
    {review.dismissed && <span class="badge">Dismissed</span>}
  </div>

  {review.content && (
    <div class="review-content">
      <p>{review.content}</p>
    </div>
  )}

  {review.code_comments && review.code_comments.length > 0 && (
    <div class="review-code-comments">
      <details>
        <summary>
          {review.code_comments.length} code comment{review.code_comments.length !== 1 ? 's' : ''}
        </summary>
        <div class="code-comments-list">
          {review.code_comments.map((comment: any) => (
            <div class="code-comment-item">
              <span class="file-path">{comment.file_path}</span>
              <span class="line-number">L{Math.abs(comment.line)}</span>
              <p class="comment-preview">{comment.body.substring(0, 100)}{comment.body.length > 100 ? '...' : ''}</p>
            </div>
          ))}
        </div>
      </details>
    </div>
  )}

  <div class="review-meta">
    {new Date(review.created_at).toLocaleDateString()}
  </div>
</div>

<style>
  .review-summary {
    border: 1px solid black;
    padding: 1rem;
    margin: 1rem 0;
  }

  .review-summary.approve {
    border-left: 4px solid #28a745;
  }

  .review-summary.reject {
    border-left: 4px solid #dc3545;
  }

  .review-summary.comment {
    border-left: 4px solid #6c757d;
  }

  .review-summary.stale {
    opacity: 0.7;
    background: #f8f9fa;
  }

  .review-summary.dismissed {
    opacity: 0.5;
    text-decoration: line-through;
  }

  .review-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .review-icon {
    font-size: 1.25rem;
  }

  .review-type {
    text-transform: capitalize;
    font-size: 0.875rem;
    color: #666;
  }

  .badge {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    border: 1px solid black;
    background: #fff3cd;
  }

  .review-content {
    margin: 1rem 0;
    padding: 0.75rem;
    background: #f8f9fa;
  }

  .review-code-comments {
    margin: 0.75rem 0;
  }

  .code-comments-list {
    margin-top: 0.5rem;
  }

  .code-comment-item {
    padding: 0.5rem;
    border: 1px solid #ddd;
    margin: 0.25rem 0;
    font-size: 0.875rem;
  }

  .file-path {
    font-family: monospace;
    font-weight: bold;
  }

  .line-number {
    color: #666;
    margin-left: 0.5rem;
  }

  .comment-preview {
    margin: 0.25rem 0 0;
    color: #666;
  }

  .review-meta {
    margin-top: 0.75rem;
    font-size: 0.875rem;
    color: #666;
  }
</style>
```

---

## 5. Enhanced PR Files Page with Inline Comments

Update `/Users/williamcory/plue/ui/pages/[user]/[repo]/pulls/[number]/files.astro` to support inline comments:

```astro
---
import Layout from "../../../../../../layouts/Layout.astro";
import Header from "../../../../../../components/Header.astro";
import InlineComment from "../../../../../../components/InlineComment.astro";
import { sql } from "../../../../../../lib/db";
import { compareRefs } from "../../../../../../lib/git";
import type { User, Repository, PullRequest } from "../../../../../../lib/types";

const { user: username, repo: reponame, number } = Astro.params;
const currentUserId = 1; // Hardcoded for now - should come from auth

const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
if (!user) return Astro.redirect("/404");

const [repo] = await sql`
  SELECT * FROM repositories
  WHERE user_id = ${user.id} AND name = ${reponame}
` as Repository[];
if (!repo) return Astro.redirect("/404");

const [pr] = await sql`
  SELECT pr.*, i.title, i.author_id
  FROM pull_requests pr
  JOIN issues i ON pr.issue_id = i.id
  WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number!, 10)}
` as any[];
if (!pr) return Astro.redirect("/404");

const compareInfo = await compareRefs(username, reponame, pr.base_branch, pr.head_branch);

// Get existing comments for files
const allComments = await sql`
  SELECT rc.*, u.username as author_username, rd.username as resolve_doer_username
  FROM review_comments rc
  JOIN users u ON rc.author_id = u.id
  LEFT JOIN users rd ON rc.resolve_doer_id = rd.id
  WHERE rc.pull_request_id = ${pr.id}
  ORDER BY rc.file_path, rc.line, rc.created_at
`;

// Group comments by file and line
const commentsByFile: Record<string, Record<number, any[]>> = {};
for (const comment of allComments) {
  if (!commentsByFile[comment.file_path]) {
    commentsByFile[comment.file_path] = {};
  }
  if (!commentsByFile[comment.file_path][comment.line]) {
    commentsByFile[comment.file_path][comment.line] = [];
  }
  commentsByFile[comment.file_path][comment.line].push(comment);
}

// Check if user can resolve (PR author, maintainer, or comment author)
const canResolve = (comment: any) => {
  return currentUserId === pr.author_id || currentUserId === comment.author_id;
};
---

<Layout title={`Files · PR #${number}`}>
  <Header />

  <div class="breadcrumb">
    <a href={`/${username}`}>{username}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}`}>{reponame}</a>
    <span class="sep">/</span>
    <a href={`/${username}/${reponame}/pulls/${number}`}>PR #{number}</a>
    <span class="sep">/</span>
    <span class="current">files</span>
  </div>

  <div class="container">
    <h1>Files Changed</h1>

    <div class="diff-stats">
      <strong>{compareInfo.total_files}</strong> files changed,
      <span class="add">+{compareInfo.total_additions}</span>,
      <span class="del">-{compareInfo.total_deletions}</span>
    </div>

    <div class="files-list">
      {compareInfo.files.map((file) => {
        const fileComments = commentsByFile[file.name] || {};

        return (
          <div class="file-diff" id={`file-${file.name.replace(/\//g, '-')}`}>
            <div class="file-header">
              <span class:list={["file-status", file.status]}>{file.status}</span>
              <span class="file-name">{file.name}</span>
              <span class="file-stats">
                <span class="add">+{file.additions}</span>
                <span class="del">-{file.deletions}</span>
              </span>
            </div>

            {file.isBinary ? (
              <div class="binary-file">Binary file</div>
            ) : (
              <div class="diff-content">
                {/* Render diff with line numbers and comment ability */}
                {file.patch.split('\n').map((line: string, idx: number) => {
                  // Parse diff line numbers (simplified)
                  const lineNumber = idx + 1;
                  const lineComments = fileComments[lineNumber] || fileComments[-lineNumber] || [];
                  const isAddition = line.startsWith('+');
                  const isDeletion = line.startsWith('-');

                  return (
                    <div class="diff-line-wrapper">
                      <div class:list={[
                        "diff-line",
                        { 'addition': isAddition, 'deletion': isDeletion }
                      ]}>
                        <span class="line-number">{lineNumber}</span>
                        <button
                          class="add-comment-btn"
                          data-file={file.name}
                          data-line={lineNumber}
                        >
                          +
                        </button>
                        <code>{line}</code>
                      </div>

                      {lineComments.length > 0 && (
                        <div class="line-comments">
                          {lineComments.map((comment: any) => (
                            <InlineComment
                              comment={comment}
                              canResolve={canResolve(comment)}
                              resolved={comment.resolve_doer_id !== null}
                              resolverId={currentUserId}
                            />
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  </div>
</Layout>

<script>
  // Add comment button handlers
  document.querySelectorAll('.add-comment-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const target = e.target as HTMLButtonElement;
      const file = target.dataset.file!;
      const line = parseInt(target.dataset.line!);

      const commentBody = prompt(`Add a comment for ${file}:${line}`);
      if (!commentBody) return;

      // Get or create pending review
      const reviewRes = await fetch(`/api${window.location.pathname}/reviews/pending?reviewer_id=1`);
      let { review } = await reviewRes.json();

      if (!review) {
        const startRes = await fetch(`/api${window.location.pathname}/reviews/start`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ reviewer_id: 1, commit_id: null })
        });
        const data = await startRes.json();
        review = data.review;
      }

      // Add comment
      const res = await fetch(`/api${window.location.pathname}/reviews/${review.id}/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          author_id: 1,
          commit_id: '',
          file_path: file,
          line: line,
          body: commentBody,
          patch: null
        })
      });

      if (res.ok) {
        window.location.reload();
      }
    });
  });
</script>

<style>
  .diff-content {
    font-family: monospace;
    font-size: 0.875rem;
  }

  .diff-line-wrapper {
    position: relative;
  }

  .diff-line {
    display: flex;
    align-items: center;
    padding: 0.25rem;
    border-bottom: 1px solid #eee;
  }

  .diff-line.addition {
    background: #e6ffed;
  }

  .diff-line.deletion {
    background: #ffebe9;
  }

  .diff-line:hover .add-comment-btn {
    opacity: 1;
  }

  .line-number {
    width: 3rem;
    text-align: right;
    padding-right: 0.5rem;
    color: #666;
  }

  .add-comment-btn {
    opacity: 0;
    width: 1.5rem;
    height: 1.5rem;
    border: 1px solid #666;
    background: white;
    cursor: pointer;
    margin-right: 0.5rem;
    transition: opacity 0.2s;
  }

  .add-comment-btn:hover {
    background: #f0f0f0;
  }

  .line-comments {
    background: #f8f9fa;
    padding: 0.5rem;
    border-left: 3px solid #ffc107;
  }
</style>
```

---

## 6. Implementation Checklist

### Phase 1: Database
- [ ] Update reviews table to use 'reject' instead of 'request_changes'
- [ ] Add original_author and original_author_id columns to reviews
- [ ] Drop and recreate review_comments table with proper structure
- [ ] Add resolve_doer_id column for conversation resolution
- [ ] Add patch column for diff context
- [ ] Update line column to support negative values for left/right side
- [ ] Run migrations: `bun db/migrate.ts`

### Phase 2: Types
- [ ] Update ReviewType to match Gitea (pending, comment, approve, reject)
- [ ] Add code_comments array to Review interface
- [ ] Update ReviewComment interface with resolve_doer_id and patch
- [ ] Add CreateReviewOptions and CreateReviewCommentOptions interfaces
- [ ] Add CodeComment grouping interface

### Phase 3: API Endpoints
- [ ] Implement GET /reviews/pending (get current pending review)
- [ ] Implement POST /reviews/start (create/get pending review)
- [ ] Implement POST /reviews/:id/comments (add inline comment)
- [ ] Implement POST /reviews/:id/submit (submit review)
- [ ] Implement GET /reviews (list all reviews with comments)
- [ ] Implement GET /comments/:path (get comments for file)
- [ ] Implement POST /comments/:id/resolve (resolve/unresolve conversation)
- [ ] Implement POST /reviews/:id/dismiss (dismiss review)
- [ ] Implement POST /reviews/mark-stale (mark reviews stale on push)

### Phase 4: UI Components
- [ ] Create ReviewForm.astro component
- [ ] Create InlineComment.astro component
- [ ] Create ReviewSummary.astro component
- [ ] Update files.astro page with inline comment support
- [ ] Add diff line number parsing and rendering
- [ ] Add "add comment" buttons on hover
- [ ] Add conversation threading display

### Phase 5: PR Detail Page Updates
- [ ] Update PR detail page to show reviews
- [ ] Add "Start Review" button
- [ ] Display review summary cards
- [ ] Show approve/reject/comment counts
- [ ] Add dismiss review functionality for maintainers

### Phase 6: Review Workflow
- [ ] Test creating pending review
- [ ] Test adding multiple inline comments
- [ ] Test submitting review as approve/comment/reject
- [ ] Test conversation resolution
- [ ] Test marking reviews as stale
- [ ] Test dismissing reviews

### Phase 7: Edge Cases
- [ ] Handle submitting review without content or comments (error)
- [ ] Handle approving/rejecting your own PR (prevent)
- [ ] Handle submitting review on closed/merged PR (error)
- [ ] Handle invalidated comments when code changes
- [ ] Handle permissions for resolving conversations

---

## 7. Reference: Gitea Implementation Details

### Review State Machine (from review.go)

```
pending → [submit] → comment/approve/reject
                        ↓
                   [dismiss] → dismissed=true
                        ↓
                   [new commits] → stale=true
```

### Review Types (from review.go:93-104)

```go
const (
    ReviewTypePending ReviewType = iota  // 0 - Draft review
    ReviewTypeApprove                    // 1 - Approves changes
    ReviewTypeComment                    // 2 - General feedback
    ReviewTypeReject                     // 3 - Requests changes
    ReviewTypeRequest                    // 4 - Review request (not used in Plue)
)
```

### Code Comment Structure (from comment.go:281-296)

```go
Line            int64         // Negative = left (old), positive = right (new)
TreePath        string        // File path
Content         string        // Comment body
Patch           string        // Diff context (quoted if non-UTF8)
CommitID        int64
CommitSHA       string        // Commit hash
ReviewID        int64         // Parent review
Invalidated     bool          // Line changed
ResolveDoerID   int64         // NULL = unresolved
```

### Comment Resolution (from review.go:879-904)

```go
func MarkConversation(ctx, comment *Comment, doer *User, isResolve bool) error {
    if comment.Type != CommentTypeCode {
        return nil
    }

    if isResolve {
        if comment.ResolveDoerID != 0 {
            return nil  // Already resolved
        }
        comment.ResolveDoerID = doer.ID
    } else {
        if comment.ResolveDoerID == 0 {
            return nil  // Already unresolved
        }
        comment.ResolveDoerID = 0
    }

    // Update database...
}
```

### Permissions for Resolution (from review.go:908-938)

Can resolve if:
1. User is PR author (issue.PosterID)
2. User has write access to PR repo
3. User is official reviewer
4. User is comment author

### Review Dismissal (from review.go:587-601)

```go
func DismissReview(ctx, review *Review, isDismiss bool) error {
    // Only approve/reject can be dismissed
    if review.Type != ReviewTypeApprove && review.Type != ReviewTypeReject {
        return nil
    }

    review.Dismissed = isDismiss
    // Update database...
}
```

### Stale Reviews (from review.go:573-584)

When new commits are pushed:
```go
func MarkReviewsAsStale(ctx, issueID int64) error {
    // Mark all reviews as stale
    UPDATE review SET stale=true WHERE issue_id=?
}

// Can unmark specific commit reviews as not stale
func MarkReviewsAsNotStale(ctx, issueID int64, commitID string) error {
    UPDATE review SET stale=false WHERE issue_id=? AND commit_id=?
}
```

### Review Content Validation (from pull/review.go:440-443)

```typescript
// TypeScript equivalent
function validateReview(type: ReviewType, content: string, codeComments: number): boolean {
  // Approve/reject without content requires at least one code comment
  if (type !== 'comment' && !content.trim() && codeComments === 0) {
    throw new Error('Review must have content or code comments');
  }
  return true;
}
```

---

## 8. Testing Scenarios

### Scenario 1: Simple Approve Review
1. User opens PR files page
2. User clicks "Start Review"
3. User selects "Approve" and adds summary
4. User submits review
5. Verify review appears on PR page
6. Verify PR can be merged

### Scenario 2: Inline Comments
1. User starts a review
2. User hovers over diff line and clicks "+"
3. User adds inline comment
4. User adds another inline comment on different file
5. User submits review as "Comment"
6. Verify both comments appear in files view
7. Verify comments grouped by conversation

### Scenario 3: Request Changes
1. User starts review
2. User adds inline comment requesting fix
3. User submits as "Request Changes"
4. Verify PR shows "Changes Requested" status
5. Verify PR cannot be merged

### Scenario 4: Conversation Resolution
1. PR has inline comment
2. PR author clicks "Resolve"
3. Verify comment marked as resolved
4. Verify resolved badge appears
5. Commenter clicks "Unresolve"
6. Verify comment unresolved

### Scenario 5: Stale Reviews
1. PR has approved review
2. New commits pushed to PR
3. API marks reviews as stale
4. Verify "Stale" badge on review
5. Verify PR status updated

### Scenario 6: Dismiss Review
1. Maintainer views approved review
2. Maintainer clicks "Dismiss"
3. Enters dismissal reason
4. Verify review marked dismissed
5. Verify dismissed badge appears

---

## 9. Implementation Notes

### Code Comment Line Numbers

The `line` field uses signed integers:
- **Positive**: Right side (new code) - e.g., `line: 42`
- **Negative**: Left side (old code) - e.g., `line: -42`

Helper functions:
```typescript
function getDiffSide(line: number): 'left' | 'right' {
  return line < 0 ? 'left' : 'right';
}

function getUnsignedLine(line: number): number {
  return Math.abs(line);
}
```

### Diff Patch Context

Store 4-5 lines of context around each comment:
```typescript
async function generatePatch(filePath: string, line: number): Promise<string> {
  // Use git show with context lines
  const contextLines = 5;
  // Return unified diff patch
}
```

### Review Permissions

```typescript
function canSubmitReview(userId: number, prAuthorId: number): boolean {
  // Cannot review your own PR
  return userId !== prAuthorId;
}

function canResolveComment(userId: number, prAuthorId: number, commentAuthorId: number): boolean {
  // PR author, comment author, or maintainer
  return userId === prAuthorId || userId === commentAuthorId;
}

function canDismissReview(userId: number, repoOwnerId: number): boolean {
  // Only maintainers
  return userId === repoOwnerId;
}
```

### Invalidating Comments on Push

When new commits are pushed:
1. Get all code comments for PR
2. For each comment, check if line still exists at that location
3. Use git blame to see if commit hash changed
4. Mark as invalidated if changed

```typescript
async function invalidateCommentsOnPush(prId: number, newCommitId: string) {
  const comments = await getCodeComments(prId);

  for (const comment of comments) {
    const stillValid = await checkLineStillExists(
      comment.file_path,
      comment.line,
      newCommitId
    );

    if (!stillValid) {
      await markCommentInvalidated(comment.id);
    }
  }
}
```

---

## 10. Future Enhancements (Out of Scope)

- Suggested reviewers based on git blame
- Review request notifications
- Required approvals before merge
- Dismissing all previous reviews from a reviewer
- Review threads (replies to inline comments)
- Code suggestion blocks (like GitHub)
- Batch comment resolution
- Review templates
- Approval workflows with multiple reviewers
- Auto-request reviews based on CODEOWNERS

---

## 11. Success Criteria

The implementation is complete when:

1. ✅ Users can start a pending review
2. ✅ Users can add multiple inline comments to a review
3. ✅ Users can submit review as approve/comment/reject
4. ✅ Reviews appear on PR detail page with correct status
5. ✅ Inline comments appear on specific diff lines in files view
6. ✅ Conversations can be resolved/unresolved
7. ✅ Reviews can be dismissed by maintainers
8. ✅ Reviews are marked stale when new commits are pushed
9. ✅ Cannot approve/reject your own PR
10. ✅ Cannot submit review on closed/merged PR
11. ✅ All UI follows Plue's brutalist design aesthetic

---

**References:**
- Gitea review model: `/Users/williamcory/plue/gitea/models/issues/review.go`
- Gitea comment model: `/Users/williamcory/plue/gitea/models/issues/comment.go`
- Gitea review routes: `/Users/williamcory/plue/gitea/routers/web/repo/pull_review.go`
- Gitea review service: `/Users/williamcory/plue/gitea/services/pull/review.go`
- Gitea review list: `/Users/williamcory/plue/gitea/models/issues/review_list.go`
- Existing PR implementation: `/Users/williamcory/plue/docs/prompts/02_pull_requests.md`
- Existing schema: `/Users/williamcory/plue/db/schema.sql`
