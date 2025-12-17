# Task Delegation to Sub-Agents

<metadata>
  <priority>high</priority>
  <category>agent-enhancement</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/agent.py, agent/registry.py, core/sessions.py, server/routes/</affects>
</metadata>

## Objective

Implement a task delegation system that allows the primary agent to spawn specialized sub-agents for parallel execution of complex, multi-step tasks.

<context>
The current agent implementation has a registry system with different agent types (build, general, plan, explore) but lacks the ability to spawn sub-agents dynamically for task decomposition. This feature would enable:
- Parallel execution of independent subtasks
- Specialized agents for different types of work (exploration vs. implementation)
- Better resource utilization on multi-step workflows
- Clear separation of concerns between planning and execution

Similar to multi-agent orchestration systems, this allows breaking down complex tasks like "refactor the authentication module" into parallel operations: one agent explores the codebase, another reviews tests, and another analyzes dependencies.
</context>

## Requirements

<functional-requirements>
1. Add a `task` tool that allows the primary agent to:
   - Define a subtask with clear objectives
   - Select specialized agent type (explore, general, plan)
   - Execute subtask in parallel with other operations
   - Collect and aggregate results from multiple sub-agents
2. Support parallel task execution:
   - Multiple sub-agents running concurrently
   - Progress tracking for each subtask
   - Timeout and cancellation support
3. Sub-agent isolation:
   - Each sub-agent operates in isolated context
   - Results returned to parent agent as structured data
   - No shared state between sub-agents (except session context)
4. Task types and agent selection:
   - Exploration tasks → `explore` agent (fast codebase search)
   - Analysis/planning tasks → `plan` agent (read-only analysis)
   - Implementation tasks → `general` agent (parallel execution specialist)
5. Result aggregation and synthesis:
   - Parent agent receives structured results from all sub-agents
   - Ability to make decisions based on aggregated data
   - Clear attribution of which sub-agent produced which results
</functional-requirements>

<technical-requirements>
1. Add `task` tool to agent tools in `agent/agent.py`
2. Implement `TaskExecutor` class for managing sub-agent lifecycle
3. Add task tracking to session state in `core/sessions.py`
4. Support asyncio for concurrent task execution
5. Implement proper cleanup and timeout handling
6. Add task results to message parts for UI display
7. Support both streaming and batch result collection
</technical-requirements>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Implementation Guide

<files-to-modify>
- `agent/agent.py` - Add task tool and TaskExecutor
- `agent/task_executor.py` - New file for task orchestration
- `agent/registry.py` - Add task delegation support to agent modes
- `core/sessions.py` - Track active tasks per session
- `core/events.py` - Add task-related event types
- `server/routes/tasks.py` - Optional: REST API for task management
</files-to-modify>

<task-tool-signature>
```python
@agent.tool_plain
async def task(
    objective: str,
    subagent_type: str = "general",
    context: dict[str, Any] | None = None,
    timeout_seconds: int = 120,
    session_id: str = "default",
) -> str:
    """Delegate a task to a specialized sub-agent for parallel execution.

    Use this tool to break down complex work into parallel subtasks that can
    be executed by specialized agents. Results are returned as structured data.

    Args:
        objective: Clear description of what the sub-agent should accomplish
        subagent_type: Type of agent to spawn:
            - "explore": Fast codebase exploration and search
            - "plan": Analysis and planning (read-only)
            - "general": Implementation and execution (full tools)
        context: Optional context dictionary to pass to sub-agent
        timeout_seconds: Maximum execution time (default 120s)
        session_id: Session identifier for task tracking

    Returns:
        JSON string with task results including:
        - task_id: Unique identifier for the task
        - status: "completed", "failed", "timeout"
        - result: Sub-agent's response or output
        - duration: Execution time in seconds
        - agent_type: Which sub-agent type was used

    Example:
        # Explore codebase for authentication-related code
        result = await task(
            objective="Find all files related to user authentication and authorization",
            subagent_type="explore"
        )

        # Analyze test coverage in parallel
        test_result = await task(
            objective="Analyze test coverage for the auth module",
            subagent_type="plan"
        )
    """
    # Implementation here
    pass
```
</task-tool-signature>

<task-executor-implementation>
```python
"""
Task executor for managing sub-agent delegation and parallel execution.
"""
from __future__ import annotations

import asyncio
import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

from pydantic_ai import Agent

from .agent import create_agent_with_mcp
from .registry import get_agent_config, AgentMode


@dataclass
class TaskResult:
    """Result from a sub-agent task execution."""

    task_id: str
    objective: str
    agent_type: str
    status: str  # "completed", "failed", "timeout", "cancelled"
    result: str | None = None
    error: str | None = None
    duration: float = 0.0
    started_at: float = field(default_factory=time.time)
    completed_at: float | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "task_id": self.task_id,
            "objective": self.objective,
            "agent_type": self.agent_type,
            "status": self.status,
            "result": self.result,
            "error": self.error,
            "duration": self.duration,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
        }


class TaskExecutor:
    """Manages sub-agent task execution and lifecycle."""

    def __init__(self, model_id: str, working_dir: str | None = None):
        """
        Initialize task executor.

        Args:
            model_id: Model identifier for sub-agents
            working_dir: Working directory for file operations
        """
        self.model_id = model_id
        self.working_dir = working_dir
        self._active_tasks: dict[str, asyncio.Task] = {}

    async def execute_task(
        self,
        objective: str,
        subagent_type: str = "general",
        context: dict[str, Any] | None = None,
        timeout_seconds: int = 120,
    ) -> TaskResult:
        """
        Execute a task with a sub-agent.

        Args:
            objective: Task objective/prompt
            subagent_type: Type of sub-agent to spawn
            context: Optional context dictionary
            timeout_seconds: Execution timeout

        Returns:
            TaskResult with execution details
        """
        task_id = str(uuid.uuid4())[:8]
        task_result = TaskResult(
            task_id=task_id,
            objective=objective,
            agent_type=subagent_type,
            status="running",
        )

        try:
            # Validate agent type exists
            agent_config = get_agent_config(subagent_type)
            if agent_config is None:
                task_result.status = "failed"
                task_result.error = f"Unknown agent type: {subagent_type}"
                return task_result

            # Execute with timeout
            async with asyncio.timeout(timeout_seconds):
                async with create_agent_with_mcp(
                    model_id=self.model_id,
                    agent_name=subagent_type,
                    working_dir=self.working_dir,
                ) as agent:
                    # Build prompt with context
                    prompt = objective
                    if context:
                        context_str = json.dumps(context, indent=2)
                        prompt = f"{objective}\n\nContext:\n{context_str}"

                    # Run agent
                    result = await agent.run(prompt)

                    task_result.status = "completed"
                    task_result.result = result.data
                    task_result.completed_at = time.time()
                    task_result.duration = task_result.completed_at - task_result.started_at

        except asyncio.TimeoutError:
            task_result.status = "timeout"
            task_result.error = f"Task exceeded timeout of {timeout_seconds}s"
            task_result.completed_at = time.time()
            task_result.duration = task_result.completed_at - task_result.started_at

        except Exception as e:
            task_result.status = "failed"
            task_result.error = str(e)
            task_result.completed_at = time.time()
            task_result.duration = task_result.completed_at - task_result.started_at

        return task_result

    async def execute_parallel(
        self,
        tasks: list[dict[str, Any]],
        timeout_seconds: int = 120,
    ) -> list[TaskResult]:
        """
        Execute multiple tasks in parallel.

        Args:
            tasks: List of task specifications (objective, subagent_type, context)
            timeout_seconds: Timeout for each individual task

        Returns:
            List of TaskResults in same order as input tasks
        """
        async_tasks = [
            self.execute_task(
                objective=task["objective"],
                subagent_type=task.get("subagent_type", "general"),
                context=task.get("context"),
                timeout_seconds=timeout_seconds,
            )
            for task in tasks
        ]

        results = await asyncio.gather(*async_tasks, return_exceptions=True)

        # Convert exceptions to failed TaskResults
        final_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                final_results.append(TaskResult(
                    task_id=str(uuid.uuid4())[:8],
                    objective=tasks[i]["objective"],
                    agent_type=tasks[i].get("subagent_type", "general"),
                    status="failed",
                    error=str(result),
                ))
            else:
                final_results.append(result)

        return final_results

    def get_active_task_count(self) -> int:
        """Get number of currently active tasks."""
        return len(self._active_tasks)

    async def cancel_all_tasks(self) -> None:
        """Cancel all active tasks."""
        for task in self._active_tasks.values():
            task.cancel()

        # Wait for cancellation to complete
        if self._active_tasks:
            await asyncio.gather(*self._active_tasks.values(), return_exceptions=True)

        self._active_tasks.clear()
```
</task-executor-implementation>

<integration-example>
```python
# In agent/agent.py, add the task tool:

from .task_executor import TaskExecutor

# Create task executor instance (in create_agent_with_mcp)
task_executor = TaskExecutor(model_id=model_id, working_dir=working_dir)

@agent.tool_plain
async def task(
    objective: str,
    subagent_type: str = "general",
    context: dict[str, Any] | None = None,
    timeout_seconds: int = 120,
    session_id: str = "default",
) -> str:
    """Delegate a task to a specialized sub-agent for parallel execution."""
    result = await task_executor.execute_task(
        objective=objective,
        subagent_type=subagent_type,
        context=context,
        timeout_seconds=timeout_seconds,
    )
    return json.dumps(result.to_dict(), indent=2)


@agent.tool_plain
async def task_parallel(
    tasks: list[dict[str, Any]],
    timeout_seconds: int = 120,
    session_id: str = "default",
) -> str:
    """Execute multiple tasks in parallel with specialized sub-agents."""
    results = await task_executor.execute_parallel(
        tasks=tasks,
        timeout_seconds=timeout_seconds,
    )
    return json.dumps([r.to_dict() for r in results], indent=2)
```
</integration-example>

<example-usage>
```python
# Example 1: Parallel codebase exploration
tasks = [
    {
        "objective": "Find all authentication-related files",
        "subagent_type": "explore"
    },
    {
        "objective": "Find all database migration files",
        "subagent_type": "explore"
    },
    {
        "objective": "Find all test files for the API",
        "subagent_type": "explore"
    }
]
results = await task_parallel(tasks)

# Example 2: Verify implementation with sub-agents
verification_tasks = [
    {
        "objective": "Run pytest on the auth module",
        "subagent_type": "general",
        "context": {"test_path": "tests/test_auth/"}
    },
    {
        "objective": "Check for any remaining TODOs in modified files",
        "subagent_type": "explore"
    },
    {
        "objective": "Analyze test coverage for new code",
        "subagent_type": "plan"
    }
]
verification = await task_parallel(verification_tasks)
```
</example-usage>

## Acceptance Criteria

<criteria>
- [ ] `task` tool available in primary agent
- [ ] `task_parallel` tool for concurrent task execution
- [ ] Sub-agent type validation (explore, plan, general)
- [ ] Timeout enforcement for long-running tasks
- [ ] Task results include task_id, status, duration
- [ ] Error handling for failed sub-agents
- [ ] Proper cleanup of sub-agent resources
- [ ] Session tracking of active tasks
- [ ] Task results included in message parts
- [ ] Parent agent can aggregate and synthesize sub-agent results
- [ ] No shared state between parallel sub-agents
- [ ] Cancellation support for aborting tasks
- [ ] Clear documentation in tool docstrings
</criteria>

## Testing Strategy

<test-requirements>
1. Unit tests for TaskExecutor:
   - Single task execution
   - Parallel task execution
   - Timeout handling
   - Error handling and recovery
2. Integration tests:
   - Agent spawning and lifecycle
   - Result aggregation
   - Session state tracking
3. Performance tests:
   - Multiple parallel tasks (3, 5, 10 concurrent)
   - Large result sets
   - Timeout behavior under load
4. End-to-end tests:
   - Complex multi-step workflows
   - Mixed agent types (explore + plan + general)
   - Error scenarios and fallbacks
</test-requirements>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_agent/` to ensure all tests pass
3. Test with the FastAPI server running (test task delegation via REST API)
4. Create example scripts demonstrating task delegation patterns
5. Update CLAUDE.md with task delegation documentation
6. Rename this file from `23-task-delegation.md` to `23-task-delegation.complete.md`
</completion>

## Design Considerations

<design-notes>
**Agent Mode Usage:**
- The registry already has `AgentMode.SUBAGENT` defined for the "general" agent
- Sub-agents should run with reduced thinking budget to conserve tokens
- Consider adding `max_turns` limit to prevent runaway sub-agent loops

**Session Isolation:**
- Each sub-agent gets a unique session context
- Parent session ID passed for tracking and logging
- Sub-agent results stored in parent session state

**Resource Management:**
- Limit maximum concurrent sub-agents (e.g., 5 at a time)
- Implement task queue for overflow
- Monitor token usage across all sub-agents
- Implement circuit breaker for repeated failures

**Future Enhancements:**
- Task dependencies (task B waits for task A)
- Streaming results from sub-agents
- Task prioritization and scheduling
- Result caching for identical tasks
- Sub-agent → sub-agent delegation (nested tasks)
</design-notes>
