"""
Features endpoint for managing feature flags.

Provides endpoints to list features and get feature status.
"""

from fastapi import APIRouter
from pydantic import BaseModel

from config.features import feature_manager


router = APIRouter()


class Feature(BaseModel):
    """A feature flag definition."""

    name: str
    description: str
    stage: str
    default: bool
    enabled: bool
    overridden: bool
    deprecated: bool


class FeatureStatus(BaseModel):
    """Feature enablement status."""

    name: str
    enabled: bool


# =============================================================================
# Endpoints
# =============================================================================


@router.get("/features")
async def list_features() -> list[Feature]:
    """
    List all feature flags with their current status.

    Returns:
        List of all feature flags with status information
    """
    features = feature_manager.list_features()
    return [
        Feature(
            name=f["name"],
            description=f["description"],
            stage=f["stage"],
            default=f["default"],
            enabled=f["enabled"],
            overridden=f["overridden"],
            deprecated=f["deprecated"],
        )
        for f in features
    ]


@router.get("/features/{feature_name}")
async def get_feature(feature_name: str) -> FeatureStatus:
    """
    Get the status of a specific feature.

    Args:
        feature_name: Name of the feature to check

    Returns:
        Feature status with name and enabled state
    """
    enabled = feature_manager.is_enabled(feature_name)
    return FeatureStatus(name=feature_name, enabled=enabled)
