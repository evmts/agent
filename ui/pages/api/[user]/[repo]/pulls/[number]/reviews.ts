import type { APIRoute } from 'astro';
import sql from '../../../../../../../db/client';
import { getUserBySession } from '../../../../../../lib/auth-helpers';
import type { User, Repository, PullRequest, Review, ReviewType } from '../../../../../../lib/types';

// Create a review for a pull request
export const POST: APIRoute = async ({ params, request }) => {
  try {
    const { user: username, repo: reponame, number } = params;
    const formData = await request.formData();
    
    const reviewType = formData.get('type') as ReviewType;
    const content = formData.get('content') as string;
    const commitId = formData.get('commit_id') as string;

    // Get authenticated user
    const authUser = await getUserBySession(request);
    if (!authUser) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate required fields
    if (!reviewType) {
      return new Response(JSON.stringify({ error: 'Review type is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate review type
    if (!['pending', 'comment', 'approve', 'request_changes'].includes(reviewType)) {
      return new Response(JSON.stringify({ error: 'Invalid review type' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [repo] = await sql`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    ` as Repository[];
    if (!repo) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const pullNumber = parseInt(number!, 10);
    if (isNaN(pullNumber)) {
      return new Response(JSON.stringify({ error: 'Invalid pull request number' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [pr] = await sql`
      SELECT pr.*, i.state
      FROM pull_requests pr
      JOIN issues i ON pr.issue_id = i.id
      WHERE i.repository_id = ${repo.id} AND i.issue_number = ${pullNumber}
    ` as PullRequest[];

    if (!pr) {
      return new Response(JSON.stringify({ error: 'Pull request not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (pr.state !== 'open') {
      return new Response(JSON.stringify({ error: 'Cannot review closed pull request' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Create review
    const [review] = await sql`
      INSERT INTO reviews (
        pull_request_id, reviewer_id, type, content, commit_id
      ) VALUES (
        ${pr.id}, ${authUser.id}, ${reviewType}, ${content?.trim() || null}, ${commitId || null}
      )
      RETURNING *
    ` as Review[];

    // Redirect back to the pull request
    return new Response('', {
      status: 302,
      headers: {
        'Location': `/${username}/${reponame}/pulls/${number}`
      }
    });
  } catch (error) {
    console.error('Create review error:', error);
    return new Response(JSON.stringify({ 
      error: 'Failed to create review',
      details: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

// Get reviews for a pull request
export const GET: APIRoute = async ({ params }) => {
  try {
    const { user: username, repo: reponame, number } = params;

    const [user] = await sql`SELECT * FROM users WHERE username = ${username}` as User[];
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [repo] = await sql`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    ` as Repository[];
    if (!repo) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const pullNumber = parseInt(number!, 10);
    if (isNaN(pullNumber)) {
      return new Response(JSON.stringify({ error: 'Invalid pull request number' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [pr] = await sql`
      SELECT pr.*
      FROM pull_requests pr
      JOIN issues i ON pr.issue_id = i.id
      WHERE i.repository_id = ${repo.id} AND i.issue_number = ${pullNumber}
    ` as PullRequest[];

    if (!pr) {
      return new Response(JSON.stringify({ error: 'Pull request not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const reviews = await sql`
      SELECT r.*, u.username as reviewer_username
      FROM reviews r
      JOIN users u ON r.reviewer_id = u.id
      WHERE r.pull_request_id = ${pr.id}
      ORDER BY r.created_at DESC
    ` as Review[];

    return new Response(JSON.stringify({ reviews }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Get reviews error:', error);
    return new Response(JSON.stringify({ 
      error: 'Failed to get reviews',
      details: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};