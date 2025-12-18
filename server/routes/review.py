"""
Code review endpoint for analyzing git diffs.

Provides AI-powered code review with structured severity classification.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Query
from pydantic import BaseModel
from pydantic_ai import Agent

from agent.review import REVIEW_PROMPT, parse_review_output
from config import REVIEW_MODEL

logger = logging.getLogger(__name__)


# =============================================================================
# Constants
# =============================================================================

NO_CHANGES_MESSAGE = "No changes to review."


# =============================================================================
# Request/Response Models
# =============================================================================


class ReviewRequest(BaseModel):
    """Request for code review."""

    diff: str
    model: Optional[str] = None


class ReviewIssue(BaseModel):
    """A single review issue."""

    severity: str  # critical, warning, suggestion
    file: str
    line: Optional[int]
    message: str


class ReviewResponse(BaseModel):
    """Response from code review."""

    issues: list[ReviewIssue]
    positive_notes: list[str]
    summary: str
    model_used: str


# =============================================================================
# Router
# =============================================================================

router = APIRouter()


@router.post("/review")
async def run_review(
    request: ReviewRequest, directory: str | None = Query(None)
) -> ReviewResponse:
    """
    Run code review on provided git diff.

    Args:
        request: Review request with diff and optional model
        directory: Optional working directory (reserved for future use)

    Returns:
        ReviewResponse with structured issues, notes, and summary
    """
    # Check for empty diff
    if not request.diff or request.diff.strip() == "":
        return ReviewResponse(
            issues=[],
            positive_notes=[],
            summary=NO_CHANGES_MESSAGE,
            model_used=request.model or REVIEW_MODEL,
        )

    # Select model
    model = request.model or REVIEW_MODEL
    logger.info("Running code review with model: %s", model)

    # Create review prompt
    prompt = REVIEW_PROMPT.format(diff=request.diff)

    # Create a simple agent for review (no tools needed)
    agent = Agent(
        model=model,
        system_prompt="You are a code reviewer analyzing changes for issues and improvements.",
    )

    # Run agent synchronously (review is a simple single-turn task)
    try:
        result = await agent.run(prompt)
        content = result.data if hasattr(result, "data") else str(result)

        # Parse structured output
        review_result = parse_review_output(content)

        # Convert to response format
        return ReviewResponse(
            issues=[
                ReviewIssue(
                    severity=issue.severity,
                    file=issue.file,
                    line=issue.line,
                    message=issue.message,
                )
                for issue in review_result.issues
            ],
            positive_notes=review_result.positive_notes,
            summary=review_result.summary,
            model_used=model,
        )

    except Exception as e:
        logger.exception("Error during code review")
        return ReviewResponse(
            issues=[],
            positive_notes=[],
            summary=f"Error during review: {str(e)}",
            model_used=model,
        )
