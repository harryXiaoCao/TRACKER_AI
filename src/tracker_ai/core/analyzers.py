from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import numpy as np

from .analysis import AnalysisResult
from .calibration import CalibrationProfile
from .tracking import PairwiseMetricResult, TrackResult


@dataclass(frozen=True)
class AnalyzerMetric:
    key: str
    value: float
    unit_label: str
    note: str = ""


@dataclass(frozen=True)
class AnalyzerResult:
    analyzer_id: str
    title: str
    confidence: float
    metrics: tuple[AnalyzerMetric, ...]
    notes: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, object]:
        return {
            "analyzer_id": self.analyzer_id,
            "title": self.title,
            "confidence": self.confidence,
            "metrics": [
                {"key": metric.key, "value": metric.value, "unit_label": metric.unit_label, "note": metric.note}
                for metric in self.metrics
            ],
            "notes": list(self.notes),
        }


class ExperimentAnalyzer(Protocol):
    analyzer_id: str
    title: str

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None: ...


def _metric(key: str, value: float, unit_label: str, note: str = "") -> AnalyzerMetric:
    return AnalyzerMetric(key=key, value=float(value), unit_label=unit_label, note=note)


def _first_reliable_index(track_result: TrackResult) -> int:
    for index, observation in enumerate(track_result.observations):
        if not observation.lost and observation.confidence >= 0.35:
            return index
    return 0


def _peak_indices(values: np.ndarray) -> np.ndarray:
    if len(values) < 3:
        return np.array([], dtype=int)
    indices: list[int] = []
    for index in range(1, len(values) - 1):
        if values[index] >= values[index - 1] and values[index] >= values[index + 1]:
            indices.append(index)
    return np.array(indices, dtype=int)


class ProjectileAnalyzer:
    analyzer_id = "projectile"
    title = "Projectile Motion"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        if len(analysis.time_s) < 5 or np.ptp(analysis.y_units) <= calibration.reference_length * 0.1:
            return None
        launch_index = _first_reliable_index(track_result)
        coeffs = np.polyfit(analysis.time_s, analysis.y_units, 2)
        gravity_estimate = float(2.0 * coeffs[0])
        launch_angle = float(np.degrees(np.arctan2(analysis.y_velocity[launch_index], analysis.x_velocity[launch_index] + 1e-9)))
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=self.title,
            confidence=float(np.mean(analysis.scientific_confidence)) if len(analysis.scientific_confidence) else 0.0,
            metrics=(
                _metric("launch_angle_deg", launch_angle, "deg"),
                _metric("gravity_fit", gravity_estimate, f"{calibration.unit_label}/s^2"),
                _metric("flight_time", analysis.time_s[-1] - analysis.time_s[0], "s"),
            ),
            notes=("Estimated from a quadratic fit of vertical displacement over time.",),
        )


class PendulumAnalyzer:
    analyzer_id = "pendulum"
    title = "Pendulum Motion"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        peaks = _peak_indices(np.abs(analysis.x_units - np.mean(analysis.x_units)))
        if len(peaks) < 2:
            return None
        periods = np.diff(analysis.time_s[peaks]) * 2.0
        if not len(periods):
            return None
        amplitudes = np.abs(analysis.x_units[peaks] - np.mean(analysis.x_units))
        damping_ratio = float(np.log(max(amplitudes[0], 1e-9) / max(amplitudes[-1], 1e-9)) / max(len(amplitudes) - 1, 1))
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=self.title,
            confidence=float(np.mean(analysis.scientific_confidence)),
            metrics=(
                _metric("period", float(np.mean(periods)), "s"),
                _metric("damping_ratio", max(damping_ratio, 0.0), ""),
                _metric("peak_angle", float(np.max(np.abs(analysis.angle_deg))), "deg"),
            ),
            notes=("Detected from repeated lateral turning points in the track.",),
        )


class CircularMotionAnalyzer:
    analyzer_id = "circular"
    title = "Circular Motion"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        if len(analysis.x_units) < 5:
            return None
        center_x = float(np.mean(analysis.x_units))
        center_y = float(np.mean(analysis.y_units))
        radius = np.sqrt((analysis.x_units - center_x) ** 2 + (analysis.y_units - center_y) ** 2)
        if float(np.mean(radius)) <= 1e-6:
            return None
        circularity = 1.0 - min(float(np.std(radius) / max(np.mean(radius), 1e-6)), 1.0)
        if circularity < 0.55:
            return None
        angular_velocity = np.gradient(np.unwrap(np.radians(analysis.angle_deg)), analysis.time_s)
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=self.title,
            confidence=min(float(np.mean(analysis.scientific_confidence)), circularity),
            metrics=(
                _metric("mean_radius", float(np.mean(radius)), calibration.unit_label),
                _metric("angular_velocity", float(np.mean(np.abs(angular_velocity))), "rad/s"),
                _metric("circularity", circularity, ""),
            ),
            notes=("Center estimated from the mean track position.",),
        )


class InclineAnalyzer:
    analyzer_id = "incline"
    title = "Incline Motion"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        if len(analysis.x_units) < 3 or np.ptp(analysis.x_units) <= 1e-6:
            return None
        slope, intercept = np.polyfit(analysis.x_units, analysis.y_units, 1)
        residual = analysis.y_units - (slope * analysis.x_units + intercept)
        if float(np.std(residual)) > max(calibration.reference_length * 0.15, 1e-6):
            return None
        track_angle = float(np.degrees(np.arctan(slope)))
        along_track_acc = float(np.mean(np.cos(np.arctan(slope)) * analysis.x_acceleration + np.sin(np.arctan(slope)) * analysis.y_acceleration))
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=self.title,
            confidence=float(np.mean(analysis.scientific_confidence)),
            metrics=(
                _metric("track_angle_deg", track_angle, "deg"),
                _metric("along_track_acceleration", along_track_acc, f"{calibration.unit_label}/s^2"),
                _metric("line_residual_std", float(np.std(residual)), calibration.unit_label),
            ),
            notes=("Estimated from a line fit through the smoothed path.",),
        )


class SpringAnalyzer:
    analyzer_id = "spring"
    title = "Spring Oscillation"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        dominant = analysis.x_units if np.ptp(analysis.x_units) >= np.ptp(analysis.y_units) else analysis.y_units
        peaks = _peak_indices(np.abs(dominant - np.mean(dominant)))
        if len(peaks) < 3:
            return None
        periods = np.diff(analysis.time_s[peaks]) * 2.0
        if not len(periods):
            return None
        amplitudes = np.abs(dominant[peaks] - np.mean(dominant))
        damping = float(np.log(max(amplitudes[0], 1e-9) / max(amplitudes[-1], 1e-9)) / max(len(amplitudes) - 1, 1))
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=self.title,
            confidence=float(np.mean(analysis.scientific_confidence)),
            metrics=(
                _metric("period", float(np.mean(periods)), "s"),
                _metric("frequency", 1.0 / max(float(np.mean(periods)), 1e-9), "Hz"),
                _metric("damping_ratio", max(damping, 0.0), ""),
            ),
            notes=("Dominant oscillation axis selected automatically from the larger path span.",),
        )


class CollisionAnalyzer:
    analyzer_id = "collision"
    title = "Collision Pair"

    def analyze(
        self,
        analysis: AnalysisResult,
        track_result: TrackResult,
        calibration: CalibrationProfile,
        *,
        pairwise_metrics: list[PairwiseMetricResult] | None = None,
    ) -> AnalyzerResult | None:
        if not pairwise_metrics:
            return None
        matching = [metric for metric in pairwise_metrics if track_result.track_id in {metric.primary_track_id, metric.secondary_track_id}]
        if not matching:
            return None
        metric = min(matching, key=lambda item: item.minimum_separation)
        if metric.collision_frame is None:
            return None
        samples = metric.samples
        collision_index = next((index for index, sample in enumerate(samples) if sample.frame_index == metric.collision_frame), None)
        if collision_index is None or collision_index == 0 or collision_index >= len(samples) - 1:
            restitution = metric.peak_relative_speed
        else:
            pre_speed = float(np.mean([sample.relative_speed_units_s for sample in samples[max(0, collision_index - 2) : collision_index]]))
            post_speed = float(np.mean([sample.relative_speed_units_s for sample in samples[collision_index + 1 : min(len(samples), collision_index + 3)]]))
            restitution = post_speed / max(pre_speed, 1e-9)
        other_track = metric.secondary_track_id if metric.primary_track_id == track_result.track_id else metric.primary_track_id
        return AnalyzerResult(
            analyzer_id=self.analyzer_id,
            title=f"{self.title}: {track_result.track_id} vs {other_track}",
            confidence=float(np.mean(analysis.scientific_confidence)),
            metrics=(
                _metric("minimum_separation", metric.minimum_separation, calibration.unit_label),
                _metric("peak_relative_speed", metric.peak_relative_speed, f"{calibration.unit_label}/s"),
                _metric("coefficient_of_restitution", restitution, ""),
            ),
            notes=(f"Collision frame detected at {metric.collision_frame}.",),
        )


BUILTIN_ANALYZERS: tuple[ExperimentAnalyzer, ...] = (
    ProjectileAnalyzer(),
    PendulumAnalyzer(),
    CircularMotionAnalyzer(),
    InclineAnalyzer(),
    SpringAnalyzer(),
    CollisionAnalyzer(),
)


def run_builtin_analyzers(
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    *,
    pairwise_metrics: list[PairwiseMetricResult] | None = None,
) -> tuple[AnalyzerResult, ...]:
    results: list[AnalyzerResult] = []
    for analyzer in BUILTIN_ANALYZERS:
        result = analyzer.analyze(analysis, track_result, calibration, pairwise_metrics=pairwise_metrics)
        if result is not None and result.metrics:
            results.append(result)
    return tuple(results)
