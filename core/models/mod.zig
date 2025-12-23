// Models module - re-exports all model types
pub const session = @import("session.zig");
pub const message = @import("message.zig");
pub const part = @import("part.zig");

// Session types
pub const Session = session.Session;
pub const SessionTime = session.SessionTime;
pub const SessionSummary = session.SessionSummary;
pub const RevertInfo = session.RevertInfo;
pub const CompactionInfo = session.CompactionInfo;
pub const GhostCommitInfo = session.GhostCommitInfo;
pub const ReasoningEffort = session.ReasoningEffort;
pub const CreateSessionOptions = session.CreateSessionOptions;
pub const UpdateSessionOptions = session.UpdateSessionOptions;
pub const generateSessionId = session.generateSessionId;
pub const generateId = session.generateId;

// Message types
pub const Message = message.Message;
pub const UserMessage = message.UserMessage;
pub const AssistantMessage = message.AssistantMessage;
pub const MessageStatus = message.MessageStatus;
pub const MessageRole = message.MessageRole;
pub const MessageTime = message.MessageTime;
pub const ModelInfo = message.ModelInfo;
pub const PathInfo = message.PathInfo;
pub const TokenInfo = message.TokenInfo;
pub const generateMessageId = message.generateMessageId;

// Part types
pub const Part = part.Part;
pub const TextPart = part.TextPart;
pub const ReasoningPart = part.ReasoningPart;
pub const ToolPart = part.ToolPart;
pub const FilePart = part.FilePart;
pub const PartType = part.PartType;
pub const PartTime = part.PartTime;
pub const ToolState = part.ToolState;
pub const ToolStatus = part.ToolStatus;
pub const ToolStatePending = part.ToolStatePending;
pub const ToolStateRunning = part.ToolStateRunning;
pub const ToolStateCompleted = part.ToolStateCompleted;
pub const generatePartId = part.generatePartId;

test {
    @import("std").testing.refAllDecls(@This());
}
