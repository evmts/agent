"""
Undo session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import InvalidOperationError, NotFoundError, undo_turns

from ...event_bus import get_event_bus
from ...requests import UndoRequest, UndoResult


router = APIRouter()


@router.post("/session/{sessionID}/undo")
async def undo_session_turns(
    sessionID: str, request: UndoRequest, directory: str | None = Query(None)
) -> UndoResult:
    """Undo the last N turns in a session, reverting both messages and files."""
    try:
        turns_undone, messages_removed, files_reverted, snapshot_restored = await undo_turns(
            session_id=sessionID,
            event_bus=get_event_bus(),
            count=request.count,
        )
        return UndoResult(
            turns_undone=turns_undone,
            messages_removed=messages_removed,
            files_reverted=files_reverted,
            snapshot_restored=snapshot_restored,
        )
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
    except InvalidOperationError as e:
        raise HTTPException(status_code=500, detail=str(e))
