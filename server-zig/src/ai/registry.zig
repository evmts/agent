const std = @import("std");
const types = @import("types.zig");

const AgentConfig = types.AgentConfig;
const AgentMode = types.AgentMode;

/// System prompt prefix used by all agents
const SYSTEM_PROMPT_PREFIX =
    \\You are an AI assistant helping with software development tasks.
    \\You have access to tools for reading, writing, and searching files.
    \\
    \\Key principles:
    \\- Always read files before modifying them
    \\- Make minimal, targeted changes
    \\- Explain your reasoning before making changes
    \\- Ask for clarification when requirements are unclear
;

/// Build agent - primary agent with full tool access
pub const build_agent = AgentConfig{
    .name = "build",
    .description = "Primary agent with full tool access for development tasks",
    .mode = .primary,
    .system_prompt = SYSTEM_PROMPT_PREFIX ++
        \\
        \\You are the primary development agent with full access to:
        \\- File operations (read, write, edit)
        \\- Code search (grep)
        \\- Command execution (PTY)
        \\- Web access
        \\- GitHub CLI
        \\
        \\Use these tools carefully and always verify your changes.
    ,
    .temperature = @as(f32, 0.7),
    .top_p = @as(f32, 0.95),
    .tools_enabled = .{},
    .allowed_shell_patterns = &.{"*"},
};

/// Explore agent - read-only for fast codebase exploration
pub const explore_agent = AgentConfig{
    .name = "explore",
    .description = "Read-only agent for fast codebase exploration",
    .mode = .subagent,
    .system_prompt = SYSTEM_PROMPT_PREFIX ++
        \\
        \\You are an exploration agent with read-only access.
        \\Your job is to quickly search and analyze code without making changes.
        \\
        \\Focus on:
        \\- Finding relevant files and code patterns
        \\- Understanding code structure
        \\- Summarizing what you find
        \\
        \\You cannot write or modify files.
    ,
    .temperature = @as(f32, 0.5),
    .top_p = @as(f32, 0.9),
    .tools_enabled = .{
        .grep = true,
        .read_file = true,
        .write_file = false,
        .multiedit = false,
        .web_fetch = false,
        .github = true,
        .unified_exec = false,
        .write_stdin = false,
        .close_pty_session = false,
        .list_pty_sessions = false,
    },
    .allowed_shell_patterns = &.{ "ls *", "find *", "tree *", "git log *", "git show *", "git diff *", "git status" },
};

/// Plan agent - analysis and planning (read-only)
pub const plan_agent = AgentConfig{
    .name = "plan",
    .description = "Analysis and planning agent (read-only)",
    .mode = .subagent,
    .system_prompt = SYSTEM_PROMPT_PREFIX ++
        \\
        \\You are a planning agent focused on analysis and design.
        \\
        \\Your job is to:
        \\- Analyze requirements
        \\- Understand existing code structure
        \\- Design implementation approaches
        \\- Create detailed plans
        \\
        \\You can read files and fetch web content but cannot modify code.
    ,
    .temperature = @as(f32, 0.6),
    .top_p = @as(f32, 0.9),
    .tools_enabled = .{
        .grep = true,
        .read_file = true,
        .write_file = false,
        .multiedit = false,
        .web_fetch = true,
        .github = true,
        .unified_exec = false,
        .write_stdin = false,
        .close_pty_session = false,
        .list_pty_sessions = false,
    },
    .allowed_shell_patterns = &.{ "ls *", "find *", "tree *", "git *", "cat *" },
};

/// General agent - full access subagent
pub const general_agent = AgentConfig{
    .name = "general",
    .description = "General-purpose subagent with full tool access",
    .mode = .subagent,
    .system_prompt = SYSTEM_PROMPT_PREFIX ++
        \\
        \\You are a general-purpose agent that can be spawned for parallel tasks.
        \\You have full access to all tools.
        \\
        \\Complete your assigned task efficiently and report results clearly.
    ,
    .temperature = @as(f32, 0.7),
    .top_p = @as(f32, 0.95),
    .tools_enabled = .{},
    .allowed_shell_patterns = &.{"*"},
};

/// Get agent configuration by name
pub fn getAgentConfig(name: []const u8) AgentConfig {
    if (std.mem.eql(u8, name, "build")) return build_agent;
    if (std.mem.eql(u8, name, "explore")) return explore_agent;
    if (std.mem.eql(u8, name, "plan")) return plan_agent;
    if (std.mem.eql(u8, name, "general")) return general_agent;
    return build_agent; // Default fallback
}

/// Check if a tool is enabled for an agent
pub fn isToolEnabled(agent_name: []const u8, tool_name: []const u8) bool {
    const config = getAgentConfig(agent_name);

    if (std.mem.eql(u8, tool_name, "grep")) return config.tools_enabled.grep;
    if (std.mem.eql(u8, tool_name, "readFile")) return config.tools_enabled.read_file;
    if (std.mem.eql(u8, tool_name, "writeFile")) return config.tools_enabled.write_file;
    if (std.mem.eql(u8, tool_name, "multiedit")) return config.tools_enabled.multiedit;
    if (std.mem.eql(u8, tool_name, "webFetch")) return config.tools_enabled.web_fetch;
    if (std.mem.eql(u8, tool_name, "github")) return config.tools_enabled.github;
    if (std.mem.eql(u8, tool_name, "unifiedExec")) return config.tools_enabled.unified_exec;
    if (std.mem.eql(u8, tool_name, "writeStdin")) return config.tools_enabled.write_stdin;
    if (std.mem.eql(u8, tool_name, "closePtySession")) return config.tools_enabled.close_pty_session;
    if (std.mem.eql(u8, tool_name, "listPtySessions")) return config.tools_enabled.list_pty_sessions;

    return true; // Default to enabled
}

/// List all available agent names
pub const AGENT_NAMES: []const []const u8 = &.{
    "build",
    "explore",
    "plan",
    "general",
};

test "getAgentConfig returns correct config" {
    const build = getAgentConfig("build");
    try std.testing.expectEqualStrings("build", build.name);
    try std.testing.expectEqual(AgentMode.primary, build.mode);

    const explore = getAgentConfig("explore");
    try std.testing.expectEqualStrings("explore", explore.name);
    try std.testing.expectEqual(AgentMode.subagent, explore.mode);
}

test "isToolEnabled respects agent config" {
    // Build agent should have all tools enabled
    try std.testing.expect(isToolEnabled("build", "writeFile"));
    try std.testing.expect(isToolEnabled("build", "grep"));

    // Explore agent should not have write tools
    try std.testing.expect(!isToolEnabled("explore", "writeFile"));
    try std.testing.expect(isToolEnabled("explore", "grep"));
}
