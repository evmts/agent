import type { Env, JWTPayload, User, Repository } from '../types';
import { layout } from '../templates/layout';
import { escapeHtml, formatDate, htmlResponse } from '../lib/html';
import { DataSyncDO } from '../durable-objects/data-sync';

export async function handleUserProfile(
  request: Request,
  env: Env,
  user: JWTPayload | null,
  params: { user: string }
): Promise<Response> {
  const doId = env.DATA_SYNC.idFromName('global');
  const stub = env.DATA_SYNC.get(doId) as DurableObjectStub<DataSyncDO>;

  const profileUser = await stub.getUser(params.user);
  if (!profileUser) {
    return htmlResponse(
      layout({ title: 'Not Found', user }, '<div class="empty">User not found</div>'),
      404
    );
  }

  const repos = await stub.getUserRepositories(profileUser.id);
  // Filter to public repos unless viewing own profile
  const visibleRepos =
    user?.username === params.user
      ? repos
      : repos.filter((r) => r.isPublic);

  const content = renderUserProfile(profileUser, visibleRepos, user?.username === params.user);
  return htmlResponse(layout({ title: profileUser.username, user }, content));
}

function renderUserProfile(
  profileUser: User,
  repos: Repository[],
  isOwner: boolean
): string {
  const repoList =
    repos.length > 0
      ? repos
          .map(
            (repo) => `
        <div class="list-item">
          <div class="flex justify-between items-center">
            <div class="list-item-title">
              <a href="/${escapeHtml(profileUser.username)}/${escapeHtml(repo.name)}">
                ${escapeHtml(repo.name)}
              </a>
              ${!repo.isPublic ? '<span class="badge">Private</span>' : ''}
            </div>
          </div>
          ${repo.description ? `<p class="text-muted mb-2">${escapeHtml(repo.description)}</p>` : ''}
          <div class="list-item-meta">
            Updated ${formatDate(repo.updatedAt)}
          </div>
        </div>
      `
          )
          .join('')
      : '<div class="empty">No repositories yet</div>';

  return `
    <div class="flex gap-4 mb-4">
      <div style="flex: 0 0 200px;">
        <div class="card">
          ${profileUser.avatarUrl ? `<img src="${escapeHtml(profileUser.avatarUrl)}" alt="" style="width:100%;margin-bottom:1rem;">` : ''}
          <h2>${escapeHtml(profileUser.displayName || profileUser.username)}</h2>
          <p class="text-muted">@${escapeHtml(profileUser.username)}</p>
          ${profileUser.bio ? `<p class="mt-4">${escapeHtml(profileUser.bio)}</p>` : ''}
          <p class="text-muted mt-4">Joined ${formatDate(profileUser.createdAt)}</p>
        </div>
      </div>
      <div style="flex: 1;">
        <div class="flex justify-between items-center mb-4">
          <h2>Repositories</h2>
          ${isOwner ? '<a href="/new" class="btn">New</a>' : ''}
        </div>
        <div class="list">
          ${repoList}
        </div>
      </div>
    </div>
  `;
}
