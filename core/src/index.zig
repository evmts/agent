// Core module - encapsulates all core logic for the agent system.
//
// This module provides:
// - Models (Session, Message, Part)
// - State management (FileTimeTracker, ActiveTasks)
// - Events (EventBus, Event types)
// - Exceptions (CoreError)

const std = @import("std");

// Models
pub const models = @import("models/mod.zig");
pub const Session = models.Session;
pub const SessionTime = models.SessionTime;
pub const SessionSummary = models.SessionSummary;
pub const RevertInfo = models.RevertInfo;
pub const CompactionInfo = models.CompactionInfo;
pub const GhostCommitInfo = models.GhostCommitInfo;
pub const ReasoningEffort = models.ReasoningEffort;
pub const CreateSessionOptions = models.CreateSessionOptions;
pub const UpdateSessionOptions = models.UpdateSessionOptions;
pub const generateSessionId = models.generateSessionId;
pub const generateId = models.generateId;

pub const Message = models.Message;
pub const UserMessage = models.UserMessage;
pub const AssistantMessage = models.AssistantMessage;
pub const MessageStatus = models.MessageStatus;
pub const MessageRole = models.MessageRole;
pub const MessageTime = models.MessageTime;
pub const ModelInfo = models.ModelInfo;
pub const PathInfo = models.PathInfo;
pub const TokenInfo = models.TokenInfo;
pub const generateMessageId = models.generateMessageId;

pub const Part = models.Part;
pub const TextPart = models.TextPart;
pub const ReasoningPart = models.ReasoningPart;
pub const ToolPart = models.ToolPart;
pub const FilePart = models.FilePart;
pub const PartType = models.PartType;
pub const PartTime = models.PartTime;
pub const ToolState = models.ToolState;
pub const ToolStatus = models.ToolStatus;
pub const ToolStatePending = models.ToolStatePending;
pub const ToolStateRunning = models.ToolStateRunning;
pub const ToolStateCompleted = models.ToolStateCompleted;
pub const generatePartId = models.generatePartId;

// State
pub const state = @import("state.zig");
pub const FileDiff = state.FileDiff;
pub const SnapshotInfo = state.SnapshotInfo;
pub const OperationInfo = state.OperationInfo;
pub const FileTimeTracker = state.FileTimeTracker;
pub const MessageWithParts = state.MessageWithParts;
pub const ActiveTasks = state.ActiveTasks;
pub const SessionTrackers = state.SessionTrackers;

// Events
pub const events = @import("events.zig");
pub const Event = events.Event;
pub const EventType = events.EventType;
pub const EventPayload = events.EventPayload;
pub const EventBus = events.EventBus;
pub const NullEventBus = events.NullEventBus;
pub const EventHandler = events.EventHandler;
pub const SessionEventData = events.SessionEventData;
pub const MessageEventData = events.MessageEventData;
pub const PartEventData = events.PartEventData;
pub const SnapshotEventData = events.SnapshotEventData;
pub const ToolEventData = events.ToolEventData;
pub const AgentEventData = events.AgentEventData;
pub const getEventBus = events.getEventBus;
pub const setEventBus = events.setEventBus;

// Exceptions
pub const exceptions = @import("exceptions.zig");
pub const CoreError = exceptions.CoreError;
pub const ErrorWithContext = exceptions.ErrorWithContext;

// Version
pub const VERSION = "0.1.0";

test {
    std.testing.refAllDecls(@This());
}
