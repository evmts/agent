//! Repository Watcher Service
//!
//! Monitors jj repositories for changes and syncs data to PostgreSQL database.
//! Runs as a background service with file system watching and debouncing.

const std = @import("std");
const db = @import("../lib/db.zig");
const EdgeNotifier = @import("edge_notifier.zig").EdgeNotifier;
const WorkflowTrigger = @import("workflow_trigger.zig").WorkflowTrigger;
const jj = @cImport({
    @cInclude("jj_ffi.h");
});

const log = std.log.scoped(.repo_watcher);

/// Configuration for the repository watcher
pub const Config = struct {
    /// Debounce delay in milliseconds (waits this long after last change before syncing)
    debounce_ms: u64 = 300,
    /// How often to check for file changes in ms (polling interval)
    poll_interval_ms: u64 = 100,
    /// Base path for repositories (e.g., "repos/")
    repos_base_path: []const u8 = "repos",
    /// Maximum number of changes to sync per repository
    max_changes: u32 = 1000,
};

/// Represents a repository being watched
const WatchedRepo = struct {
    user: []const u8,
    repo: []const u8,
    repo_id: i64,
    last_modified: i64,
    debounce_timer: ?i64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *WatchedRepo) void {
        self.allocator.free(self.user);
        self.allocator.free(self.repo);
    }

    pub fn getPath(self: *const WatchedRepo, allocator: std.mem.Allocator, base_path: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ base_path, self.user, self.repo });
    }
};

/// Repository Watcher Service
pub const RepoWatcher = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    config: Config,
    watched_repos: std.StringHashMap(*WatchedRepo),
    running: std.atomic.Value(bool),
    thread: ?std.Thread,
    mutex: std.Thread.Mutex,
    edge_notifier: ?*EdgeNotifier,

    pub fn init(allocator: std.mem.Allocator, pool: *db.Pool, config: Config, edge_notifier: ?*EdgeNotifier) RepoWatcher {
        return .{
            .allocator = allocator,
            .pool = pool,
            .config = config,
            .watched_repos = std.StringHashMap(*WatchedRepo).init(allocator),
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
            .mutex = .{},
            .edge_notifier = edge_notifier,
        };
    }

    pub fn deinit(self: *RepoWatcher) void {
        self.stop();

        var it = self.watched_repos.valueIterator();
        while (it.next()) |repo| {
            repo.*.deinit();
            self.allocator.destroy(repo.*);
        }
        self.watched_repos.deinit();
    }

    /// Start the watcher service in a background thread
    pub fn start(self: *RepoWatcher) !void {
        if (self.running.load(.acquire)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);

        // Load all repositories from database and start watching
        try self.watchAllRepos();

        // Start background thread
        self.thread = try std.Thread.spawn(.{}, watcherThread, .{self});

        log.info("Repository watcher started", .{});
    }

    /// Stop the watcher service
    pub fn stop(self: *RepoWatcher) void {
        if (!self.running.load(.acquire)) {
            return;
        }

        self.running.store(false, .release);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        log.info("Repository watcher stopped", .{});
    }

    /// Load all repositories from database and add them to watch list
    pub fn watchAllRepos(self: *RepoWatcher) !void {
        var conn = try self.pool.acquire();
        defer conn.release();

        const query =
            \\SELECT r.id, r.name, u.username
            \\FROM repositories r
            \\JOIN users u ON r.user_id = u.id
            \\ORDER BY r.id
        ;

        var result = try conn.query(query, .{});
        defer result.deinit();

        var count: usize = 0;
        while (try result.next()) |row| {
            const repo_id = row.get(i64, 0);
            const repo_name = try self.allocator.dupe(u8, row.get([]const u8, 1));
            const username = try self.allocator.dupe(u8, row.get([]const u8, 2));

            errdefer {
                self.allocator.free(repo_name);
                self.allocator.free(username);
            }

            try self.watchRepo(username, repo_name, repo_id);
            count += 1;
        }

        log.info("Started watching {d} repositories", .{count});
    }

    /// Add a repository to the watch list
    pub fn watchRepo(self: *RepoWatcher, user: []const u8, repo: []const u8, repo_id: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ user, repo });
        defer self.allocator.free(key);

        // Don't add duplicates
        if (self.watched_repos.contains(key)) {
            return;
        }

        const watched_repo = try self.allocator.create(WatchedRepo);
        errdefer self.allocator.destroy(watched_repo);

        watched_repo.* = .{
            .user = try self.allocator.dupe(u8, user),
            .repo = try self.allocator.dupe(u8, repo),
            .repo_id = repo_id,
            .last_modified = 0,
            .debounce_timer = null,
            .allocator = self.allocator,
        };

        const stored_key = try self.allocator.dupe(u8, key);
        try self.watched_repos.put(stored_key, watched_repo);

        log.info("Started watching: {s}/{s}", .{ user, repo });
    }

    /// Remove a repository from the watch list
    pub fn unwatchRepo(self: *RepoWatcher, user: []const u8, repo: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ user, repo });
        defer self.allocator.free(key);

        if (self.watched_repos.fetchRemove(key)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);

            log.info("Stopped watching: {s}/{s}", .{ user, repo });
        }
    }

    /// Background thread that monitors repositories for changes
    fn watcherThread(self: *RepoWatcher) void {
        log.info("Watcher thread started", .{});

        while (self.running.load(.acquire)) {
            self.checkAllRepos() catch |err| {
                log.err("Error checking repositories: {}", .{err});
            };

            // Sleep for poll interval
            std.Thread.sleep(self.config.poll_interval_ms * std.time.ns_per_ms);
        }

        log.info("Watcher thread stopped", .{});
    }

    /// Check all watched repositories for changes
    fn checkAllRepos(self: *RepoWatcher) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        var it = self.watched_repos.valueIterator();
        while (it.next()) |watched_repo| {
            self.checkRepo(watched_repo.*, now) catch |err| {
                log.err("Error checking repo {s}/{s}: {}", .{ watched_repo.*.user, watched_repo.*.repo, err });
            };
        }
    }

    /// Check a single repository for changes
    fn checkRepo(self: *RepoWatcher, watched_repo: *WatchedRepo, now: i64) !void {
        const repo_path = try watched_repo.getPath(self.allocator, self.config.repos_base_path);
        defer self.allocator.free(repo_path);

        // Check if .jj directory exists
        const jj_path = try std.fmt.allocPrint(self.allocator, "{s}/.jj", .{repo_path});
        defer self.allocator.free(jj_path);

        var jj_dir = std.fs.cwd().openDir(jj_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Repository not initialized yet
                return;
            }
            return err;
        };
        jj_dir.close();

        // Get last modification time of .jj/op_heads/
        const op_heads_path = try std.fmt.allocPrint(self.allocator, "{s}/.jj/op_heads", .{repo_path});
        defer self.allocator.free(op_heads_path);

        const op_heads_stat = std.fs.cwd().statFile(op_heads_path) catch |err| {
            if (err == error.FileNotFound) {
                return;
            }
            return err;
        };

        const mtime: i64 = @truncate(@divFloor(op_heads_stat.mtime, std.time.ns_per_ms));

        // Check if repository changed
        if (mtime > watched_repo.last_modified) {
            watched_repo.last_modified = mtime;
            watched_repo.debounce_timer = now;
            log.debug("Detected change in {s}/{s}", .{ watched_repo.user, watched_repo.repo });
        }

        // Check if debounce timer expired
        if (watched_repo.debounce_timer) |timer| {
            if (now - timer >= self.config.debounce_ms) {
                watched_repo.debounce_timer = null;

                log.info("Syncing {s}/{s} to database", .{ watched_repo.user, watched_repo.repo });

                // Sync to database
                self.syncToDatabase(watched_repo) catch |err| {
                    log.err("Failed to sync {s}/{s}: {}", .{ watched_repo.user, watched_repo.repo, err });
                };
            }
        }
    }

    /// Sync repository data to database using jj-ffi
    fn syncToDatabase(self: *RepoWatcher, watched_repo: *WatchedRepo) !void {
        const repo_path = try watched_repo.getPath(self.allocator, self.config.repos_base_path);
        defer self.allocator.free(repo_path);

        // Convert to null-terminated C string
        const repo_path_z = try self.allocator.dupeZ(u8, repo_path);
        defer self.allocator.free(repo_path_z);

        // Open jj workspace
        const workspace_result = jj.jj_workspace_open(repo_path_z.ptr);
        if (!workspace_result.success) {
            defer if (workspace_result.error_message != null) jj.jj_string_free(workspace_result.error_message);
            const err_msg = if (workspace_result.error_message != null)
                std.mem.span(workspace_result.error_message)
            else
                "Unknown error";
            log.err("Failed to open workspace: {s}", .{err_msg});
            return error.WorkspaceOpenFailed;
        }
        const workspace = workspace_result.workspace orelse return error.WorkspaceOpenFailed;
        defer jj.jj_workspace_free(workspace);

        // Sync in parallel
        const sync_results = try self.allocator.alloc(SyncResult, 4);
        defer self.allocator.free(sync_results);

        var threads: [4]std.Thread = undefined;
        var thread_args: [4]SyncThreadArgs = undefined;

        // Prepare thread arguments
        for (0..4) |i| {
            thread_args[i] = .{
                .service = self,
                .workspace = workspace,
                .watched_repo = watched_repo,
                .result = &sync_results[i],
                .sync_type = @enumFromInt(i),
            };
        }

        // Start sync threads
        for (0..4) |i| {
            threads[i] = try std.Thread.spawn(.{}, syncThread, .{&thread_args[i]});
        }

        // Wait for all threads
        for (0..4) |i| {
            threads[i].join();
        }

        // Check results
        for (sync_results, 0..) |result, i| {
            if (result == .err) {
                log.err("Sync failed for type {d}: {s}", .{ i, @errorName(result.err) });
            }
        }

        // After successful sync, notify edge with merkle root
        if (self.edge_notifier) |notifier| {
            // Get tree hash for the working copy revision
            const tree_hash = jj.jj_get_tree_hash(workspace, "@");

            if (tree_hash.success) {
                defer jj.jj_free_tree_hash(tree_hash);

                const repo_key = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ watched_repo.user, watched_repo.repo },
                );
                defer self.allocator.free(repo_key);

                const hash_str = std.mem.span(tree_hash.hash);

                notifier.notifyGitChange(repo_key, hash_str) catch |err| {
                    log.warn("Failed to notify edge of git change: {}", .{err});
                };

                log.debug("Notified edge of merkle root update: {s} -> {s}", .{ repo_key, hash_str[0..@min(hash_str.len, 8)] });
            } else {
                if (tree_hash.error_message) |msg| {
                    log.warn("Failed to get tree hash: {s}", .{std.mem.span(msg)});
                    jj.jj_free_tree_hash(tree_hash);
                }
            }
        }

        // After successful sync, trigger workflows for push event
        self.triggerPushWorkflows(watched_repo, workspace) catch |err| {
            log.warn("Failed to trigger workflows: {}", .{err});
        };
    }

    const SyncType = enum(usize) {
        changes = 0,
        bookmarks = 1,
        operations = 2,
        conflicts = 3,
    };

    const SyncResult = union(enum) {
        ok: void,
        err: anyerror,
    };

    const SyncThreadArgs = struct {
        service: *RepoWatcher,
        workspace: *jj.JjWorkspace,
        watched_repo: *WatchedRepo,
        result: *SyncResult,
        sync_type: SyncType,
    };

    fn syncThread(args: *SyncThreadArgs) void {
        args.result.* = .{ .ok = {} };

        switch (args.sync_type) {
            .changes => {
                syncChanges(args.service, args.workspace, args.watched_repo) catch |err| {
                    args.result.* = .{ .err = err };
                };
            },
            .bookmarks => {
                syncBookmarks(args.service, args.workspace, args.watched_repo) catch |err| {
                    args.result.* = .{ .err = err };
                };
            },
            .operations => {
                syncOperations(args.service, args.workspace, args.watched_repo) catch |err| {
                    args.result.* = .{ .err = err };
                };
            },
            .conflicts => {
                syncConflicts(args.service, args.workspace, args.watched_repo) catch |err| {
                    args.result.* = .{ .err = err };
                };
            },
        }
    }

    /// Sync changes to the database
    fn syncChanges(self: *RepoWatcher, workspace: *jj.JjWorkspace, watched_repo: *WatchedRepo) !void {
        // List changes
        const changes_result = jj.jj_list_changes(workspace, self.config.max_changes, null);
        if (!changes_result.success) {
            defer if (changes_result.error_message != null) jj.jj_string_free(changes_result.error_message);
            return error.ListChangesFailed;
        }
        defer jj.jj_commit_array_free(changes_result.commits, changes_result.len);

        var conn = try self.pool.acquire();
        defer conn.release();

        // Insert/update each change
        var i: usize = 0;
        while (i < changes_result.len) : (i += 1) {
            const change_ptr = changes_result.commits[i];
            if (change_ptr == null) continue;
            const change = change_ptr.*;

            const change_id = std.mem.span(change.change_id);
            const commit_id = std.mem.span(change.id);
            const description = std.mem.span(change.description);
            const author_name = std.mem.span(change.author_name);
            const author_email = std.mem.span(change.author_email);

            const query =
                \\INSERT INTO changes (
                \\  change_id, repository_id, session_id, commit_id,
                \\  description, author_name, author_email, timestamp,
                \\  is_empty, has_conflicts
                \\) VALUES ($1, $2, $3, $4, $5, $6, $7, to_timestamp($8), $9, $10)
                \\ON CONFLICT (change_id) DO UPDATE SET
                \\  commit_id = EXCLUDED.commit_id,
                \\  description = EXCLUDED.description,
                \\  author_name = EXCLUDED.author_name,
                \\  author_email = EXCLUDED.author_email,
                \\  timestamp = EXCLUDED.timestamp,
                \\  is_empty = EXCLUDED.is_empty,
                \\  has_conflicts = EXCLUDED.has_conflicts
            ;

            var result = try conn.query(query, .{
                change_id,
                watched_repo.repo_id,
                @as(?i64, null), // session_id
                commit_id,
                description,
                author_name,
                author_email,
                @as(f64, @floatFromInt(change.author_timestamp)),
                change.is_empty,
                false, // has_conflicts (would need additional check)
            });
            result.deinit();
        }

        log.debug("Synced {d} changes for {s}/{s}", .{ changes_result.len, watched_repo.user, watched_repo.repo });
    }

    /// Sync bookmarks to the database
    fn syncBookmarks(self: *RepoWatcher, workspace: *jj.JjWorkspace, watched_repo: *WatchedRepo) !void {
        const bookmarks_result = jj.jj_list_bookmarks(workspace);
        if (!bookmarks_result.success) {
            defer if (bookmarks_result.error_message != null) jj.jj_string_free(bookmarks_result.error_message);
            return error.ListBookmarksFailed;
        }
        defer jj.jj_bookmark_array_free(bookmarks_result.bookmarks, bookmarks_result.len);

        var conn = try self.pool.acquire();
        defer conn.release();

        // Get existing bookmarks
        const existing_query = "SELECT name FROM bookmarks WHERE repository_id = $1";
        var existing_result = try conn.query(existing_query, .{watched_repo.repo_id});
        defer existing_result.deinit();

        var existing_names = std.StringHashMap(void).init(self.allocator);
        defer existing_names.deinit();

        while (try existing_result.next()) |row| {
            const name = row.get([]const u8, 0);
            const name_copy = try self.allocator.dupe(u8, name);
            try existing_names.put(name_copy, {});
        }
        defer {
            var it = existing_names.keyIterator();
            while (it.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        var current_names = std.StringHashMap(void).init(self.allocator);
        defer current_names.deinit();

        // Upsert current bookmarks
        var i: usize = 0;
        while (i < bookmarks_result.len) : (i += 1) {
            const bookmark = &bookmarks_result.bookmarks[i];
            const name = std.mem.span(bookmark.name);

            const name_copy = try self.allocator.dupe(u8, name);
            try current_names.put(name_copy, {});

            if (bookmark.target_id != null) {
                const target_id = std.mem.span(bookmark.target_id);

                const query =
                    \\INSERT INTO bookmarks (
                    \\  repository_id, name, target_change_id, pusher_id, is_default
                    \\) VALUES ($1, $2, $3, $4, $5)
                    \\ON CONFLICT (repository_id, name) DO UPDATE SET
                    \\  target_change_id = EXCLUDED.target_change_id,
                    \\  updated_at = NOW()
                ;

                var result = try conn.query(query, .{
                    watched_repo.repo_id,
                    name,
                    target_id,
                    @as(?i64, null), // pusher_id
                    false, // is_default
                });
                result.deinit();
            }
        }
        defer {
            var it = current_names.keyIterator();
            while (it.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        // Delete bookmarks that no longer exist
        var existing_it = existing_names.keyIterator();
        while (existing_it.next()) |name| {
            if (!current_names.contains(name.*)) {
                const delete_query = "DELETE FROM bookmarks WHERE repository_id = $1 AND name = $2";
                var result = try conn.query(delete_query, .{ watched_repo.repo_id, name.* });
                result.deinit();
            }
        }

        log.debug("Synced {d} bookmarks for {s}/{s}", .{ bookmarks_result.len, watched_repo.user, watched_repo.repo });
    }

    /// Sync operations to the database
    fn syncOperations(self: *RepoWatcher, workspace: *jj.JjWorkspace, watched_repo: *WatchedRepo) !void {
        const op_result = jj.jj_get_current_operation(workspace);
        if (!op_result.success) {
            defer if (op_result.error_message != null) jj.jj_string_free(op_result.error_message);
            return error.GetOperationFailed;
        }
        const op_ptr = op_result.operation orelse return error.OperationNotFound;
        defer jj.jj_operation_info_free(op_ptr);

        var conn = try self.pool.acquire();
        defer conn.release();

        const op = op_ptr.*;
        const op_id = std.mem.span(op.id);
        const description = std.mem.span(op.description);

        const query =
            \\INSERT INTO jj_operations (
            \\  repository_id, session_id, operation_id, operation_type,
            \\  description, timestamp, is_undone, metadata
            \\) VALUES ($1, $2, $3, $4, $5, to_timestamp($6), $7, $8)
            \\ON CONFLICT (operation_id) DO UPDATE SET
            \\  description = EXCLUDED.description,
            \\  timestamp = EXCLUDED.timestamp
        ;

        var result = try conn.query(query, .{
            watched_repo.repo_id,
            @as(?i64, null), // session_id
            op_id,
            "snapshot", // operation_type
            description,
            @as(f64, @floatFromInt(op.timestamp)),
            false, // is_undone
            @as(?[]const u8, null), // metadata
        });
        result.deinit();

        log.debug("Synced operation for {s}/{s}", .{ watched_repo.user, watched_repo.repo });
    }

    /// Sync conflicts to the database
    fn syncConflicts(self: *RepoWatcher, workspace: *jj.JjWorkspace, watched_repo: *WatchedRepo) !void {
        _ = workspace;

        var conn = try self.pool.acquire();
        defer conn.release();

        // Mark resolved conflicts
        const query =
            \\UPDATE conflicts
            \\SET resolved = true, resolved_at = NOW()
            \\WHERE repository_id = $1
            \\  AND resolved = false
            \\  AND change_id NOT IN (
            \\    SELECT change_id FROM changes WHERE has_conflicts = true AND repository_id = $1
            \\  )
        ;

        var result = try conn.query(query, .{watched_repo.repo_id});
        result.deinit();

        log.debug("Synced conflicts for {s}/{s}", .{ watched_repo.user, watched_repo.repo });
    }

    /// Trigger workflows for push event
    fn triggerPushWorkflows(self: *RepoWatcher, watched_repo: *WatchedRepo, workspace: *jj.JjWorkspace) !void {
        // Get current revision info
        const changes_result = jj.jj_list_changes(workspace, 1, null);
        if (!changes_result.success) {
            return error.ListChangesFailed;
        }
        defer jj.jj_commit_array_free(changes_result.commits, changes_result.len);

        if (changes_result.len == 0) {
            return; // No changes to trigger on
        }

        const latest_change = changes_result.commits[0].*;
        const commit_sha = std.mem.span(latest_change.id);

        // Get current bookmark/branch
        const bookmarks_result = jj.jj_list_bookmarks(workspace);
        var ref: ?[]const u8 = null;
        if (bookmarks_result.success and bookmarks_result.len > 0) {
            // Use first bookmark as ref
            ref = std.mem.span(bookmarks_result.bookmarks[0].name);
        }
        defer if (bookmarks_result.success) jj.jj_bookmark_array_free(bookmarks_result.bookmarks, bookmarks_result.len);

        // Initialize workflow trigger
        var trigger = WorkflowTrigger.init(self.allocator, self.pool);

        // Trigger workflows for push event
        trigger.triggerWorkflows(
            watched_repo.repo_id,
            "push",
            ref,
            commit_sha,
            null, // trigger_user_id (could be extracted from commit author)
        ) catch |err| {
            log.err("Failed to trigger workflows for {s}/{s}: {}", .{
                watched_repo.user,
                watched_repo.repo,
                err,
            });
            return err;
        };

        log.debug("Triggered push workflows for {s}/{s}", .{ watched_repo.user, watched_repo.repo });
    }
};

test "RepoWatcher init/deinit" {
    const allocator = std.testing.allocator;

    // Mock pool (would use real pool in integration tests)
    var mock_pool: db.Pool = undefined;

    var watcher = RepoWatcher.init(allocator, &mock_pool, .{}, null);
    defer watcher.deinit();

    try std.testing.expect(!watcher.running.load(.acquire));
}
