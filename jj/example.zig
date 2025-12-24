const std = @import("std");

// Import the C header
const c = @cImport({
    @cInclude("jj_ffi.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <path-to-jj-workspace>\n", .{args[0]});
        return error.MissingArgument;
    }

    const workspace_path = args[1];

    // Check if it's a jj workspace
    if (!c.jj_is_jj_workspace(workspace_path.ptr)) {
        std.debug.print("Error: {s} is not a jj workspace\n", .{workspace_path});
        return error.NotJjWorkspace;
    }

    // Open the workspace
    std.debug.print("Opening workspace: {s}\n", .{workspace_path});
    const workspace_result = c.jj_workspace_open(workspace_path.ptr);
    defer {
        if (workspace_result.success) {
            c.jj_workspace_free(workspace_result.workspace);
        }
        if (workspace_result.error_message != null) {
            c.jj_string_free(workspace_result.error_message);
        }
    }

    if (!workspace_result.success) {
        const err_msg = std.mem.span(workspace_result.error_message);
        std.debug.print("Error opening workspace: {s}\n", .{err_msg});
        return error.WorkspaceOpenFailed;
    }

    const workspace = workspace_result.workspace;

    // Get current operation
    std.debug.print("\n--- Current Operation ---\n", .{});
    const op_result = c.jj_get_current_operation(workspace);
    defer {
        if (op_result.success and op_result.operation != null) {
            c.jj_operation_info_free(op_result.operation);
        }
        if (op_result.error_message != null) {
            c.jj_string_free(op_result.error_message);
        }
    }

    if (op_result.success and op_result.operation != null) {
        const op = op_result.operation.*;
        const op_id = std.mem.span(op.id);
        const op_desc = std.mem.span(op.description);
        std.debug.print("Operation ID: {s}\n", .{op_id});
        std.debug.print("Description: {s}\n", .{op_desc});
        std.debug.print("Timestamp: {d}\n", .{op.timestamp});
    }

    // List bookmarks
    std.debug.print("\n--- Bookmarks ---\n", .{});
    const bookmarks_result = c.jj_list_bookmarks(workspace);
    defer {
        if (bookmarks_result.success and bookmarks_result.bookmarks != null) {
            c.jj_bookmark_array_free(bookmarks_result.bookmarks, bookmarks_result.len);
        }
        if (bookmarks_result.error_message != null) {
            c.jj_string_free(bookmarks_result.error_message);
        }
    }

    if (bookmarks_result.success) {
        std.debug.print("Found {d} bookmarks:\n", .{bookmarks_result.len});
        const bookmarks = bookmarks_result.bookmarks[0..bookmarks_result.len];
        for (bookmarks) |bookmark| {
            const name = std.mem.span(bookmark.name);
            if (bookmark.target_id != null) {
                const target = std.mem.span(bookmark.target_id);
                std.debug.print("  - {s} -> {s}\n", .{ name, target });
            } else {
                std.debug.print("  - {s} (no target)\n", .{name});
            }
        }
    } else {
        const err_msg = std.mem.span(bookmarks_result.error_message);
        std.debug.print("Error listing bookmarks: {s}\n", .{err_msg});
    }

    // List recent changes
    std.debug.print("\n--- Recent Changes ---\n", .{});
    const changes_result = c.jj_list_changes(workspace, 5, null);
    defer {
        if (changes_result.success and changes_result.commits != null) {
            c.jj_commit_array_free(changes_result.commits, changes_result.len);
        }
        if (changes_result.error_message != null) {
            c.jj_string_free(changes_result.error_message);
        }
    }

    if (changes_result.success) {
        std.debug.print("Found {d} recent changes:\n", .{changes_result.len});
        const commits = changes_result.commits[0..changes_result.len];
        for (commits, 0..) |commit_ptr, i| {
            const commit = commit_ptr.*;
            const change_id = std.mem.span(commit.change_id);
            const desc = std.mem.span(commit.description);
            const author = std.mem.span(commit.author_name);

            std.debug.print("\n{d}. Change ID: {s}\n", .{ i + 1, change_id[0..@min(12, change_id.len)] });
            std.debug.print("   Author: {s}\n", .{author});
            std.debug.print("   Description: {s}\n", .{desc});
            std.debug.print("   Empty: {}\n", .{commit.is_empty});
        }
    } else {
        const err_msg = std.mem.span(changes_result.error_message);
        std.debug.print("Error listing changes: {s}\n", .{err_msg});
    }

    // Try to get a specific commit (if we have any changes)
    if (changes_result.success and changes_result.len > 0) {
        const first_commit = changes_result.commits[0].*;
        const commit_id = std.mem.span(first_commit.id);

        std.debug.print("\n--- Files in Latest Commit ---\n", .{});
        const files_result = c.jj_list_files(workspace, commit_id.ptr);
        defer {
            if (files_result.success and files_result.strings != null) {
                c.jj_string_array_free(files_result.strings, files_result.len);
            }
            if (files_result.error_message != null) {
                c.jj_string_free(files_result.error_message);
            }
        }

        if (files_result.success) {
            std.debug.print("Found {d} files:\n", .{files_result.len});
            const files = files_result.strings[0..@min(10, files_result.len)];
            for (files) |file_ptr| {
                const file = std.mem.span(file_ptr);
                std.debug.print("  - {s}\n", .{file});
            }
            if (files_result.len > 10) {
                std.debug.print("  ... and {d} more\n", .{files_result.len - 10});
            }

            // Try to read the first file
            if (files_result.len > 0) {
                const first_file = std.mem.span(files_result.strings[0]);
                std.debug.print("\n--- Content of {s} ---\n", .{first_file});

                const content_result = c.jj_get_file_content(workspace, commit_id.ptr, files_result.strings[0]);
                defer {
                    if (content_result.string != null) {
                        c.jj_string_free(content_result.string);
                    }
                    if (content_result.error_message != null) {
                        c.jj_string_free(content_result.error_message);
                    }
                }

                if (content_result.success and content_result.string != null) {
                    const content = std.mem.span(content_result.string);
                    const preview_len = @min(500, content.len);
                    std.debug.print("{s}\n", .{content[0..preview_len]});
                    if (content.len > preview_len) {
                        std.debug.print("... ({d} more bytes)\n", .{content.len - preview_len});
                    }
                } else {
                    const err_msg = std.mem.span(content_result.error_message);
                    std.debug.print("Error reading file: {s}\n", .{err_msg});
                }
            }
        } else {
            const err_msg = std.mem.span(files_result.error_message);
            std.debug.print("Error listing files: {s}\n", .{err_msg});
        }
    }
}
