import type { APIRoute } from 'astro';
import sql from '../../../../../../../db/client';
import { getUserBySession } from '../../../../../../lib/auth-helpers';
import { mergePullRequest } from '../../../../../../lib/git';
import type { User, Repository, PullRequest, MergeStyle, Issue } from '../../../../../../lib/types';

type PullRequestWithIssueState = PullRequest & { state: Issue['state'] };

// Merge a pull request
export const POST: APIRoute = async ({ params, request }) => {
  try {
    const { user: username, repo: reponame, number } = params;

    // Validate route params
    if (!username || !reponame || !number) {
      return new Response(JSON.stringify({ error: 'Invalid route parameters' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const formData = await request.formData();

    const mergeStyle = formData.get('merge_style') as MergeStyle;
    const mergeMessage = formData.get('merge_message') as string;

    // Get authenticated user
    const authUser = await getUserBySession(request);
    if (!authUser) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate required fields
    if (!mergeStyle) {
      return new Response(JSON.stringify({ error: 'Merge style is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!mergeMessage?.trim()) {
      return new Response(JSON.stringify({ error: 'Merge message is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate merge style
    if (!['merge', 'squash', 'rebase'].includes(mergeStyle)) {
      return new Response(JSON.stringify({ error: 'Invalid merge style' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [user] = await sql<User[]>`SELECT * FROM users WHERE username = ${username}`;
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [repo] = await sql<Repository[]>`
      SELECT * FROM repositories
      WHERE user_id = ${user.id} AND name = ${reponame}
    `;
    if (!repo) {
      return new Response(JSON.stringify({ error: 'Repository not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const pullNumber = parseInt(number, 10);
    if (isNaN(pullNumber)) {
      return new Response(JSON.stringify({ error: 'Invalid pull request number' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const [pr] = await sql<PullRequestWithIssueState[]>`
      SELECT pr.*, i.state
      FROM pull_requests pr
      JOIN issues i ON pr.issue_id = i.id
      WHERE i.repository_id = ${repo.id} AND i.issue_number = ${pullNumber}
    `;

    if (!pr) {
      return new Response(JSON.stringify({ error: 'Pull request not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (pr.has_merged) {
      return new Response(JSON.stringify({ error: 'Pull request is already merged' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (pr.state !== 'open') {
      return new Response(JSON.stringify({ error: 'Pull request is closed' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (pr.status !== 'mergeable') {
      return new Response(JSON.stringify({ error: `Cannot merge: status is ${pr.status}` }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Perform merge
    const mergeCommitId = await mergePullRequest(
      username,
      reponame,
      pr.base_branch,
      pr.head_branch,
      mergeStyle,
      mergeMessage.trim(),
      authUser.username,
      `${authUser.username}@plue.local`
    );

    // Update PR
    await sql`
      UPDATE pull_requests
      SET
        has_merged = true,
        merged_at = NOW(),
        merged_by = ${authUser.id},
        merged_commit_id = ${mergeCommitId},
        merge_style = ${mergeStyle},
        status = 'merged',
        updated_at = NOW()
      WHERE id = ${pr.id}
    `;

    // Close issue
    await sql`
      UPDATE issues
      SET state = 'closed', closed_at = NOW()
      WHERE id = ${pr.issue_id}
    `;

    // Redirect back to the pull request
    return new Response('', {
      status: 302,
      headers: {
        'Location': `/${username}/${reponame}/pulls/${number}`
      }
    });
  } catch (error) {
    console.error('Merge PR error:', error);
    return new Response(JSON.stringify({ 
      error: 'Failed to merge pull request',
      details: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};