// AI Agent Module
//
// This module provides the AI agent functionality for the Zig server,
// with a direct Anthropic API client.

const std = @import("std");

// Core types
pub const types = @import("types.zig");
pub const StreamEvent = types.StreamEvent;
pub const AgentOptions = types.AgentOptions;
pub const AgentMode = types.AgentMode;
pub const AgentConfig = types.AgentConfig;
pub const ToolContext = types.ToolContext;
pub const ToolError = types.ToolError;
pub const StreamCallbacks = types.StreamCallbacks;

// Re-export state management types
pub const FileTimeTracker = types.FileTimeTracker;
pub const SessionTrackers = types.SessionTrackers;
pub const ActiveTasks = types.ActiveTasks;
pub const FileDiff = types.FileDiff;
pub const SnapshotInfo = types.SnapshotInfo;
pub const EventBus = types.EventBus;
pub const Event = types.Event;
pub const EventType = types.EventType;

// Client
pub const client = @import("client.zig");
pub const AnthropicClient = client.AnthropicClient;
pub const Message = client.Message;
pub const Tool = client.Tool;
pub const Response = client.Response;

// Registry
pub const registry = @import("registry.zig");
pub const getAgentConfig = registry.getAgentConfig;
pub const isToolEnabled = registry.isToolEnabled;
pub const AGENT_NAMES = registry.AGENT_NAMES;
pub const build_agent = registry.build_agent;
pub const explore_agent = registry.explore_agent;
pub const plan_agent = registry.plan_agent;
pub const general_agent = registry.general_agent;

// Agent execution
pub const agent = @import("agent.zig");
pub const runAgent = agent.runAgent;
pub const streamAgent = agent.streamAgent;

// Tools
pub const tools = @import("tools/mod.zig");

// Version
pub const VERSION = "0.1.0";

test {
    std.testing.refAllDecls(@This());
    _ = @import("agent.test.zig");
}
