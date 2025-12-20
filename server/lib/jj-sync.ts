/**
 * JJ Sync Service
 *
 * Syncs jj repository data (changes, bookmarks, operations, conflicts)
 * to the PostgreSQL database for querying and UI display.
 */

import {
  listChanges,
  listBookmarks,
  getOperationLog,
  getConflicts,
} from "../../ui/lib/jj";
import { sql } from "../../ui/lib/db";

class JjSyncService {
  /**
   * Main entry point: sync all jj data to the database
   */
  async syncToDatabase(user: string, repo: string): Promise<void> {
    // Get repository ID from database
    const [repository] = await sql`
      SELECT r.id
      FROM repositories r
      JOIN users u ON r.user_id = u.id
      WHERE u.username = ${user} AND r.name = ${repo}
      LIMIT 1
    `;

    if (!repository) {
      throw new Error(`Repository ${user}/${repo} not found`);
    }

    const repoId = repository.id;

    // Sync all jj data in parallel
    await Promise.all([
      this.syncChanges(user, repo, repoId),
      this.syncBookmarks(user, repo, repoId),
      this.syncOperations(user, repo, repoId),
      this.syncConflicts(user, repo, repoId),
    ]);
  }

  /**
   * Sync changes to the changes table
   */
  async syncChanges(user: string, repo: string, repoId: number): Promise<void> {
    const changes = await listChanges(user, repo, 1000);

    for (const change of changes) {
      await sql`
        INSERT INTO changes (
          change_id,
          repository_id,
          session_id,
          commit_id,
          parent_change_ids,
          description,
          author_name,
          author_email,
          timestamp,
          is_empty,
          has_conflicts
        ) VALUES (
          ${change.changeId},
          ${repoId},
          NULL,
          ${change.commitId},
          ${sql.array(change.parentChangeIds || [], 'text')},
          ${change.description},
          ${change.author.name},
          ${change.author.email},
          ${change.timestamp},
          ${change.isEmpty},
          ${change.hasConflicts}
        )
        ON CONFLICT (change_id) DO UPDATE SET
          commit_id = EXCLUDED.commit_id,
          description = EXCLUDED.description,
          author_name = EXCLUDED.author_name,
          author_email = EXCLUDED.author_email,
          timestamp = EXCLUDED.timestamp,
          is_empty = EXCLUDED.is_empty,
          has_conflicts = EXCLUDED.has_conflicts
      `;
    }
  }

  /**
   * Sync bookmarks to the bookmarks table
   */
  async syncBookmarks(user: string, repo: string, repoId: number): Promise<void> {
    const bookmarks = await listBookmarks(user, repo);

    // First, get all existing bookmarks for this repo
    const existingBookmarks = await sql`
      SELECT name FROM bookmarks WHERE repository_id = ${repoId}
    `;
    const existingNames = new Set(existingBookmarks.map((b: { name: string }) => b.name));
    const currentNames = new Set(bookmarks.map(b => b.name));

    // Upsert current bookmarks
    for (const bookmark of bookmarks) {
      await sql`
        INSERT INTO bookmarks (
          repository_id,
          name,
          target_change_id,
          pusher_id,
          is_default
        ) VALUES (
          ${repoId},
          ${bookmark.name},
          ${bookmark.targetChangeId},
          NULL,
          ${bookmark.isDefault}
        )
        ON CONFLICT (repository_id, name) DO UPDATE SET
          target_change_id = EXCLUDED.target_change_id,
          is_default = EXCLUDED.is_default,
          updated_at = NOW()
      `;
    }

    // Delete bookmarks that no longer exist in jj
    for (const name of existingNames) {
      if (!currentNames.has(name)) {
        await sql`
          DELETE FROM bookmarks
          WHERE repository_id = ${repoId} AND name = ${name}
        `;
      }
    }
  }

  /**
   * Sync operations to the jj_operations table
   */
  async syncOperations(user: string, repo: string, repoId: number): Promise<void> {
    const operations = await getOperationLog(user, repo, 100);

    for (const op of operations) {
      await sql`
        INSERT INTO jj_operations (
          repository_id,
          session_id,
          operation_id,
          operation_type,
          description,
          timestamp,
          is_undone,
          metadata
        ) VALUES (
          ${repoId},
          NULL,
          ${op.operationId},
          ${op.type},
          ${op.description},
          ${op.timestamp},
          ${op.isUndone},
          NULL
        )
        ON CONFLICT (operation_id) DO UPDATE SET
          operation_type = EXCLUDED.operation_type,
          description = EXCLUDED.description,
          timestamp = EXCLUDED.timestamp,
          is_undone = EXCLUDED.is_undone
      `;
    }
  }

  /**
   * Sync conflicts to the conflicts table
   */
  async syncConflicts(user: string, repo: string, repoId: number): Promise<void> {
    // Get all changes with conflicts
    const changesWithConflicts = await sql`
      SELECT change_id FROM changes
      WHERE repository_id = ${repoId} AND has_conflicts = true
    `;

    // Clear resolved conflicts that are no longer present
    await sql`
      UPDATE conflicts
      SET resolved = true, resolved_at = NOW()
      WHERE repository_id = ${repoId}
        AND resolved = false
        AND change_id NOT IN (
          SELECT change_id FROM changes WHERE has_conflicts = true
        )
    `;

    // Sync conflicts for each change that has them
    for (const row of changesWithConflicts) {
      const changeId = row.change_id;
      const conflicts = await getConflicts(user, repo, changeId);

      for (const conflict of conflicts) {
        await sql`
          INSERT INTO conflicts (
            repository_id,
            session_id,
            change_id,
            file_path,
            conflict_type,
            resolved,
            resolved_by,
            resolution_method,
            resolved_at
          ) VALUES (
            ${repoId},
            NULL,
            ${changeId},
            ${conflict.filePath},
            ${conflict.conflictType},
            ${conflict.resolved},
            NULL,
            NULL,
            NULL
          )
          ON CONFLICT (change_id, file_path) DO UPDATE SET
            conflict_type = EXCLUDED.conflict_type,
            resolved = EXCLUDED.resolved
        `;
      }
    }
  }
}

export const jjSyncService = new JjSyncService();
