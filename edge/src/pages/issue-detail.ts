import type { Env, JWTPayload, Issue, Comment } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handleIssueDetail(
  request: Request,
  env: Env,
  user: JWTPayload | null,
  params: { user: string; repo: string; number: string }
): Promise<Response> {
  const issueNumber = parseInt(params.number, 10);

  const doId = env.DATA_SYNC.idFromName(`repo:${params.user}/${params.repo}`);
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  const repo = await stub.getRepoByOwnerAndName(params.user, params.repo);
  if (!repo) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Repository not found</div>'),
      404
    );
  }

  const issue = await stub.getIssue(repo.id, issueNumber);
  if (!issue) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Issue not found</div>'),
      404
    );
  }

  const comments = await stub.getIssueComments(issue.id);

  const navLinks = [
    { href: `/${params.user}/${params.repo}`, label: 'Code' },
    { href: `/${params.user}/${params.repo}/issues`, label: 'Issues', active: true },
    { href: `/${params.user}/${params.repo}/pulls`, label: 'Pull Requests' },
  ];

  const content = renderIssueDetail(params.user, params.repo, issue, comments, user);
  return htmlResponse(
    layout({ title: `${issue.title} - Issue #${issueNumber}`, user, navLinks }, content)
  );
}

function renderIssueDetail(
  owner: string,
  repoName: string,
  issue: Issue & { authorUsername: string },
  comments: (Comment & { authorUsername: string })[],
  user: JWTPayload | null
): string {
  const commentList = comments
    .map(
      (comment) => `
      <div class="card">
        <div class="card-header">
          <span class="card-meta">
            <strong>${escapeHtml(comment.authorUsername)}</strong> commented ${formatDate(comment.createdAt)}
          </span>
        </div>
        <div class="card-body">
          ${escapeHtml(comment.body).replace(/\n/g, '<br>')}
        </div>
      </div>
    `
    )
    .join('');

  const commentForm = user
    ? `
      <div class="card mt-4">
        <h3 class="mb-2">Add a comment</h3>
        <form action="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues/${issue.issueNumber}" method="POST">
          <input type="hidden" name="action" value="comment">
          <textarea name="body" rows="4" style="width:100%;font-family:inherit;padding:0.5rem;border:2px solid var(--border);" placeholder="Leave a comment..." required></textarea>
          <div class="flex justify-between items-center mt-2">
            <button type="submit" class="btn btn-primary">Comment</button>
            ${
              issue.state === 'open'
                ? `<button type="submit" name="action" value="close" class="btn">Close Issue</button>`
                : `<button type="submit" name="action" value="reopen" class="btn">Reopen Issue</button>`
            }
          </div>
        </form>
      </div>
    `
    : `<p class="text-muted mt-4"><a href="/login">Sign in</a> to comment</p>`;

  return `
    <div class="mb-4">
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues" class="text-muted">&larr; Back to issues</a>
    </div>

    <div class="flex items-center gap-2 mb-2">
      <span class="badge badge-${issue.state}">${issue.state}</span>
      <h1>${escapeHtml(issue.title)}</h1>
    </div>

    <p class="text-muted mb-4">
      #${issue.issueNumber} opened ${formatDate(issue.createdAt)} by
      <a href="/${escapeHtml(issue.authorUsername)}">${escapeHtml(issue.authorUsername)}</a>
    </p>

    <div class="card mb-4">
      <div class="card-body">
        ${issue.body ? escapeHtml(issue.body).replace(/\n/g, '<br>') : '<em class="text-muted">No description provided.</em>'}
      </div>
    </div>

    ${comments.length > 0 ? `<h2 class="mb-2">Comments (${comments.length})</h2>` : ''}
    ${commentList}

    ${commentForm}
  `;
}
