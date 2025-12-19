import type { APIRoute } from 'astro';
import sql from '../../../../../db/client';
import { getUserBySession } from '../../../../lib/auth-helpers';
import { compareRefs, checkMergeable } from '../../../../lib/git';
import type { User, Repository, Issue, PullRequest } from '../../../../lib/types';

// Create a pull request
export const POST: APIRoute = async ({ params, request }) => {
  try {
    const { user: username, repo: reponame } = params;

    // Validate route params
    if (!username || !reponame) {
      return new Response(JSON.stringify({ error: 'Invalid route parameters' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const formData = await request.formData();

    const title = formData.get('title') as string;
    const description = formData.get('description') as string;
    const headBranch = formData.get('head_branch') as string;
    const baseBranch = formData.get('base_branch') as string;

    // Get authenticated user
    const authUser = await getUserBySession(request);
    if (!authUser) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate required fields
    if (!title?.trim()) {
      return new Response(JSON.stringify({ error: 'Title is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!headBranch?.trim()) {
      return new Response(JSON.stringify({ error: 'Head branch is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!baseBranch?.trim()) {
      return new Response(JSON.stringify({ error: 'Base branch is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (headBranch === baseBranch) {
      return new Response(JSON.stringify({ error: 'Head branch cannot be the same as base branch' }), {
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

    // Get next issue number
    const [{ next_num }] = await sql<{ next_num: number }[]>`
      SELECT COALESCE(MAX(issue_number), 0) + 1 as next_num
      FROM issues
      WHERE repository_id = ${repo.id}
    `;

    // Create issue first
    const [issue] = await sql<Issue[]>`
      INSERT INTO issues (
        repository_id, author_id, issue_number, title, body, state
      ) VALUES (
        ${repo.id}, ${authUser.id}, ${next_num}, ${title.trim()}, ${description?.trim() || ''}, 'open'
      )
      RETURNING *
    `;

    // Compare branches to get stats
    const compareInfo = await compareRefs(username, reponame, baseBranch, headBranch);

    // Check for conflicts
    const { mergeable, conflictedFiles } = await checkMergeable(
      username,
      reponame,
      baseBranch,
      headBranch
    );

    // Handle conflicted files array properly for PostgreSQL
    const conflictedFilesArray = conflictedFiles.length > 0 ? conflictedFiles : null;

    // Create pull request
    const [pr] = await sql<PullRequest[]>`
      INSERT INTO pull_requests (
        issue_id,
        head_repo_id, head_branch, head_commit_id,
        base_repo_id, base_branch,
        merge_base,
        status,
        commits_ahead, commits_behind,
        additions, deletions, changed_files,
        conflicted_files
      ) VALUES (
        ${issue.id},
        ${repo.id}, ${headBranch}, ${compareInfo.head_commit_id},
        ${repo.id}, ${baseBranch},
        ${compareInfo.merge_base},
        ${mergeable ? 'mergeable' : 'conflict'},
        ${compareInfo.commits_ahead}, ${compareInfo.commits_behind},
        ${compareInfo.total_additions}, ${compareInfo.total_deletions}, ${compareInfo.total_files},
        ${conflictedFilesArray}
      )
      RETURNING *
    `;

    // Redirect to the new pull request
    return new Response('', {
      status: 302,
      headers: {
        'Location': `/${username}/${reponame}/pulls/${next_num}`
      }
    });
  } catch (error) {
    console.error('Create PR error:', error);
    return new Response(JSON.stringify({ 
      error: 'Failed to create pull request',
      details: error instanceof Error ? error.message : 'Unknown error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};