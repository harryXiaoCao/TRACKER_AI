from __future__ import annotations

from pathlib import Path

from tracker_ai.core.analysis import AnalysisConfig
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.session import EventMarker, ExportPreferences, ExperimentMetadata, ProjectSession, ProvenanceMetadata, SessionReviewState
from tracker_ai.core.tracking import (
    BBox,
    CorrectionAnchor,
    TrackedObject,
    TrackQualityMetadata,
    TrackResult,
    TrackSpan,
    TrackingConfig,
    TrackingProfile,
    TrackingObservation,
    merge_track_results,
)


def _make_track(start_frame: int, corrected: bool = False) -> TrackResult:
    observations = []
    for offset in range(4):
        frame_index = start_frame + offset
        observations.append(
            TrackingObservation(
                frame_index=frame_index,
                timestamp=frame_index / 20.0,
                centroid_x_px=10.0 + frame_index,
                centroid_y_px=30.0,
                bbox=BBox(8.0 + frame_index, 28.0, 6.0, 6.0),
                confidence=0.9,
                lost=False,
                corrected=corrected,
            )
        )
    return TrackResult(
        observations=observations,
        tracker_name="synthetic",
        average_confidence=0.9,
        start_frame=start_frame,
        end_frame=start_frame + len(observations) - 1,
        initial_bbox=observations[0].bbox,
    )


def test_merge_track_results_replaces_tail_with_corrected_segment():
    base = _make_track(0, corrected=False)
    replacement = _make_track(2, corrected=True)

    merged = merge_track_results(base, replacement)

    assert [ob.frame_index for ob in merged.observations] == [0, 1, 2, 3, 4, 5]
    assert any(ob.corrected for ob in merged.observations if ob.frame_index >= 2)
    assert merged.quality.corrected_spans[0].start_frame == 2


def test_project_session_round_trips_corrections_and_quality(tmp_path: Path):
    session = ProjectSession(
        video_path="demo.mp4",
        initial_bbox=BBox(1, 2, 3, 4),
        reference_bbox=BBox(5, 6, 7, 8),
        calibration=CalibrationProfile(reference_length=1.0, unit_label="m", pixel_distance=100.0),
        analysis_config=AnalysisConfig(),
        tracking_config=TrackingConfig(profile=TrackingProfile.MARKER, robust_recovery=True),
        metadata=ExperimentMetadata(
            experiment_label="Pendulum Study",
            trial_id="trial-03",
            operator_name="Ada",
            notes="baseline pass",
            tags=("pendulum", "baseline"),
        ),
        selected_start_frame=12,
        selected_end_frame=40,
        scale_points=(0.0, 0.0, 100.0, 0.0),
        corrections=[CorrectionAnchor(frame_index=15, bbox=BBox(10, 20, 30, 40))],
        track_quality=TrackQualityMetadata(
            lost_spans=[TrackSpan(start_frame=18, end_frame=20, reason="lost_tracking")],
            suspect_spans=[TrackSpan(start_frame=15, end_frame=17, reason="tracking_recovery")],
            corrected_spans=[TrackSpan(start_frame=15, end_frame=30, reason="manual_correction")],
            reacquisition_count=1,
            review_recommended=True,
        ),
        advanced_mode=True,
        review_state=SessionReviewState(last_frame_index=16, selected_window_start=12, selected_window_end=40, dismissed_review_frames=(18,)),
        event_markers=(EventMarker(name="peak_speed", frame_index=14, time_s=0.7, value=2.4, unit_label="m/s"),),
        export_preferences=ExportPreferences(include_overlay=False, include_debug_tracking=True, include_plots=True, report_template="research"),
        provenance=ProvenanceMetadata(app_version="0.1.0", source="tracker_ai", video_path_snapshot="demo.mp4"),
        additional_objects=(TrackedObject(track_id="marker", name="Marker", bbox=BBox(11, 12, 13, 14), kind="secondary"),),
    )

    path = session.save(tmp_path / "session.json")
    loaded = ProjectSession.load(path)

    assert loaded.selected_start_frame == 12
    assert loaded.selected_end_frame == 40
    assert loaded.reference_bbox == BBox(5, 6, 7, 8)
    assert loaded.tracking_config.profile == TrackingProfile.MARKER
    assert loaded.metadata.experiment_label == "Pendulum Study"
    assert loaded.metadata.tags == ("pendulum", "baseline")
    assert loaded.corrections and loaded.corrections[0].frame_index == 15
    assert loaded.track_quality and loaded.track_quality.reacquisition_count == 1
    assert loaded.track_quality and loaded.track_quality.review_recommended is True
    assert loaded.advanced_mode is True
    assert loaded.review_state.last_frame_index == 16
    assert loaded.event_markers and loaded.event_markers[0].name == "peak_speed"
    assert loaded.export_preferences.include_debug_tracking is True
    assert loaded.provenance.video_path_snapshot == "demo.mp4"
    assert loaded.additional_objects and loaded.additional_objects[0].track_id == "marker"
