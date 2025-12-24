//! Workflow System
//!
//! Implements Python-based workflow definitions with plan-based execution.
//! Workflows are evaluated in a restricted environment to produce deterministic
//! execution plans (DAGs) that are then executed by the runner system.

pub const plan = @import("plan.zig");
pub const evaluator = @import("evaluator.zig");
pub const prompt = @import("prompt.zig");
pub const validation = @import("validation.zig");
pub const registry = @import("registry.zig");
pub const executor = @import("executor.zig");
pub const llm_executor = @import("llm_executor.zig");
pub const runner_pool = @import("runner_pool.zig");
pub const local_runner = @import("local_runner.zig");

// Re-export main types
pub const WorkflowDefinition = plan.WorkflowDefinition;
pub const Step = plan.Step;
pub const StepType = plan.StepType;
pub const Trigger = plan.Trigger;
pub const TriggerType = plan.TriggerType;
pub const PlanSet = plan.PlanSet;
pub const PlanError = plan.PlanError;
pub const Evaluator = evaluator.Evaluator;
pub const PromptCatalog = evaluator.PromptCatalog;
pub const PromptDefinitionInfo = evaluator.PromptDefinitionInfo;
pub const PromptDefinition = prompt.PromptDefinition;
pub const parsePrompt = prompt.parsePrompt;
pub const parsePromptFile = prompt.parsePromptFile;
pub const renderTemplate = prompt.renderTemplate;
pub const validateWorkflow = validation.validateWorkflow;
pub const ValidationResult = validation.ValidationResult;
pub const validateJson = prompt.validateJson;
pub const SchemaValidationResult = prompt.ValidationResult;
pub const Registry = registry.Registry;
pub const DiscoveryResult = registry.DiscoveryResult;
pub const Executor = executor.Executor;
pub const StepStatus = executor.StepStatus;
pub const StepResult = executor.StepResult;
pub const ExecutionEvent = executor.ExecutionEvent;
pub const LlmExecutor = llm_executor.LlmExecutor;
pub const LlmExecutionResult = llm_executor.LlmExecutionResult;
pub const LlmExecutionEvent = llm_executor.LlmExecutionEvent;
pub const RunnerPool = runner_pool.RunnerPool;
pub const RunnerInfo = runner_pool.RunnerInfo;
pub const PoolStats = runner_pool.PoolStats;
pub const LocalRunner = local_runner.LocalRunner;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
