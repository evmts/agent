"""PathInfo model."""

from pydantic import BaseModel


class PathInfo(BaseModel):
    cwd: str
    root: str
