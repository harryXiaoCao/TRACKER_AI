from __future__ import annotations

from dataclasses import asdict, dataclass, field
import json
from pathlib import Path

from .analysis import AnalysisConfig
from .calibration import CalibrationProfile
from .tracking import BBox, CorrectionAnchor, TrackQualityMetadata, TrackSpan, TrackedObject, TrackingConfig, TrackingProfile


SESSION_VERSION = 3


@dataclass(frozen=True)
class ExperimentMetadata:
    experiment_label: str = ""
    trial_id: str = ""
    operator_name: str = ""
    notes: str = ""
    tags: tuple[str, ...] = ()


@dataclass(frozen=True)
class SessionReviewState:
    last_frame_index: int = 0
    selected_window_start: int | None = None
    selected_window_end: int | None = None
    dismissed_review_frames: tuple[int, ...] = ()


@dataclass(frozen=True)
class EventMarker:
    name: str
    frame_index: int
    time_s: float
    value: float
    unit_label: str
    axis: str = ""
    note: str = ""
    origin: str = "derived"


@dataclass(frozen=True)
class ExportPreferences:
    include_overlay: bool = True
    include_debug_tracking: bool = False
    include_plots: bool = True
    report_template: str = "research"


@dataclass(frozen=True)
class ProvenanceMetadata:
    app_version: str = "0.1.0"
    source: str = "tracker_ai"
    video_path_snapshot: str = ""


@dataclass(frozen=True)
class ProjectSession:
    video_path: str
    initial_bbox: BBox
    calibration: CalibrationProfile
    analysis_config: AnalysisConfig
    version: int = SESSION_VERSION
    reference_bbox: BBox | None = None
    tracking_config: TrackingConfig = field(default_factory=TrackingConfig)
    metadata: ExperimentMetadata = field(default_factory=ExperimentMetadata)
    selected_start_frame: int = 0
    selected_end_frame: int | None = None
    scale_points: tuple[float, float, float, float] | None = None
    corrections: list[CorrectionAnchor] | None = None
    track_quality: TrackQualityMetadata | None = None
    advanced_mode: bool = False
    review_state: SessionReviewState = field(default_factory=SessionReviewState)
    event_markers: tuple[EventMarker, ...] = ()
    export_preferences: ExportPreferences = field(default_factory=ExportPreferences)
    provenance: ProvenanceMetadata = field(default_factory=ProvenanceMetadata)
    additional_objects: tuple[TrackedObject, ...] = ()

    def save(self, output_path: str | Path) -> Path:
        path = Path(output_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": self.version,
            "video_path": self.video_path,
            "initial_bbox": asdict(self.initial_bbox),
            "reference_bbox": asdict(self.reference_bbox) if self.reference_bbox is not None else None,
            "calibration": asdict(self.calibration),
            "analysis_config": asdict(self.analysis_config),
            "tracking_config": self._tracking_config_to_dict(self.tracking_config),
            "metadata": asdict(self.metadata),
            "selected_start_frame": self.selected_start_frame,
            "selected_end_frame": self.selected_end_frame,
            "scale_points": list(self.scale_points) if self.scale_points is not None else None,
            "corrections": [asdict(correction) for correction in (self.corrections or [])],
            "track_quality": self._quality_to_dict(self.track_quality) if self.track_quality else None,
            "advanced_mode": self.advanced_mode,
            "review_state": asdict(self.review_state),
            "event_markers": [asdict(event) for event in self.event_markers],
            "export_preferences": asdict(self.export_preferences),
            "provenance": asdict(self.provenance),
            "additional_objects": [asdict(item) for item in self.additional_objects],
        }
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    @classmethod
    def load(cls, input_path: str | Path) -> "ProjectSession":
        payload = json.loads(Path(input_path).read_text(encoding="utf-8"))
        return cls(
            version=int(payload.get("version", 1)),
            video_path=payload["video_path"],
            initial_bbox=BBox(**payload["initial_bbox"]),
            reference_bbox=BBox(**payload["reference_bbox"]) if payload.get("reference_bbox") else None,
            calibration=CalibrationProfile(**payload["calibration"]),
            analysis_config=AnalysisConfig(**payload["analysis_config"]),
            tracking_config=cls._tracking_config_from_dict(payload.get("tracking_config")),
            metadata=cls._metadata_from_dict(payload.get("metadata")),
            selected_start_frame=int(payload.get("selected_start_frame", 0)),
            selected_end_frame=int(payload["selected_end_frame"]) if payload.get("selected_end_frame") is not None else None,
            scale_points=tuple(payload["scale_points"]) if payload.get("scale_points") else None,
            corrections=[
                CorrectionAnchor(frame_index=item["frame_index"], bbox=BBox(**item["bbox"]), note=item.get("note", "manual_correction"))
                for item in payload.get("corrections", [])
            ],
            track_quality=cls._quality_from_dict(payload.get("track_quality")),
            advanced_mode=bool(payload.get("advanced_mode", False)),
            review_state=cls._review_state_from_dict(payload.get("review_state")),
            event_markers=tuple(EventMarker(**item) for item in payload.get("event_markers", [])),
            export_preferences=cls._export_preferences_from_dict(payload.get("export_preferences")),
            provenance=cls._provenance_from_dict(payload.get("provenance"), payload.get("video_path", "")),
            additional_objects=tuple(TrackedObject(track_id=item["track_id"], name=item["name"], bbox=BBox(**item["bbox"]), kind=item.get("kind", "secondary")) for item in payload.get("additional_objects", [])),
        )

    @staticmethod
    def _quality_to_dict(quality: TrackQualityMetadata) -> dict[str, object]:
        return {
            "lost_spans": [asdict(span) for span in quality.lost_spans],
            "suspect_spans": [asdict(span) for span in quality.suspect_spans],
            "corrected_spans": [asdict(span) for span in quality.corrected_spans],
            "reacquisition_count": quality.reacquisition_count,
            "review_recommended": quality.review_recommended,
        }

    @staticmethod
    def _quality_from_dict(payload: dict[str, object] | None) -> TrackQualityMetadata | None:
        if not payload:
            return None
        return TrackQualityMetadata(
            lost_spans=[TrackSpan(**span) for span in payload.get("lost_spans", [])],
            suspect_spans=[TrackSpan(**span) for span in payload.get("suspect_spans", [])],
            corrected_spans=[TrackSpan(**span) for span in payload.get("corrected_spans", [])],
            reacquisition_count=int(payload.get("reacquisition_count", 0)),
            review_recommended=bool(payload.get("review_recommended", False)),
        )

    @staticmethod
    def _tracking_config_to_dict(config: TrackingConfig) -> dict[str, object]:
        return {
            "profile": config.profile.value,
            "robust_recovery": config.robust_recovery,
            "bidirectional_refinement": config.bidirectional_refinement,
            "debug_tracking": config.debug_tracking,
            "interpolate_short_gaps": config.interpolate_short_gaps,
            "max_interpolation_gap": config.max_interpolation_gap,
        }

    @staticmethod
    def _tracking_config_from_dict(payload: dict[str, object] | None) -> TrackingConfig:
        if not payload:
            return TrackingConfig()
        return TrackingConfig(
            profile=TrackingProfile(payload.get("profile", TrackingProfile.AUTO.value)),
            robust_recovery=bool(payload.get("robust_recovery", True)),
            bidirectional_refinement=bool(payload.get("bidirectional_refinement", True)),
            debug_tracking=bool(payload.get("debug_tracking", False)),
            interpolate_short_gaps=bool(payload.get("interpolate_short_gaps", True)),
            max_interpolation_gap=int(payload.get("max_interpolation_gap", 3)),
        )

    @staticmethod
    def _metadata_from_dict(payload: dict[str, object] | None) -> ExperimentMetadata:
        if not payload:
            return ExperimentMetadata()
        return ExperimentMetadata(
            experiment_label=str(payload.get("experiment_label", "")),
            trial_id=str(payload.get("trial_id", "")),
            operator_name=str(payload.get("operator_name", "")),
            notes=str(payload.get("notes", "")),
            tags=tuple(payload.get("tags", [])),
        )

    @staticmethod
    def _review_state_from_dict(payload: dict[str, object] | None) -> SessionReviewState:
        if not payload:
            return SessionReviewState()
        return SessionReviewState(
            last_frame_index=int(payload.get("last_frame_index", 0)),
            selected_window_start=int(payload["selected_window_start"]) if payload.get("selected_window_start") is not None else None,
            selected_window_end=int(payload["selected_window_end"]) if payload.get("selected_window_end") is not None else None,
            dismissed_review_frames=tuple(int(frame) for frame in payload.get("dismissed_review_frames", [])),
        )

    @staticmethod
    def _export_preferences_from_dict(payload: dict[str, object] | None) -> ExportPreferences:
        if not payload:
            return ExportPreferences()
        return ExportPreferences(
            include_overlay=bool(payload.get("include_overlay", True)),
            include_debug_tracking=bool(payload.get("include_debug_tracking", False)),
            include_plots=bool(payload.get("include_plots", True)),
            report_template=str(payload.get("report_template", "research")),
        )

    @staticmethod
    def _provenance_from_dict(payload: dict[str, object] | None, video_path: str) -> ProvenanceMetadata:
        if not payload:
            return ProvenanceMetadata(video_path_snapshot=video_path)
        return ProvenanceMetadata(
            app_version=str(payload.get("app_version", "0.1.0")),
            source=str(payload.get("source", "tracker_ai")),
            video_path_snapshot=str(payload.get("video_path_snapshot", video_path)),
        )
