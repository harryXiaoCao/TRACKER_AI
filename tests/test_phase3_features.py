from __future__ import annotations

from pathlib import Path

from tracker_ai.core.analysis import AnalysisConfig, analyze_track
from tracker_ai.core.analyzers import run_builtin_analyzers
from tracker_ai.core.batch import build_batch_aggregate_report, build_batch_trial_report
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.tracking import BBox, TrackResult, TrackingConfig, TrackingObservation
from tracker_ai.core.workspace import ResearchWorkspace, WorkspaceItem


def _make_track_result() -> TrackResult:
    observations = []
    for frame_index in range(10):
        timestamp = frame_index * 0.1
        x = frame_index * 4.0
        y = -(frame_index - 4.5) ** 2 + 24.0
        observations.append(
            TrackingObservation(
                frame_index=frame_index,
                timestamp=timestamp,
                centroid_x_px=x,
                centroid_y_px=y,
                bbox=BBox(x=x - 2.0, y=y - 2.0, width=4.0, height=4.0),
                confidence=0.92,
                lost=False,
            )
        )
    return TrackResult(
        observations=observations,
        tracker_name="synthetic",
        average_confidence=0.92,
        start_frame=0,
        end_frame=9,
        initial_bbox=observations[0].bbox,
        tracking_config=TrackingConfig(),
    )


def test_builtin_analyzers_emit_projectile_metrics() -> None:
    track = _make_track_result()
    calibration = CalibrationProfile.from_points(0.0, 0.0, 10.0, 0.0, reference_length=1.0, unit_label="m")
    analysis = analyze_track(track, calibration, AnalysisConfig(smoothing_window=5, smoothing_polyorder=2))

    analyzer_ids = {result.analyzer_id for result in run_builtin_analyzers(analysis, track, calibration)}

    assert "projectile" in analyzer_ids
    assert len(analysis.angle_deg) == len(track.observations)


def test_batch_aggregate_report_counts_qc_badges() -> None:
    track = _make_track_result()
    calibration = CalibrationProfile.from_points(0.0, 0.0, 10.0, 0.0, reference_length=1.0, unit_label="m")
    analysis = analyze_track(track, calibration)
    trial = build_batch_trial_report(
        trial_id="trial_a",
        video_path="/tmp/example.mp4",
        analysis=analysis,
        track_result=track,
        calibration=calibration,
    )

    report = build_batch_aggregate_report([trial, trial])

    assert report.trial_count == 2
    assert report.qc_badges[trial.qc_badge] == 2


def test_workspace_round_trip(tmp_path: Path) -> None:
    workspace = ResearchWorkspace(
        title="Study Workspace",
        active_video_path="/tmp/video_b.mp4",
        items=(
            WorkspaceItem(label="trial-a", video_path="/tmp/video_a.mp4"),
            WorkspaceItem(label="trial-b", video_path="/tmp/video_b.mp4", session_path="/tmp/video_b.session.json"),
        ),
    )

    saved_path = workspace.save(tmp_path / "workspace.json")
    loaded = ResearchWorkspace.load(saved_path)

    assert loaded.title == "Study Workspace"
    assert loaded.active_video_path == "/tmp/video_b.mp4"
    assert len(loaded.items) == 2
    assert loaded.items[1].session_path.endswith("session.json")
