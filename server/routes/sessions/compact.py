"""
Compact session endpoint.
"""

import logging
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from config.defaults import DEFAULT_COMPACTION_MODEL, DEFAULT_PRESERVE_MESSAGES
from core import CoreError, NotFoundError, compact_conversation

from ...event_bus import get_event_bus


logger = logging.getLogger(__name__)


router = APIRouter()


class CompactRequest(BaseModel):
    """Request body for compact endpoint."""

    preserveCount: int | None = None
    modelID: str | None = None


class CompactResponse(BaseModel):
    """Response from compact endpoint."""

    compacted: bool
    reason: str | None = None
    messagesRemoved: int = 0
    tokensBefore: int = 0
    tokensAfter: int = 0
    tokensSaved: int = 0


@router.post("/session/{sessionID}/compact")
async def compact_session_route(
    sessionID: str,
    request: CompactRequest | None = None,
    directory: str | None = Query(None),
) -> CompactResponse:
    """
    Compact a session by summarizing older messages.

    This reduces the token count while preserving recent context.
    """
    try:
        # Use defaults if no request body provided
        preserve_count = DEFAULT_PRESERVE_MESSAGES
        model_id = DEFAULT_COMPACTION_MODEL

        if request:
            if request.preserveCount is not None:
                preserve_count = request.preserveCount
            if request.modelID is not None:
                model_id = request.modelID

        result = await compact_conversation(
            session_id=sessionID,
            event_bus=get_event_bus(),
            preserve_count=preserve_count,
            model_id=model_id,
        )

        return CompactResponse(
            compacted=result.compacted,
            reason=result.reason,
            messagesRemoved=result.messages_removed,
            tokensBefore=result.tokens_before,
            tokensAfter=result.tokens_after,
            tokensSaved=result.tokens_before - result.tokens_after,
        )

    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
    except CoreError as e:
        logger.error("Compaction failed for session %s: %s", sessionID, str(e))
        raise HTTPException(status_code=500, detail=f"Compaction failed: {str(e)}")
