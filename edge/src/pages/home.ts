import type { Env, JWTPayload, Repository } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handleHome(
  request: Request,
  env: Env,
  user: JWTPayload | null
): Promise<Response> {
  // Get global DO stub
  const doId = env.DATA_SYNC.idFromName('global');
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  // Fetch public repositories
  const repos = await stub.getPublicRepositories(50);

  const content = renderHomePage(repos);
  return htmlResponse(layout({ title: 'Home', user }, content));
}

function renderHomePage(repos: (Repository & { username: string })[]): string {
  const repoList =
    repos.length > 0
      ? repos
          .map(
            (repo) => `
        <div class="list-item">
          <div class="list-item-title">
            <a href="/${escapeHtml(repo.username)}/${escapeHtml(repo.name)}">
              ${escapeHtml(repo.username)}/${escapeHtml(repo.name)}
            </a>
          </div>
          ${repo.description ? `<p class="text-muted mb-2">${escapeHtml(repo.description)}</p>` : ''}
          <div class="list-item-meta">
            Updated ${formatDate(repo.updatedAt)}
          </div>
        </div>
      `
          )
          .join('')
      : '<div class="empty">No public repositories yet</div>';

  return `
    <div class="flex justify-between items-center mb-4">
      <h1>Explore</h1>
      <a href="/new" class="btn btn-primary">New Repository</a>
    </div>
    <div class="list">
      ${repoList}
    </div>
  `;
}
