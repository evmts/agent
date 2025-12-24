"""
Plue Runner - Main entry point for sandboxed agent/workflow execution.

This runner executes in a gVisor-sandboxed K8s pod and streams results
back to the Zig API server.

Modes:
- active: Execute a task immediately (TASK_ID required)
- standby: Wait for assignment from the API server

Environment variables:
- MODE: "active" or "standby" (default: active)
- TASK_ID: Task identifier (required for active mode)
- CALLBACK_URL: URL to stream results back to
- ANTHROPIC_API_KEY: API key for Claude
- REGISTER_URL: URL to register as standby runner
"""

import os
import sys
import json
import signal
from typing import Optional

from .agent import AgentRunner
from .workflow import WorkflowRunner
from .streaming import StreamingClient
from .logger import configure_logging, get_logger

# Configure structured JSON logging
configure_logging(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    task_id=os.environ.get("TASK_ID"),
    request_id=os.environ.get("REQUEST_ID"),
)
logger = get_logger(__name__)


class Runner:
    """Main runner that handles both agent and workflow execution."""

    def __init__(
        self,
        task_id: str,
        callback_url: str,
        anthropic_api_key: str,
    ):
        self.task_id = task_id
        self.callback_url = callback_url
        self.anthropic_api_key = anthropic_api_key
        self.streaming = StreamingClient(callback_url, task_id)
        self.aborted = False

        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self._handle_sigterm)
        signal.signal(signal.SIGINT, self._handle_sigterm)

    def _handle_sigterm(self, signum, frame):
        """Handle termination signals."""
        logger.info(f"Received signal {signum}, aborting...")
        self.aborted = True

    def run(self, config: dict) -> int:
        """
        Execute a task based on its configuration.

        Args:
            config: Task configuration including type (agent/workflow) and parameters

        Returns:
            Exit code (0 for success, non-zero for failure)
        """
        try:
            task_type = config.get("type", "agent")

            if task_type == "agent":
                return self._run_agent(config)
            elif task_type == "workflow":
                return self._run_workflow(config)
            else:
                logger.error(f"Unknown task type: {task_type}")
                self.streaming.send_error(f"Unknown task type: {task_type}")
                return 1

        except Exception as e:
            logger.exception("Task execution failed")
            self.streaming.send_error(str(e))
            return 1

    def _run_agent(self, config: dict) -> int:
        """Execute an agent task."""
        logger.info(f"Running agent task: {self.task_id}")

        agent = AgentRunner(
            api_key=self.anthropic_api_key,
            model=config.get("model", "claude-sonnet-4-20250514"),
            system_prompt=config.get("system_prompt", ""),
            tools=config.get("tools", []),
            max_turns=config.get("max_turns", 20),
            streaming=self.streaming,
        )

        # Get initial messages
        messages = config.get("messages", [])

        try:
            result = agent.run(messages, abort_check=lambda: self.aborted)
            self.streaming.send_done()
            return 0 if result else 1
        except Exception as e:
            logger.exception("Agent execution failed")
            self.streaming.send_error(str(e))
            return 1

    def _run_workflow(self, config: dict) -> int:
        """Execute a workflow task."""
        logger.info(f"Running workflow task: {self.task_id}")

        workflow = WorkflowRunner(
            streaming=self.streaming,
        )

        # Get workflow steps
        steps = config.get("steps", [])

        try:
            result = workflow.run(steps, abort_check=lambda: self.aborted)
            self.streaming.send_done()
            return 0 if result else 1
        except Exception as e:
            logger.exception("Workflow execution failed")
            self.streaming.send_error(str(e))
            return 1


def run_standby_mode(register_url: str, anthropic_api_key: str):
    """
    Run in standby mode - register with the API and wait for assignment.
    """
    import httpx
    import time

    logger.info(f"Starting in standby mode, registering at {register_url}")

    pod_name = os.environ.get("POD_NAME", "unknown")
    pod_ip = os.environ.get("POD_IP", "unknown")

    while True:
        try:
            # Register with the API
            with httpx.Client(timeout=30.0) as client:
                response = client.post(
                    register_url,
                    json={
                        "pod_name": pod_name,
                        "pod_ip": pod_ip,
                    }
                )

                if response.status_code == 200:
                    data = response.json()
                    if data.get("task"):
                        # We've been assigned a task
                        task = data["task"]
                        callback_url = data.get("callback_url", "")

                        logger.info(f"Received task assignment: {task['id']}")

                        runner = Runner(
                            task_id=task["id"],
                            callback_url=callback_url,
                            anthropic_api_key=anthropic_api_key,
                        )

                        exit_code = runner.run(task["config"])
                        logger.info(f"Task completed with exit code: {exit_code}")

                        # After completing, re-register for next task
                        continue

                # No task available, sleep and retry
                time.sleep(5)

        except Exception as e:
            logger.exception("Error in standby mode")
            time.sleep(5)


def main():
    """Main entry point."""
    mode = os.environ.get("MODE", "active")
    anthropic_api_key = os.environ.get("ANTHROPIC_API_KEY")

    if not anthropic_api_key:
        logger.error("ANTHROPIC_API_KEY environment variable is required")
        sys.exit(1)

    if mode == "standby":
        register_url = os.environ.get("REGISTER_URL")
        if not register_url:
            logger.error("REGISTER_URL environment variable is required for standby mode")
            sys.exit(1)

        run_standby_mode(register_url, anthropic_api_key)
    else:
        # Active mode - execute task immediately
        task_id = os.environ.get("TASK_ID")
        callback_url = os.environ.get("CALLBACK_URL")

        if not task_id:
            logger.error("TASK_ID environment variable is required")
            sys.exit(1)

        if not callback_url:
            logger.error("CALLBACK_URL environment variable is required")
            sys.exit(1)

        # Read task config from stdin or environment
        config_json = os.environ.get("TASK_CONFIG")
        if config_json:
            config = json.loads(config_json)
        else:
            # Try reading from stdin
            config = json.load(sys.stdin)

        runner = Runner(
            task_id=task_id,
            callback_url=callback_url,
            anthropic_api_key=anthropic_api_key,
        )

        exit_code = runner.run(config)
        sys.exit(exit_code)


if __name__ == "__main__":
    main()
