from __future__ import annotations

import math

import numpy as np

from tracker_ai.core.analysis import AnalysisConfig, analyze_track
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.tracking import BBox, TrackResult, TrackingObservation


def _synthetic_track() -> TrackResult:
    observations = []
    for frame_index in range(9):
        t = frame_index * 0.1
        x = 10.0 + 5.0 * t
        y = 20.0 + 2.0 * t * t
        observations.append(
            TrackingObservation(
                frame_index=frame_index,
                timestamp=t,
                centroid_x_px=x,
                centroid_y_px=y,
                bbox=BBox(x=x - 2, y=y - 2, width=4, height=4),
                confidence=0.95,
                lost=False,
            )
        )
    return TrackResult(
        observations=observations,
        tracker_name="synthetic",
        average_confidence=0.95,
        start_frame=0,
        end_frame=observations[-1].frame_index,
        initial_bbox=observations[0].bbox,
    )


def test_calibration_from_points():
    calibration = CalibrationProfile.from_points(0, 0, 100, 0, reference_length=2.0, unit_label="m")
    assert math.isclose(calibration.units_per_pixel, 0.02)
    assert math.isclose(calibration.pixels_to_units(50), 1.0)


def test_axis_aligned_calibration_transforms_origin_and_rotation():
    calibration = CalibrationProfile.from_axis_points(10, 10, 10, 110, reference_length=2.0, unit_label="m")
    x_units, y_units = calibration.transform_point(10, 60)
    assert math.isclose(x_units, 1.0, abs_tol=1e-6)
    assert math.isclose(y_units, 0.0, abs_tol=1e-6)


def test_analysis_derivatives_are_reasonable():
    track = _synthetic_track()
    calibration = CalibrationProfile(reference_length=1.0, unit_label="m", pixel_distance=1.0)
    analysis = analyze_track(track, calibration, AnalysisConfig(smoothing_window=5, smoothing_polyorder=2))

    assert np.allclose(analysis.x_velocity[2:-2], 5.0, atol=0.35)
    assert np.allclose(analysis.y_acceleration[2:-2], 4.0, atol=0.6)
    assert len(analysis.to_rows()) == len(track.observations)
    assert len(analysis.events) >= 2
    assert analysis.selected_window is not None
    assert analysis.selected_window.end_frame == len(track.observations) - 1
    assert np.all(analysis.scientific_confidence <= analysis.confidence + 1e-9)
