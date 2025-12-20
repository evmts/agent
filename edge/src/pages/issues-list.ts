import type { Env, JWTPayload, Issue } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handleIssuesList(
  request: Request,
  env: Env,
  user: JWTPayload | null,
  params: { user: string; repo: string }
): Promise<Response> {
  const url = new URL(request.url);
  const state = (url.searchParams.get('state') || 'open') as 'open' | 'closed' | 'all';

  const doId = env.DATA_SYNC.idFromName(`repo:${params.user}/${params.repo}`);
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  const repo = await stub.getRepoByOwnerAndName(params.user, params.repo);
  if (!repo) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">Repository not found</div>'),
      404
    );
  }

  const [issues, counts] = await Promise.all([
    stub.getIssues(repo.id, state),
    stub.getIssueCounts(repo.id),
  ]);

  const navLinks = [
    { href: `/${params.user}/${params.repo}`, label: 'Code' },
    { href: `/${params.user}/${params.repo}/issues`, label: 'Issues', active: true },
    { href: `/${params.user}/${params.repo}/pulls`, label: 'Pull Requests' },
  ];

  const content = renderIssuesList(params.user, params.repo, issues, counts, state);
  return htmlResponse(
    layout({ title: `Issues - ${params.repo}`, user, navLinks }, content)
  );
}

function renderIssuesList(
  owner: string,
  repoName: string,
  issues: (Issue & { authorUsername: string })[],
  counts: { open: number; closed: number },
  currentState: string
): string {
  const tabs = `
    <div class="tabs">
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues?state=open"
         class="tab ${currentState === 'open' ? 'active' : ''}">
        Open (${counts.open})
      </a>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues?state=closed"
         class="tab ${currentState === 'closed' ? 'active' : ''}">
        Closed (${counts.closed})
      </a>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues?state=all"
         class="tab ${currentState === 'all' ? 'active' : ''}">
        All
      </a>
    </div>
  `;

  const issueList =
    issues.length > 0
      ? issues
          .map(
            (issue) => `
        <div class="list-item">
          <div class="flex items-center gap-2 mb-2">
            <span class="badge badge-${issue.state}">${issue.state}</span>
            <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues/${issue.issueNumber}"
               class="list-item-title">
              ${escapeHtml(issue.title)}
            </a>
          </div>
          <div class="list-item-meta">
            #${issue.issueNumber} opened ${formatDate(issue.createdAt)} by ${escapeHtml(issue.authorUsername)}
          </div>
        </div>
      `
          )
          .join('')
      : '<div class="empty">No issues found</div>';

  return `
    <div class="flex justify-between items-center mb-4">
      <h1>${escapeHtml(owner)}/${escapeHtml(repoName)} - Issues</h1>
      <a href="/${escapeHtml(owner)}/${escapeHtml(repoName)}/issues/new" class="btn btn-primary">New Issue</a>
    </div>
    ${tabs}
    <div class="list">
      ${issueList}
    </div>
  `;
}
