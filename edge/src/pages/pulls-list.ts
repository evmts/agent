import type { Env, JWTPayload, PullRequest } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handlePullsList(
  request: Request,
  env: Env,
  user: JWTPayload | null,
  params: { user: string; repo: string }
): Promise<Response> {
  const url = new URL(request.url);
  const state = (url.searchParams.get('state') || 'open') as 'open' | 'merged' | 'all';

  const doId = env.DATA_SYNC.idFromName(`repo:${params.user}/${params.repo}`);
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  const repo = await stub.getRepoByOwnerAndName(params.user, params.repo);
  if (!repo) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Repository not found</div>'),
      404
    );
  }

  const [prs, counts] = await Promise.all([
    stub.getPullRequests(repo.id, state),
    stub.getPullRequestCounts(repo.id),
  ]);

  const navLinks = [
    { href: `/${params.user}/${params.repo}`, label: 'Code' },
    { href: `/${params.user}/${params.repo}/issues`, label: 'Issues' },
    { href: `/${params.user}/${params.repo}/pulls`, label: 'Pull Requests', active: true },
  ];

  const content = renderPullsList(params.user, params.repo, prs, counts, state);
  return htmlResponse(
    layout({ title: `Pull Requests - ${params.repo}`, user, navLinks }, content)
  );
}

function renderPullsList(
  owner: string,
  repoName: string,
  prs: (PullRequest & { title: string; authorUsername: string; issueNumber: number })[],
  counts: { open: number; merged: number },
  currentState: string
): string {
  const tabs = `
    <div class="tabs">
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls?state=open"
         class="tab ${currentState === 'open' ? 'active' : ''}">
        Open (${counts.open})
      </a>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls?state=merged"
         class="tab ${currentState === 'merged' ? 'active' : ''}">
        Merged (${counts.merged})
      </a>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls?state=all"
         class="tab ${currentState === 'all' ? 'active' : ''}">
        All
      </a>
    </div>
  `;

  const prList =
    prs.length > 0
      ? prs
          .map((pr) => {
            const badgeClass = pr.hasMerged ? 'badge-merged' : 'badge-open';
            const badgeText = pr.hasMerged ? 'merged' : 'open';
            return `
        <div class="list-item">
          <div class="flex items-center gap-2 mb-2">
            <span class="badge ${badgeClass}">${badgeText}</span>
            <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls/${pr.issueNumber}"
               class="list-item-title">
              ${escapeHtml(pr.title)}
            </a>
          </div>
          <div class="list-item-meta">
            #${pr.issueNumber} opened ${formatDate(pr.createdAt)} by ${escapeHtml(pr.authorUsername)}
            &middot; ${escapeHtml(pr.headBranch)} &rarr; ${escapeHtml(pr.baseBranch)}
          </div>
        </div>
      `;
          })
          .join('')
      : '<div class="empty">No pull requests found</div>';

  return `
    <div class="flex justify-between items-center mb-4">
      <h1>${escapeHtml(owner)}/${escapeHtml(repoName)} - Pull Requests</h1>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/pulls/new" class="btn btn-primary">New Pull Request</a>
    </div>
    ${tabs}
    <div class="list">
      ${prList}
    </div>
  `;
}
