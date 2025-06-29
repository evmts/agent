// Re-export all command modules
pub const tui = @import("commands/tui.zig");
pub const run = @import("commands/run.zig");
pub const generate = @import("commands/generate.zig");
pub const scrap = @import("commands/scrap.zig");
pub const auth = @import("commands/auth.zig");
pub const upgrade = @import("commands/upgrade.zig");
pub const serve = @import("commands/serve.zig");
pub const models = @import("commands/models.zig");

// Common command utilities
pub const command = @import("command.zig");