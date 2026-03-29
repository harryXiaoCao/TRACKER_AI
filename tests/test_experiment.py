from __future__ import annotations

from tracker_ai.core.analysis import AnalysisConfig, analyze_track
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.experiment import apply_reference_motion_correction, build_pairwise_metrics
from tracker_ai.core.tracking import BBox, TrackResult, TrackingObservation


def _make_track(xs: list[float], ys: list[float], *, name: str) -> TrackResult:
    observations: list[TrackingObservation] = []
    for frame_index, (x, y) in enumerate(zip(xs, ys, strict=True)):
        observations.append(
            TrackingObservation(
                frame_index=frame_index,
                timestamp=frame_index / 20.0,
                centroid_x_px=x,
                centroid_y_px=y,
                bbox=BBox(x - 5, y - 5, 10, 10),
                confidence=0.95,
                lost=False,
            )
        )
    return TrackResult(
        observations=observations,
        tracker_name=name,
        average_confidence=0.95,
        start_frame=0,
        end_frame=len(observations) - 1,
        initial_bbox=observations[0].bbox,
    )


def test_reference_motion_correction_removes_shared_drift():
    primary = _make_track([10.0, 12.0, 14.0, 16.0], [40.0, 40.0, 40.0, 40.0], name="primary")
    reference = _make_track([100.0, 102.0, 104.0, 106.0], [20.0, 20.0, 20.0, 20.0], name="reference")

    corrected = apply_reference_motion_correction(primary, reference)
    corrected_xs = [observation.centroid_x_px for observation in corrected.observations]

    assert corrected_xs == [10.0, 10.0, 10.0, 10.0]
    assert all(observation.debug["reference_dx"] >= 0 for observation in corrected.observations[1:])


def test_pairwise_metrics_capture_relative_distance_and_collision():
    primary = _make_track([0.0, 1.0, 2.0, 3.0], [0.0, 0.0, 0.0, 0.0], name="primary")
    primary = TrackResult(**{**primary.__dict__, "track_id": "primary", "track_name": "Primary"})
    secondary = _make_track([3.0, 2.0, 1.0, 0.0], [0.0, 0.0, 0.0, 0.0], name="secondary")
    secondary = TrackResult(**{**secondary.__dict__, "track_id": "secondary", "track_name": "Secondary", "track_kind": "secondary"})
    calibration = CalibrationProfile(reference_length=1.0, unit_label="m", pixel_distance=1.0)
    analyses = {
        "primary": analyze_track(primary, calibration, AnalysisConfig()),
        "secondary": analyze_track(secondary, calibration, AnalysisConfig()),
    }

    metrics = build_pairwise_metrics([primary, secondary], analyses)

    assert len(metrics) == 1
    assert metrics[0].minimum_separation <= 1.0
    assert metrics[0].peak_relative_speed >= 1.0
