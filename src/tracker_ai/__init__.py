"""Tracker AI package."""

from .core.analysis import AnalysisConfig, AnalysisResult, analyze_track
from .core.calibration import CalibrationProfile
from .core.session import ProjectSession
from .core.tracking import BBox, TrackResult, TrackingObservation
from .core.video import VideoMetadata, VideoSource

__all__ = [
    "AnalysisConfig",
    "AnalysisResult",
    "CalibrationProfile",
    "ProjectSession",
    "BBox",
    "TrackResult",
    "TrackingObservation",
    "VideoMetadata",
    "VideoSource",
    "analyze_track",
]

