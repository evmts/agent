"""PartInput models."""

from typing import Literal

from pydantic import BaseModel


class TextPartInput(BaseModel):
    type: Literal["text"] = "text"
    text: str


class FilePartInput(BaseModel):
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None


PartInput = TextPartInput | FilePartInput
