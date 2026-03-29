from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import numpy as np

from .tracking import BBox, TrackResult


@dataclass(frozen=True)
class BenchmarkAnnotation:
    frame_index: int
    centroid_x_px: float
    centroid_y_px: float
    bbox: BBox


@dataclass(frozen=True)
class BenchmarkClip:
    name: str
    video_path: str
    start_frame: int
    initial_bbox: BBox
    tags: tuple[str, ...]
    annotations: tuple[BenchmarkAnnotation, ...]


@dataclass(frozen=True)
class BenchmarkMetrics:
    clip_name: str
    annotated_frame_count: int
    median_center_error_px: float
    p95_center_error_px: float
    mean_iou: float
    lost_frame_rate: float
    reacquisition_latency_frames: int


@dataclass(frozen=True)
class BenchmarkSuiteMetrics:
    clip_metrics: tuple[BenchmarkMetrics, ...]
    median_center_error_px: float
    p95_center_error_px: float
    mean_iou: float
    lost_frame_rate: float
    max_reacquisition_latency_frames: int


def _iou(a: BBox, b: BBox) -> float:
    ax1, ay1 = a.x, a.y
    ax2, ay2 = a.x + a.width, a.y + a.height
    bx1, by1 = b.x, b.y
    bx2, by2 = b.x + b.width, b.y + b.height
    inter_x1 = max(ax1, bx1)
    inter_y1 = max(ay1, by1)
    inter_x2 = min(ax2, bx2)
    inter_y2 = min(ay2, by2)
    inter_w = max(0.0, inter_x2 - inter_x1)
    inter_h = max(0.0, inter_y2 - inter_y1)
    inter_area = inter_w * inter_h
    union_area = a.area() + b.area() - inter_area
    if union_area <= 0:
        return 0.0
    return float(inter_area / union_area)


def load_benchmark_manifest(path: str | Path) -> list[BenchmarkClip]:
    manifest_path = Path(path)
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    clips: list[BenchmarkClip] = []
    for item in payload["clips"]:
        video_path = Path(item["video_path"])
        if not video_path.is_absolute():
            video_path = (manifest_path.parent / video_path).resolve()
        annotations = tuple(
            BenchmarkAnnotation(
                frame_index=int(annotation["frame_index"]),
                centroid_x_px=float(annotation["centroid_x_px"]),
                centroid_y_px=float(annotation["centroid_y_px"]),
                bbox=BBox(
                    x=float(annotation["bbox"][0]),
                    y=float(annotation["bbox"][1]),
                    width=float(annotation["bbox"][2]),
                    height=float(annotation["bbox"][3]),
                ),
            )
            for annotation in item["annotations"]
        )
        clips.append(
            BenchmarkClip(
                name=item["name"],
                video_path=str(video_path),
                start_frame=int(item.get("start_frame", 0)),
                initial_bbox=BBox(*item["initial_bbox"]),
                tags=tuple(item.get("tags", [])),
                annotations=annotations,
            )
        )
    return clips


def evaluate_track_against_clip(track_result: TrackResult, clip: BenchmarkClip) -> BenchmarkMetrics:
    observation_by_frame = track_result.observation_by_frame()
    center_errors: list[float] = []
    ious: list[float] = []
    lost_frames = 0
    annotated_indices: list[int] = []

    for annotation in clip.annotations:
        observation = observation_by_frame.get(annotation.frame_index)
        if observation is None:
            continue
        annotated_indices.append(annotation.frame_index)
        center_errors.append(
            float(
                np.hypot(
                    observation.centroid_x_px - annotation.centroid_x_px,
                    observation.centroid_y_px - annotation.centroid_y_px,
                )
            )
        )
        ious.append(_iou(observation.bbox, annotation.bbox))
        if observation.lost:
            lost_frames += 1

    reacquisition_latency = 0
    if annotated_indices:
        sorted_frames = sorted(annotated_indices)
        lost_start: int | None = None
        for frame_index in range(sorted_frames[0], sorted_frames[-1] + 1):
            observation = observation_by_frame.get(frame_index)
            if observation is None:
                continue
            if observation.lost and lost_start is None:
                lost_start = frame_index
            elif lost_start is not None and not observation.lost:
                reacquisition_latency = max(reacquisition_latency, frame_index - lost_start)
                lost_start = None

    if not center_errors:
        raise ValueError(f"No overlapping annotations were found for benchmark clip '{clip.name}'")

    return BenchmarkMetrics(
        clip_name=clip.name,
        annotated_frame_count=len(center_errors),
        median_center_error_px=float(np.median(center_errors)),
        p95_center_error_px=float(np.percentile(center_errors, 95)),
        mean_iou=float(np.mean(ious)),
        lost_frame_rate=float(lost_frames / len(center_errors)),
        reacquisition_latency_frames=int(reacquisition_latency),
    )


def evaluate_benchmark_suite(manifest_path: str | Path, track_runner) -> BenchmarkSuiteMetrics:
    clips = load_benchmark_manifest(manifest_path)
    clip_metrics = tuple(track_runner(clip) for clip in clips)
    return BenchmarkSuiteMetrics(
        clip_metrics=clip_metrics,
        median_center_error_px=float(np.median([metric.median_center_error_px for metric in clip_metrics])),
        p95_center_error_px=float(np.max([metric.p95_center_error_px for metric in clip_metrics])),
        mean_iou=float(np.mean([metric.mean_iou for metric in clip_metrics])),
        lost_frame_rate=float(np.mean([metric.lost_frame_rate for metric in clip_metrics])),
        max_reacquisition_latency_frames=max(metric.reacquisition_latency_frames for metric in clip_metrics),
    )
