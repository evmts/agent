import type { APIRoute } from 'astro';
import { sql } from '../../../../../../lib/db';
import { getUserBySession } from '../../../../../../lib/auth-helpers';
import { mergePullRequest } from '../../../../../../lib/git';
import type { User, Repository, PullRequest, MergeStyle } from '../../../../../../lib/types';

// Merge a pull request
export const POST: APIRoute = async ({ params, request }) => {
  try {
    const { user: username, repo: reponame, number } = params;
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

    if (!mergeStyle || !mergeMessage) {
      return new Response(JSON.stringify({ error: 'Merge style and message are required' }), {
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

    const [pr] = await sql`
      SELECT pr.*, i.state
      FROM pull_requests pr
      JOIN issues i ON pr.issue_id = i.id
      WHERE i.repository_id = ${repo.id} AND i.issue_number = ${parseInt(number!, 10)}
    ` as PullRequest[];

    if (!pr) {
      return new Response(JSON.stringify({ error: 'Pull request not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (pr.has_merged) {
      return new Response(JSON.stringify({ error: 'Already merged' }), {
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
      mergeMessage,
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
        status = 'merged'
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
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};