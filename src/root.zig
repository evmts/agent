//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

// Import all modules with tests
const config = @import("config/config.zig");
const git_handler = @import("server/handlers/git.zig");
const git_command = @import("git/command.zig");
const server = @import("server/server.zig");
const dao = @import("database/dao.zig");
const user_model = @import("database/models/user.zig");
const server_command = @import("commands/server.zig");
const issue_model = @import("database/models/issue.zig");
const repository_model = @import("database/models/repository.zig");
const action_model = @import("database/models/action.zig");
const main = @import("main.zig");
const start_command = @import("commands/start.zig");
const ssh_bindings = @import("ssh/bindings.zig");
const ssh_security = @import("ssh/security.zig");
const ssh_host_key = @import("ssh/host_key.zig");
const ssh_shutdown = @import("ssh/shutdown.zig");

test "All tests" {
    // Reference all modules to ensure their tests are included
    testing.refAllDecls(@This());
    testing.refAllDecls(config);
    testing.refAllDecls(git_handler);
    testing.refAllDecls(git_command);
    testing.refAllDecls(server);
    testing.refAllDecls(dao);
    testing.refAllDecls(user_model);
    testing.refAllDecls(server_command);
    testing.refAllDecls(issue_model);
    testing.refAllDecls(repository_model);
    testing.refAllDecls(action_model);
    testing.refAllDecls(main);
    testing.refAllDecls(start_command);
    testing.refAllDecls(ssh_bindings);
    testing.refAllDecls(ssh_security);
    testing.refAllDecls(ssh_host_key);
    testing.refAllDecls(ssh_shutdown);
}
