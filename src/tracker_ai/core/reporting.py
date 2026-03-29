from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import numpy as np

from .analysis import AnalysisEvent, AnalysisResult
from .analyzers import AnalyzerResult, run_builtin_analyzers
from .calibration import CalibrationProfile
from .tracking import TrackResult


@dataclass(frozen=True)
class AnalysisSummary:
    frame_count: int
    duration_seconds: float
    start_frame: int
    end_frame: int
    average_confidence: float
    low_confidence_frame_count: int
    suspect_span_count: int
    x_range_units: float
    y_range_units: float
    total_path_length: float
    net_displacement: float
    peak_speed: float
    mean_speed: float
    peak_acceleration: float
    mean_acceleration: float
    lost_frame_count: int
    corrected_frame_count: int
    reacquisition_count: int
    review_recommended: bool
    scientific_confidence_mean: float
    peak_position_uncertainty: float
    peak_velocity_uncertainty: float
    qc_badge: str
    event_count: int
    unit_label: str

    def to_dict(self) -> dict[str, float | int | str]:
        return {
            "frame_count": self.frame_count,
            "duration_seconds": self.duration_seconds,
            "start_frame": self.start_frame,
            "end_frame": self.end_frame,
            "average_confidence": self.average_confidence,
            "low_confidence_frame_count": self.low_confidence_frame_count,
            "suspect_span_count": self.suspect_span_count,
            "x_range_units": self.x_range_units,
            "y_range_units": self.y_range_units,
            "total_path_length": self.total_path_length,
            "net_displacement": self.net_displacement,
            "peak_speed": self.peak_speed,
            "mean_speed": self.mean_speed,
            "peak_acceleration": self.peak_acceleration,
            "mean_acceleration": self.mean_acceleration,
            "lost_frame_count": self.lost_frame_count,
            "corrected_frame_count": self.corrected_frame_count,
            "reacquisition_count": self.reacquisition_count,
            "review_recommended": self.review_recommended,
            "scientific_confidence_mean": self.scientific_confidence_mean,
            "peak_position_uncertainty": self.peak_position_uncertainty,
            "peak_velocity_uncertainty": self.peak_velocity_uncertainty,
            "qc_badge": self.qc_badge,
            "event_count": self.event_count,
            "unit_label": self.unit_label,
        }


@dataclass(frozen=True)
class QualityReport:
    qc_badge: str
    tracker_confidence_mean: float
    scientific_confidence_mean: float
    calibration_confidence: float
    drift_sensitivity: float
    low_confidence_frames: int
    lost_frame_count: int
    corrected_frame_count: int
    interpolated_burden_ratio: float
    peak_position_uncertainty: float
    peak_velocity_uncertainty: float
    review_recommended: bool
    notes: tuple[str, ...]

    def to_dict(self) -> dict[str, float | int | str | bool | list[str]]:
        return {
            "qc_badge": self.qc_badge,
            "tracker_confidence_mean": self.tracker_confidence_mean,
            "scientific_confidence_mean": self.scientific_confidence_mean,
            "calibration_confidence": self.calibration_confidence,
            "drift_sensitivity": self.drift_sensitivity,
            "low_confidence_frames": self.low_confidence_frames,
            "lost_frame_count": self.lost_frame_count,
            "corrected_frame_count": self.corrected_frame_count,
            "interpolated_burden_ratio": self.interpolated_burden_ratio,
            "peak_position_uncertainty": self.peak_position_uncertainty,
            "peak_velocity_uncertainty": self.peak_velocity_uncertainty,
            "review_recommended": self.review_recommended,
            "notes": list(self.notes),
        }


def _qc_badge(analysis: AnalysisResult, track_result: TrackResult, calibration: CalibrationProfile | None = None) -> str:
    if len(track_result.observations) == 0:
        return "review_needed"
    lost_ratio = sum(1 for observation in track_result.observations if observation.lost) / len(track_result.observations)
    if analysis.scientific_confidence.size and float(np.mean(analysis.scientific_confidence)) >= 0.88 and lost_ratio == 0.0:
        return "good_for_publication"
    if lost_ratio > 0.18:
        return "too_much_interpolation"
    calibration_span = max(float(np.ptp(analysis.raw_x_units)) if len(analysis.raw_x_units) else 0.0, 1.0)
    if calibration is not None:
        calibration_span = max(calibration_span, calibration.reference_length)
    if analysis.position_uncertainty.size and float(np.max(analysis.position_uncertainty)) > calibration_span * 0.10:
        return "insufficient_calibration"
    return "review_needed"


def build_quality_report(
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile | None = None,
) -> QualityReport:
    notes: list[str] = []
    if any(observation.lost for observation in track_result.observations):
        notes.append("Lost frames detected; review reacquisition spans before publication use.")
    if any(observation.corrected for observation in track_result.observations):
        notes.append("Manual corrections were applied; keep the session file with the exported run.")
    if any(observation.is_interpolated for observation in track_result.observations):
        notes.append("Short gaps were interpolated; keep raw and smoothed outputs together when reporting results.")
    if analysis.events:
        notes.append(f"{len(analysis.events)} derived events were detected from the smoothed track.")
    if not notes:
        notes.append("No major QC warnings were detected.")
    interpolated_burden_ratio = sum(1 for observation in track_result.observations if observation.lost or observation.corrected or observation.is_interpolated) / max(
        len(track_result.observations), 1
    )
    calibration_confidence = 0.92
    if calibration is not None:
        if calibration.mode in {"single_line", "marker_size"}:
            calibration_confidence = 0.82
        elif calibration.mode == "two_axis":
            calibration_confidence = 0.90
        elif calibration.mode == "homography":
            calibration_confidence = 0.94
    drift_sensitivity = float(np.max(analysis.position_uncertainty) / max(calibration.reference_length if calibration is not None else 1.0, 1e-6)) if len(analysis.position_uncertainty) else 0.0
    return QualityReport(
        qc_badge=_qc_badge(analysis, track_result, calibration),
        tracker_confidence_mean=float(track_result.average_confidence),
        scientific_confidence_mean=float(np.mean(analysis.scientific_confidence)) if len(analysis.scientific_confidence) else 0.0,
        calibration_confidence=float(calibration_confidence),
        drift_sensitivity=float(drift_sensitivity),
        low_confidence_frames=sum(1 for observation in track_result.observations if observation.confidence < 0.35),
        lost_frame_count=sum(1 for observation in track_result.observations if observation.lost),
        corrected_frame_count=sum(1 for observation in track_result.observations if observation.corrected),
        interpolated_burden_ratio=float(interpolated_burden_ratio),
        peak_position_uncertainty=float(np.max(analysis.position_uncertainty)) if len(analysis.position_uncertainty) else 0.0,
        peak_velocity_uncertainty=float(np.max(analysis.velocity_uncertainty)) if len(analysis.velocity_uncertainty) else 0.0,
        review_recommended=track_result.quality.review_recommended,
        notes=tuple(notes),
    )


def build_analysis_summary(
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
) -> AnalysisSummary:
    quality_report = build_quality_report(analysis, track_result, calibration)
    duration_seconds = float(analysis.time_s[-1] - analysis.time_s[0]) if len(analysis.time_s) > 1 else 0.0
    dx = np.diff(analysis.x_units) if len(analysis.x_units) > 1 else np.array([], dtype=float)
    dy = np.diff(analysis.y_units) if len(analysis.y_units) > 1 else np.array([], dtype=float)
    path_segments = np.sqrt(dx**2 + dy**2) if len(dx) else np.array([], dtype=float)
    net_displacement = (
        float(np.sqrt((analysis.x_units[-1] - analysis.x_units[0]) ** 2 + (analysis.y_units[-1] - analysis.y_units[0]) ** 2))
        if len(analysis.x_units) > 1
        else 0.0
    )
    return AnalysisSummary(
        frame_count=len(track_result.observations),
        duration_seconds=duration_seconds,
        start_frame=track_result.start_frame,
        end_frame=track_result.end_frame,
        average_confidence=float(track_result.average_confidence),
        low_confidence_frame_count=sum(1 for observation in track_result.observations if observation.confidence < 0.35),
        suspect_span_count=len(track_result.quality.suspect_spans),
        x_range_units=float(np.max(analysis.x_units) - np.min(analysis.x_units)) if len(analysis.x_units) else 0.0,
        y_range_units=float(np.max(analysis.y_units) - np.min(analysis.y_units)) if len(analysis.y_units) else 0.0,
        total_path_length=float(np.sum(path_segments)) if len(path_segments) else 0.0,
        net_displacement=net_displacement,
        peak_speed=float(np.max(analysis.speed)) if len(analysis.speed) else 0.0,
        mean_speed=float(np.mean(analysis.speed)) if len(analysis.speed) else 0.0,
        peak_acceleration=float(np.max(analysis.acceleration_magnitude)) if len(analysis.acceleration_magnitude) else 0.0,
        mean_acceleration=float(np.mean(analysis.acceleration_magnitude)) if len(analysis.acceleration_magnitude) else 0.0,
        lost_frame_count=sum(1 for observation in track_result.observations if observation.lost),
        corrected_frame_count=sum(1 for observation in track_result.observations if observation.corrected),
        reacquisition_count=track_result.quality.reacquisition_count,
        review_recommended=track_result.quality.review_recommended,
        scientific_confidence_mean=quality_report.scientific_confidence_mean,
        peak_position_uncertainty=quality_report.peak_position_uncertainty,
        peak_velocity_uncertainty=quality_report.peak_velocity_uncertainty,
        qc_badge=quality_report.qc_badge,
        event_count=len(analysis.events),
        unit_label=calibration.unit_label,
    )


def export_summary_json(summary: AnalysisSummary, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary.to_dict(), indent=2), encoding="utf-8")
    return path


def build_analyzer_report(
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    *,
    pairwise_metrics=None,
) -> tuple[AnalyzerResult, ...]:
    return run_builtin_analyzers(analysis, track_result, calibration, pairwise_metrics=pairwise_metrics)
