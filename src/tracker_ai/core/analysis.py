from __future__ import annotations

import contextlib
from dataclasses import dataclass, field
import io

import numpy as np

with contextlib.redirect_stderr(io.StringIO()):
    try:
        from scipy.signal import savgol_filter as _savgol_filter
    except Exception:  # pragma: no cover - environment dependent
        _savgol_filter = None


def _polyfit_smooth(values: np.ndarray, window: int, polyorder: int) -> np.ndarray:
    half_window = window // 2
    xs = np.arange(len(values), dtype=float)
    smoothed = np.empty_like(values, dtype=float)
    for idx in range(len(values)):
        start = max(0, idx - half_window)
        end = min(len(values), idx + half_window + 1)
        local_x = xs[start:end]
        local_y = values[start:end]
        local_order = min(polyorder, len(local_x) - 1)
        if local_order <= 0:
            smoothed[idx] = float(np.mean(local_y))
            continue
        coeffs = np.polyfit(local_x, local_y, local_order)
        smoothed[idx] = float(np.polyval(coeffs, xs[idx]))
    return smoothed

from .calibration import CalibrationProfile
from .tracking import TrackResult


@dataclass(frozen=True)
class AnalysisConfig:
    smoothing_method: str = "savitzky_golay"
    smoothing_window: int = 7
    smoothing_polyorder: int = 2


@dataclass(frozen=True)
class AnalysisEvent:
    name: str
    frame_index: int
    time_s: float
    value: float
    unit_label: str
    axis: str = ""
    note: str = ""
    origin: str = "derived"


@dataclass(frozen=True)
class AnalysisWindowSummary:
    start_frame: int
    end_frame: int
    duration_s: float
    displacement: float
    mean_speed: float
    max_speed: float
    max_acceleration: float


@dataclass(frozen=True)
class AnalysisResult:
    time_s: np.ndarray
    x_px: np.ndarray
    y_px: np.ndarray
    raw_x_units: np.ndarray
    raw_y_units: np.ndarray
    x_units: np.ndarray
    y_units: np.ndarray
    x_velocity: np.ndarray
    y_velocity: np.ndarray
    x_acceleration: np.ndarray
    y_acceleration: np.ndarray
    speed: np.ndarray
    acceleration_magnitude: np.ndarray
    angle_deg: np.ndarray
    confidence: np.ndarray
    scientific_confidence: np.ndarray
    position_uncertainty: np.ndarray
    velocity_uncertainty: np.ndarray
    acceleration_uncertainty: np.ndarray
    events: tuple[AnalysisEvent, ...] = ()
    selected_window: AnalysisWindowSummary | None = None

    def to_rows(self) -> list[dict[str, float | str]]:
        rows: list[dict[str, float]] = []
        for idx in range(len(self.time_s)):
            rows.append(
                {
                    "frame_index": float(idx),
                    "time_s": float(self.time_s[idx]),
                    "x_px": float(self.x_px[idx]),
                    "y_px": float(self.y_px[idx]),
                    "raw_x_units": float(self.raw_x_units[idx]),
                    "raw_y_units": float(self.raw_y_units[idx]),
                    "x_units": float(self.x_units[idx]),
                    "y_units": float(self.y_units[idx]),
                    "vx": float(self.x_velocity[idx]),
                    "vy": float(self.y_velocity[idx]),
                    "ax": float(self.x_acceleration[idx]),
                    "ay": float(self.y_acceleration[idx]),
                    "speed": float(self.speed[idx]),
                    "acceleration_magnitude": float(self.acceleration_magnitude[idx]),
                    "angle_deg": float(self.angle_deg[idx]),
                    "confidence": float(self.confidence[idx]),
                    "scientific_confidence": float(self.scientific_confidence[idx]),
                    "position_uncertainty": float(self.position_uncertainty[idx]),
                    "velocity_uncertainty": float(self.velocity_uncertainty[idx]),
                    "acceleration_uncertainty": float(self.acceleration_uncertainty[idx]),
                }
            )
        return rows

    def event_rows(self) -> list[dict[str, float | str]]:
        return [
            {
                "name": event.name,
                "frame_index": event.frame_index,
                "time_s": event.time_s,
                "value": event.value,
                "unit_label": event.unit_label,
                "axis": event.axis,
                "note": event.note,
                "origin": event.origin,
            }
            for event in self.events
        ]

    def measurement_series(self) -> dict[str, np.ndarray]:
        return {
            "x": self.x_units,
            "y": self.y_units,
            "x_raw": self.raw_x_units,
            "y_raw": self.raw_y_units,
            "vx": self.x_velocity,
            "vy": self.y_velocity,
            "speed": self.speed,
            "ax": self.x_acceleration,
            "ay": self.y_acceleration,
            "acceleration_magnitude": self.acceleration_magnitude,
            "angle_deg": self.angle_deg,
            "tracker_confidence": self.confidence,
            "scientific_confidence": self.scientific_confidence,
            "position_uncertainty": self.position_uncertainty,
            "velocity_uncertainty": self.velocity_uncertainty,
            "acceleration_uncertainty": self.acceleration_uncertainty,
        }

    @staticmethod
    def measurement_label(key: str) -> str:
        labels = {
            "x": "X Position",
            "y": "Y Position",
            "x_raw": "Raw X Position",
            "y_raw": "Raw Y Position",
            "vx": "Vx",
            "vy": "Vy",
            "speed": "|v|",
            "ax": "Ax",
            "ay": "Ay",
            "acceleration_magnitude": "|a|",
            "angle_deg": "Angle",
            "tracker_confidence": "Tracker Confidence",
            "scientific_confidence": "Scientific Confidence",
            "position_uncertainty": "Position Uncertainty",
            "velocity_uncertainty": "Velocity Uncertainty",
            "acceleration_uncertainty": "Acceleration Uncertainty",
        }
        return labels.get(key, key.replace("_", " ").title())


def summarize_window(analysis: "AnalysisResult", start_frame: int, end_frame: int) -> AnalysisWindowSummary | None:
    if len(analysis.time_s) == 0:
        return None
    start = max(0, min(start_frame, end_frame))
    end = min(max(start_frame, end_frame), len(analysis.time_s) - 1)
    if end <= start:
        return None
    dx = analysis.x_units[end] - analysis.x_units[start]
    dy = analysis.y_units[end] - analysis.y_units[start]
    displacement = float(np.sqrt(dx**2 + dy**2))
    duration = float(analysis.time_s[end] - analysis.time_s[start])
    return AnalysisWindowSummary(
        start_frame=start,
        end_frame=end,
        duration_s=duration,
        displacement=displacement,
        mean_speed=float(np.mean(analysis.speed[start : end + 1])),
        max_speed=float(np.max(analysis.speed[start : end + 1])),
        max_acceleration=float(np.max(analysis.acceleration_magnitude[start : end + 1])),
    )


def _event_for_peak(values: np.ndarray, time_s: np.ndarray, *, name: str, unit_label: str, axis: str = "", note: str = "") -> AnalysisEvent | None:
    if len(values) == 0:
        return None
    peak_index = int(np.argmax(values))
    return AnalysisEvent(
        name=name,
        frame_index=peak_index,
        time_s=float(time_s[peak_index]),
        value=float(values[peak_index]),
        unit_label=unit_label,
        axis=axis,
        note=note,
    )


def _zero_crossing_events(values: np.ndarray, time_s: np.ndarray, *, name: str, unit_label: str, axis: str) -> list[AnalysisEvent]:
    events: list[AnalysisEvent] = []
    if len(values) < 2:
        return events
    previous = np.sign(values[0])
    for index in range(1, len(values)):
        current = np.sign(values[index])
        if current == 0 or previous == 0:
            previous = current
            continue
        if current != previous:
            events.append(
                AnalysisEvent(
                    name=name,
                    frame_index=index,
                    time_s=float(time_s[index]),
                    value=float(values[index]),
                    unit_label=unit_label,
                    axis=axis,
                    note="Zero crossing",
                )
            )
        previous = current
    return events


def _build_analysis_events(
    time_s: np.ndarray,
    x_units: np.ndarray,
    y_units: np.ndarray,
    x_velocity: np.ndarray,
    y_velocity: np.ndarray,
    speed: np.ndarray,
    acceleration_magnitude: np.ndarray,
    unit_label: str,
) -> tuple[AnalysisEvent, ...]:
    events: list[AnalysisEvent] = []
    for event in (
        _event_for_peak(speed, time_s, name="peak_speed", unit_label=f"{unit_label}/s", note="Maximum speed"),
        _event_for_peak(acceleration_magnitude, time_s, name="peak_acceleration", unit_label=f"{unit_label}/s^2", note="Maximum acceleration"),
        _event_for_peak(y_units, time_s, name="apex", unit_label=unit_label, axis="y", note="Maximum vertical position"),
        _event_for_peak(x_units, time_s, name="furthest_x", unit_label=unit_label, axis="x", note="Maximum horizontal position"),
    ):
        if event is not None:
            events.append(event)
    events.extend(_zero_crossing_events(y_velocity, time_s, name="vy_zero_crossing", unit_label=f"{unit_label}/s", axis="y"))
    events.extend(_zero_crossing_events(x_velocity, time_s, name="vx_zero_crossing", unit_label=f"{unit_label}/s", axis="x"))
    events.sort(key=lambda item: (item.frame_index, item.name))
    return tuple(events)


def _smooth_series(values: np.ndarray, config: AnalysisConfig) -> np.ndarray:
    if len(values) < 5:
        return values.copy()
    window = min(config.smoothing_window, len(values) if len(values) % 2 == 1 else len(values) - 1)
    if window < 3:
        return values.copy()
    polyorder = min(config.smoothing_polyorder, window - 1)
    if config.smoothing_method == "savitzky_golay" and _savgol_filter is not None:
        return _savgol_filter(values, window_length=window, polyorder=polyorder, mode="interp")
    if config.smoothing_method in {"savitzky_golay", "moving_average"}:
        return _polyfit_smooth(values, window, polyorder)
    return values.copy()


def analyze_track(
    track_result: TrackResult,
    calibration: CalibrationProfile,
    config: AnalysisConfig | None = None,
) -> AnalysisResult:
    cfg = config or AnalysisConfig()
    time_s = np.array([o.timestamp for o in track_result.observations], dtype=float)
    x_px = np.array([o.centroid_x_px for o in track_result.observations], dtype=float)
    y_px = np.array([o.centroid_y_px for o in track_result.observations], dtype=float)
    confidence = np.array([o.confidence for o in track_result.observations], dtype=float)

    transformed = np.array([calibration.transform_point(x_value, y_value) for x_value, y_value in zip(x_px, y_px, strict=False)], dtype=float)
    x_units_raw = transformed[:, 0] if len(transformed) else np.array([], dtype=float)
    y_units_raw = transformed[:, 1] if len(transformed) else np.array([], dtype=float)
    x_units = _smooth_series(x_units_raw, cfg)
    y_units = _smooth_series(y_units_raw, cfg)
    position_uncertainty = np.sqrt((x_units - x_units_raw) ** 2 + (y_units - y_units_raw) ** 2)

    if len(time_s) < 2:
        zeros = np.zeros_like(time_s)
        return AnalysisResult(
            time_s=time_s,
            x_px=x_px,
            y_px=y_px,
            raw_x_units=x_units_raw,
            raw_y_units=y_units_raw,
            x_units=x_units,
            y_units=y_units,
            x_velocity=zeros,
            y_velocity=zeros,
            x_acceleration=zeros,
            y_acceleration=zeros,
            speed=zeros,
            acceleration_magnitude=zeros,
            angle_deg=zeros,
            confidence=confidence,
            scientific_confidence=confidence.copy(),
            position_uncertainty=position_uncertainty,
            velocity_uncertainty=zeros,
            acceleration_uncertainty=zeros,
            events=(),
            selected_window=summarize_window(
                AnalysisResult(
                    time_s=time_s,
                    x_px=x_px,
                    y_px=y_px,
                    raw_x_units=x_units_raw,
                    raw_y_units=y_units_raw,
                    x_units=x_units,
                    y_units=y_units,
                    x_velocity=zeros,
                    y_velocity=zeros,
                    x_acceleration=zeros,
                    y_acceleration=zeros,
                    speed=zeros,
                    acceleration_magnitude=zeros,
                    angle_deg=zeros,
                    confidence=confidence,
                    scientific_confidence=confidence.copy(),
                    position_uncertainty=position_uncertainty,
                    velocity_uncertainty=zeros,
                    acceleration_uncertainty=zeros,
                ),
                0,
                max(len(time_s) - 1, 0),
            ),
        )

    x_velocity = np.gradient(x_units, time_s)
    y_velocity = np.gradient(y_units, time_s)
    x_acceleration = np.gradient(x_velocity, time_s)
    y_acceleration = np.gradient(y_velocity, time_s)
    speed = np.sqrt(x_velocity**2 + y_velocity**2)
    acceleration_magnitude = np.sqrt(x_acceleration**2 + y_acceleration**2)
    angle_deg = np.degrees(np.arctan2(y_velocity, x_velocity))
    velocity_uncertainty = np.abs(np.gradient(position_uncertainty, time_s))
    acceleration_uncertainty = np.abs(np.gradient(velocity_uncertainty, time_s))
    scientific_confidence = np.clip(
        confidence
        - np.minimum(position_uncertainty / max(calibration.reference_length, 1e-6), 0.35)
        - 0.10 * np.array([1.0 if observation.corrected else 0.0 for observation in track_result.observations], dtype=float)
        - 0.18 * np.array([1.0 if observation.lost else 0.0 for observation in track_result.observations], dtype=float),
        0.0,
        1.0,
    )
    events = _build_analysis_events(
        time_s,
        x_units,
        y_units,
        x_velocity,
        y_velocity,
        speed,
        acceleration_magnitude,
        calibration.unit_label,
    )

    result = AnalysisResult(
        time_s=time_s,
        x_px=x_px,
        y_px=y_px,
        raw_x_units=x_units_raw,
        raw_y_units=y_units_raw,
        x_units=x_units,
        y_units=y_units,
        x_velocity=x_velocity,
        y_velocity=y_velocity,
        x_acceleration=x_acceleration,
        y_acceleration=y_acceleration,
        speed=speed,
        acceleration_magnitude=acceleration_magnitude,
        angle_deg=angle_deg,
        confidence=confidence,
        scientific_confidence=scientific_confidence,
        position_uncertainty=position_uncertainty,
        velocity_uncertainty=velocity_uncertainty,
        acceleration_uncertainty=acceleration_uncertainty,
        events=events,
    )
    object.__setattr__(result, "selected_window", summarize_window(result, 0, len(time_s) - 1))
    return result
