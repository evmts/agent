"""ModelInfo model."""

from pydantic import BaseModel


class ModelInfo(BaseModel):
    providerID: str
    modelID: str
