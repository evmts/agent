//! Dispatch Module - Unified Workflow/Agent Event System
//!
//! This module handles:
//! - Event triggering (push, PR, issue, chat)
//! - Task queue management with warm pool
//! - Webhook processing
//! - Runner registration and assignment

pub const trigger = @import("trigger.zig");
pub const queue = @import("queue.zig");
pub const webhook = @import("webhook.zig");

// Re-export commonly used types
pub const EventType = trigger.EventType;
pub const Event = trigger.Event;
pub const WorkloadType = queue.WorkloadType;
pub const WorkloadStatus = queue.WorkloadStatus;
