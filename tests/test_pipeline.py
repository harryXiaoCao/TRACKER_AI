from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from tracker_ai.core.analysis import AnalysisConfig, analyze_track
from tracker_ai.core.calibration import CalibrationProfile
from tracker_ai.core.export import export_analysis_csv, export_result_bundle
from tracker_ai.core.session import EventMarker, ExportPreferences, ExperimentMetadata, ProjectSession, ProvenanceMetadata
from tracker_ai.core.tracking import BBox, run_single_object_tracking
from tracker_ai.core.video import VideoSource


def _make_synthetic_video(path: Path) -> None:
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 20.0, (220, 180))
    for frame_index in range(24):
        frame = np.full((180, 220, 3), 245, dtype=np.uint8)
        x = 20 + frame_index * 4
        y = 70
        cv2.rectangle(frame, (x, y), (x + 24, y + 24), (40, 40, 180), -1)
        writer.write(frame)
    writer.release()


def _make_distractor_video(path: Path) -> None:
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 20.0, (260, 180))
    for frame_index in range(26):
        frame = np.full((180, 260, 3), 240, dtype=np.uint8)
        cv2.rectangle(frame, (165, 72), (189, 96), (45, 45, 175), -1)
        x = 22 + frame_index * 5
        cv2.rectangle(frame, (x, 72), (x + 24, 96), (45, 45, 175), -1)
        writer.write(frame)
    writer.release()


def _make_slope_video(path: Path) -> None:
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 24.0, (320, 220))
    for frame_index in range(36):
        frame = np.full((220, 320, 3), 238, dtype=np.uint8)
        cv2.line(frame, (40, 40), (260, 180), (95, 95, 95), 8)
        cx = 58 + frame_index * 5
        cy = 52 + int(frame_index * 3.2)
        cv2.circle(frame, (cx, cy), 14, (62, 87, 174), -1)
        cv2.circle(frame, (cx, cy), 14, (23, 37, 84), 2)
        writer.write(frame)
    writer.release()


def test_end_to_end_tracking_pipeline(tmp_path: Path):
    video_path = tmp_path / "synthetic.mp4"
    _make_synthetic_video(video_path)

    with VideoSource(video_path) as video:
        track = run_single_object_tracking(video, BBox(20, 70, 24, 24))
        analysis = analyze_track(
            track,
            CalibrationProfile(reference_length=1.0, unit_label="m", pixel_distance=20.0),
        )
        csv_path = export_analysis_csv(analysis, tmp_path / "analysis.csv")

    assert len(track.observations) == 24
    assert track.average_confidence > 0.40
    xs = np.array([obs.centroid_x_px for obs in track.observations])
    assert np.all(np.diff(xs[3:]) >= -1.0)
    assert csv_path.exists()


def test_tracker_prefers_moving_target_over_static_distractor(tmp_path: Path):
    video_path = tmp_path / "distractor.mp4"
    _make_distractor_video(video_path)

    with VideoSource(video_path) as video:
        track = run_single_object_tracking(video, BBox(22, 72, 24, 24))

    xs = np.array([obs.centroid_x_px for obs in track.observations])
    assert xs[-1] - xs[0] > 70
    assert sum(1 for obs in track.observations if obs.lost) < 6


def test_tracker_handles_object_sliding_down_slope(tmp_path: Path):
    video_path = tmp_path / "slope.mp4"
    _make_slope_video(video_path)

    with VideoSource(video_path) as video:
        track = run_single_object_tracking(video, BBox(44, 38, 28, 28))

    xs = np.array([obs.centroid_x_px for obs in track.observations])
    ys = np.array([obs.centroid_y_px for obs in track.observations])
    assert xs[-1] - xs[0] > 120
    assert ys[-1] - ys[0] > 70
    assert sum(1 for obs in track.observations if obs.lost) < 8


def test_tracker_respects_selected_frame_range(tmp_path: Path):
    video_path = tmp_path / "range.mp4"
    _make_synthetic_video(video_path)

    with VideoSource(video_path) as video:
        track = run_single_object_tracking(video, BBox(40, 70, 24, 24), start_frame=5, end_frame=12)

    assert [ob.frame_index for ob in track.observations] == list(range(5, 13))
    assert track.start_frame == 5
    assert track.end_frame == 12


def test_export_bundle_includes_research_outputs(tmp_path: Path):
    video_path = tmp_path / "synthetic.mp4"
    _make_synthetic_video(video_path)

    with VideoSource(video_path) as video:
        track = run_single_object_tracking(video, BBox(20, 70, 24, 24))
        calibration = CalibrationProfile(reference_length=1.0, unit_label="m", pixel_distance=20.0)
        analysis = analyze_track(track, calibration)

    session = ProjectSession(
        video_path=str(video_path),
        initial_bbox=BBox(20, 70, 24, 24),
        calibration=calibration,
        analysis_config=AnalysisConfig(),
        metadata=ExperimentMetadata(experiment_label="Synthetic"),
        track_quality=track.quality,
        event_markers=(
            EventMarker(name="manual_release", frame_index=3, time_s=0.15, value=0.0, unit_label="", note="operator note", origin="manual"),
        ),
        export_preferences=ExportPreferences(include_overlay=False, include_plots=False),
        provenance=ProvenanceMetadata(video_path_snapshot=str(video_path)),
    )
    bundle = export_result_bundle(
        video_path=str(video_path),
        analysis=analysis,
        track_result=track,
        calibration=calibration,
        session=session,
        output_dir=tmp_path / "bundle",
        include_overlay=False,
    )

    assert Path(bundle["raw_track"]).exists()
    assert Path(bundle["smoothed_track"]).exists()
    assert Path(bundle["events"]).exists()
    assert Path(bundle["quality_report"]).exists()
    assert Path(bundle["manifest"]).exists()
    assert Path(bundle["reproduce"]).exists()
    assert Path(bundle["selected_window"]).exists()
    report_text = Path(bundle["report"]).read_text(encoding="utf-8")
    assert "Reproduce This Run" in report_text
    assert "manual_release" in report_text
    events_text = Path(bundle["events"]).read_text(encoding="utf-8")
    assert "origin" in events_text
    assert "manual_release" in events_text
