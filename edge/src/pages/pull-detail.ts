import type { Env, JWTPayload, PullRequest, Review } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handlePullDetail(
  request: Request,
  env: Env,
  user: JWTPayload | null,
  params: { user: string; repo: string; number: string }
): Promise<Response> {
  const prNumber = parseInt(params.number, 10);

  const doId = env.DATA_SYNC.idFromName(`repo:${params.user}/${params.repo}`);
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  const repo = await stub.getRepoByOwnerAndName(params.user, params.repo);
  if (!repo) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Repository not found</div>'),
      404
    );
  }

  const pr = await stub.getPullRequest(repo.id, prNumber);
  if (!pr) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Pull request not found</div>'),
      404
    );
  }

  const reviews = await stub.getPullRequestReviews(pr.id);

  const navLinks = [
    { href: `/${params.user}/${params.repo}`, label: 'Code' },
    { href: `/${params.user}/${params.repo}/issues`, label: 'Issues' },
    { href: `/${params.user}/${params.repo}/pulls`, label: 'Pull Requests', active: true },
  ];

  const content = renderPullDetail(params.user, params.repo, pr, reviews, user);
  return htmlResponse(
    layout({ title: `${pr.title} - PR #${prNumber}`, user, navLinks }, content)
  );
}

function renderPullDetail(
  owner: string,
  repoName: string,
  pr: PullRequest & { title: string; body: string; authorUsername: string; issueNumber: number },
  reviews: (Review & { reviewerUsername: string })[],
  user: JWTPayload | null
): string {
  const badgeClass = pr.hasMerged ? 'badge-merged' : 'badge-open';
  const badgeText = pr.hasMerged ? 'merged' : 'open';

  const statusText =
    pr.status === 'mergeable'
      ? '<span style="color:#22c55e;">Ready to merge</span>'
      : pr.status === 'conflict'
        ? '<span style="color:#ef4444;">Has conflicts</span>'
        : pr.status === 'merged'
          ? '<span style="color:#8b5cf6;">Merged</span>'
          : '<span style="color:#eab308;">Checking...</span>';

  const reviewList =
    reviews.length > 0
      ? reviews
          .map((review) => {
            const icon =
              review.type === 'approve'
                ? '&#10003;'
                : review.type === 'request_changes'
                  ? '&#10007;'
                  : '&#128172;';
            return `
          <div class="card">
            <div class="card-header">
              <span>
                ${icon} <strong>${escapeHtml(review.reviewerUsername)}</strong>
                ${review.type === 'approve' ? 'approved' : review.type === 'request_changes' ? 'requested changes' : 'commented'}
              </span>
              <span class="card-meta">${formatDate(review.createdAt)}</span>
            </div>
            ${review.content ? `<div class="card-body">${escapeHtml(review.content).replace(/\n/g, '<br>')}</div>` : ''}
          </div>
        `;
          })
          .join('')
      : '';

  const actionsSection =
    user && !pr.hasMerged
      ? `
      <div class="card mt-4">
        <h3 class="mb-2">Actions</h3>
        <div class="flex gap-2">
          <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls/${pr.issueNumber}/files" class="btn">
            View Files Changed
          </a>
          ${
            pr.status === 'mergeable'
              ? `
            <form action="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls/${pr.issueNumber}" method="POST" style="display:inline">
              <input type="hidden" name="action" value="merge">
              <button type="submit" class="btn btn-primary">Merge Pull Request</button>
            </form>
          `
              : ''
          }
        </div>
      </div>
    `
      : pr.hasMerged
        ? ''
        : `<p class="text-muted mt-4"><a href="/login">Sign in</a> to review or merge</p>`;

  return `
    <div class="mb-4">
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls" class="text-muted">&larr; Back to pull requests</a>
    </div>

    <div class="flex items-center gap-2 mb-2">
      <span class="badge ${badgeClass}">${badgeText}</span>
      <h1>${escapeHtml(pr.title)}</h1>
    </div>

    <p class="text-muted mb-4">
      #${pr.issueNumber} opened ${formatDate(pr.createdAt)} by
      <a href="/${escapeHtml(pr.authorUsername)}">${escapeHtml(pr.authorUsername)}</a>
      &middot; ${escapeHtml(pr.headBranch)} &rarr; ${escapeHtml(pr.baseBranch)}
    </p>

    <div class="card mb-4">
      <div class="card-header">
        <span class="card-title">Status</span>
        ${statusText}
      </div>
    </div>

    <div class="card mb-4">
      <div class="card-body">
        ${pr.body ? escapeHtml(pr.body).replace(/\n/g, '<br>') : '<em class="text-muted">No description provided.</em>'}
      </div>
    </div>

    ${reviews.length > 0 ? `<h2 class="mb-2">Reviews (${reviews.length})</h2>` : ''}
    ${reviewList}

    ${actionsSection}
  `;
}
