"""
Workflow runner for executing scripted CI/CD workflows.

Supports YAML-defined workflows with shell commands, file operations,
and git operations.
"""

import json
import subprocess
import os
from typing import List, Dict, Any, Optional, Callable

from .streaming import StreamingClient
from .logger import get_logger

logger = get_logger(__name__)


class WorkflowRunner:
    """Runs scripted workflow steps."""

    def __init__(self, streaming: StreamingClient):
        self.streaming = streaming
        self.env = os.environ.copy()

    def run(
        self,
        steps: List[Dict[str, Any]],
        abort_check: Optional[Callable[[], bool]] = None,
    ) -> bool:
        """
        Execute workflow steps in order.

        Args:
            steps: List of step definitions
            abort_check: Callable that returns True if execution should abort

        Returns:
            True if all steps completed successfully, False otherwise
        """
        for i, step in enumerate(steps):
            # Check for abort
            if abort_check and abort_check():
                logger.info("Workflow execution aborted")
                return False

            step_name = step.get("name", f"step-{i}")
            self.streaming.send_step_start(step_name, i)

            try:
                success = self._execute_step(step)

                if success:
                    self.streaming.send_step_end(step_name, i, "success")
                else:
                    self.streaming.send_step_end(step_name, i, "failure")
                    return False

            except Exception as e:
                logger.exception(f"Step {step_name} failed")
                self.streaming.send_step_end(
                    step_name, i, "error", str(e)
                )
                return False

        return True

    def _execute_step(self, step: Dict[str, Any]) -> bool:
        """Execute a single workflow step."""
        step_type = step.get("type", "run")

        if step_type == "run":
            return self._execute_run(step)
        elif step_type == "checkout":
            return self._execute_checkout(step)
        elif step_type == "env":
            return self._execute_env(step)
        else:
            logger.error(f"Unknown step type: {step_type}")
            return False

    def _execute_run(self, step: Dict[str, Any]) -> bool:
        """Execute a shell command."""
        command = step.get("run")
        if not command:
            logger.error("Missing 'run' field in step")
            return False

        working_dir = step.get("working-directory", "/workspace")

        self.streaming.send_log("info", f"Running: {command}")

        # Validate command doesn't contain obvious injection patterns
        dangerous_chars = ";|&$`<>"
        if any(char in command for char in dangerous_chars):
            logger.error(f"Command contains dangerous shell metacharacters")
            self.streaming.send_log("error", "Command rejected: contains shell metacharacters")
            return False

        # Use shlex to safely parse the command into argv array
        import shlex
        try:
            args = shlex.split(command)
        except ValueError as e:
            logger.error(f"Failed to parse command: {e}")
            self.streaming.send_log("error", f"Invalid command syntax: {e}")
            return False

        if not args:
            logger.error("Empty command after parsing")
            return False

        try:
            result = subprocess.run(
                args,
                shell=False,
                cwd=working_dir,
                env=self.env,
                capture_output=True,
                text=True,
                timeout=step.get("timeout-minutes", 10) * 60,
            )

            # Stream stdout
            if result.stdout:
                for line in result.stdout.split("\n"):
                    self.streaming.send_log("stdout", line)

            # Stream stderr
            if result.stderr:
                for line in result.stderr.split("\n"):
                    self.streaming.send_log("stderr", line)

            return result.returncode == 0

        except subprocess.TimeoutExpired:
            self.streaming.send_log("error", "Command timed out")
            return False
        except Exception as e:
            self.streaming.send_log("error", str(e))
            return False

    def _execute_checkout(self, step: Dict[str, Any]) -> bool:
        """Execute a checkout step (jj workspace)."""
        ref = step.get("ref", "@")

        self.streaming.send_log("info", f"Checking out: {ref}")

        try:
            result = subprocess.run(
                ["jj", "workspace", "update-stale"],
                cwd="/workspace",
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                self.streaming.send_log("error", result.stderr)
                return False

            return True

        except Exception as e:
            self.streaming.send_log("error", str(e))
            return False

    def _execute_env(self, step: Dict[str, Any]) -> bool:
        """Set environment variables."""
        for key, value in step.get("env", {}).items():
            self.env[key] = str(value)
            self.streaming.send_log("info", f"Set env: {key}")

        return True


def parse_workflow_yaml(content: str) -> Dict[str, Any]:
    """
    Parse a workflow YAML file.

    Args:
        content: YAML content

    Returns:
        Parsed workflow configuration
    """
    import yaml
    return yaml.safe_load(content)


def workflow_to_steps(workflow: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Convert a workflow definition to a list of executable steps.

    Args:
        workflow: Parsed workflow YAML

    Returns:
        List of step definitions
    """
    steps = []

    for job_name, job in workflow.get("jobs", {}).items():
        for step in job.get("steps", []):
            # Normalize step format
            normalized = {
                "name": step.get("name", step.get("run", "unnamed")[:50]),
            }

            if "run" in step:
                normalized["type"] = "run"
                normalized["run"] = step["run"]
            elif "uses" in step:
                # TODO: Implement action support
                normalized["type"] = "action"
                normalized["uses"] = step["uses"]

            if "working-directory" in step:
                normalized["working-directory"] = step["working-directory"]

            if "env" in step:
                normalized["env"] = step["env"]

            if "timeout-minutes" in step:
                normalized["timeout-minutes"] = step["timeout-minutes"]

            steps.append(normalized)

    return steps
