from __future__ import annotations

from pathlib import Path

import pytest

from tracker_ai.core.benchmark import evaluate_benchmark_suite, evaluate_track_against_clip, load_benchmark_manifest
from tracker_ai.core.tracking import TrackingConfig, TrackingProfile, run_single_object_tracking
from tracker_ai.core.video import VideoSource


MANIFEST_PATH = Path(__file__).resolve().parents[1] / "sample_data" / "benchmark_manifest.json"


def _run_clip(clip):
    with VideoSource(clip.video_path) as video:
        result = run_single_object_tracking(
            video,
            clip.initial_bbox,
            start_frame=clip.start_frame,
            config=TrackingConfig(profile=TrackingProfile.AUTO, robust_recovery=True, debug_tracking=True),
        )
    return evaluate_track_against_clip(result, clip)


def test_benchmark_manifest_covers_real_video_failure_modes():
    clips = load_benchmark_manifest(MANIFEST_PATH)
    covered_tags = {tag for clip in clips for tag in clip.tags}
    assert {"blur", "glare", "illumination_shift", "occlusion", "disappearance", "camera_jitter", "distractor", "scale_drift"} <= covered_tags


@pytest.mark.parametrize(
    ("clip_name", "max_p95_error", "max_lost_rate", "max_reacquisition_latency"),
    [
        ("marker_blur_glare", 6.0, 0.00, 0),
        ("marker_occlusion_reentry", 18.0, 0.10, 10),
        ("marker_jitter_distractor_scale", 6.0, 0.00, 0),
    ],
)
def test_tracker_handles_benchmark_clip_regressions(clip_name: str, max_p95_error: float, max_lost_rate: float, max_reacquisition_latency: int):
    clips = {clip.name: clip for clip in load_benchmark_manifest(MANIFEST_PATH)}
    metrics = _run_clip(clips[clip_name])

    assert metrics.p95_center_error_px <= max_p95_error
    assert metrics.lost_frame_rate <= max_lost_rate
    assert metrics.reacquisition_latency_frames <= max_reacquisition_latency


def test_tracker_benchmark_suite_metrics_stay_within_acceptance_thresholds():
    suite = evaluate_benchmark_suite(MANIFEST_PATH, _run_clip)

    assert suite.median_center_error_px <= 6.0
    assert suite.p95_center_error_px <= 18.0
    assert suite.lost_frame_rate <= 0.05
    assert suite.max_reacquisition_latency_frames <= 10
