"""
Pydantic AI Agent module.
Exports the configured agent and initialization function.
"""
from .agent import create_agent
from .wrapper import AgentWrapper, StreamEvent

__all__ = ["create_agent", "AgentWrapper", "StreamEvent"]
