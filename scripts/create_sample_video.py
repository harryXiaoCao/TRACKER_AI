from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def build_video(output_path: Path, *, width: int = 960, height: int = 540, fps: int = 60, seconds: int = 6) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(output_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    total_frames = fps * seconds

    gravity = 0.22
    vx = 6.0
    vy = -7.0
    x = 120.0
    y = float(height - 120)
    radius = 20

    for _ in range(total_frames):
        frame = np.full((height, width, 3), (244, 240, 232), dtype=np.uint8)
        cv2.line(frame, (90, height - 70), (width - 80, height - 70), (60, 74, 87), 3)
        cv2.line(frame, (90, height - 70), (90, 80), (60, 74, 87), 3)

        x += vx
        y += vy
        vy += gravity

        if y >= height - 70 - radius:
            y = height - 70 - radius
            vy *= -0.92

        if x >= width - 120:
            x = width - 120
            vx *= -0.98

        cv2.circle(frame, (int(x), int(y)), radius, (33, 90, 166), -1)
        cv2.circle(frame, (int(x), int(y)), radius, (10, 28, 56), 2)
        cv2.putText(frame, "Tracker AI sample", (48, 52), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (24, 58, 82), 2)
        cv2.putText(frame, "Reference: 0.50 m", (48, 92), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (24, 58, 82), 2)
        cv2.line(frame, (120, height - 40), (320, height - 40), (184, 92, 56), 5)
        cv2.putText(frame, "0.50 m", (180, height - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (184, 92, 56), 2)
        writer.write(frame)

    writer.release()
    return output_path


def _draw_lab_background(frame: np.ndarray, *, jitter_x: int = 0, jitter_y: int = 0) -> None:
    height, width = frame.shape[:2]
    frame[:] = (242, 239, 233)
    cv2.rectangle(frame, (40 + jitter_x, 50 + jitter_y), (width - 40 + jitter_x, height - 40 + jitter_y), (250, 247, 242), -1)
    cv2.line(frame, (70 + jitter_x, height - 65 + jitter_y), (width - 70 + jitter_x, height - 65 + jitter_y), (82, 87, 91), 4)
    cv2.line(frame, (85 + jitter_x, 80 + jitter_y), (85 + jitter_x, height - 65 + jitter_y), (82, 87, 91), 3)
    cv2.line(frame, (145 + jitter_x, 60 + jitter_y), (145 + jitter_x, height - 80 + jitter_y), (198, 203, 208), 2)
    cv2.line(frame, (0, 145 + jitter_y), (width, 145 + jitter_y), (228, 223, 214), 2)
    cv2.putText(frame, "Tracker AI benchmark", (54 + jitter_x, 44 + jitter_y), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (44, 64, 84), 2)
    cv2.line(frame, (120 + jitter_x, height - 28 + jitter_y), (320 + jitter_x, height - 28 + jitter_y), (177, 98, 54), 5)
    cv2.putText(frame, "0.50 m", (190 + jitter_x, height - 6 + jitter_y), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (177, 98, 54), 2)


def _draw_marker_object(frame: np.ndarray, center: tuple[float, float], radius: int, *, blur: bool = False, scale_y: float = 1.0) -> tuple[float, float, float, float]:
    cx, cy = int(round(center[0])), int(round(center[1]))
    axes = (radius, max(10, int(round(radius * scale_y))))
    cv2.ellipse(frame, (cx, cy), axes, 0, 0, 360, (44, 108, 192), -1)
    cv2.circle(frame, (cx, cy), max(5, radius // 2), (12, 184, 111), -1)
    cv2.circle(frame, (cx, cy), max(5, radius // 3), (240, 240, 242), -1)
    cv2.ellipse(frame, (cx, cy), axes, 0, 0, 360, (16, 34, 69), 2)
    if blur:
        frame[:] = cv2.GaussianBlur(frame, (7, 7), 0)
    return (cx - axes[0], cy - axes[1], axes[0] * 2, axes[1] * 2)


def _annotation_rows(positions: list[tuple[int, tuple[float, float], tuple[float, float, float, float]]], *, step: int = 5) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for frame_index, center, bbox in positions:
        if frame_index % step != 0:
            continue
        rows.append(
            {
                "frame_index": frame_index,
                "centroid_x_px": round(center[0], 3),
                "centroid_y_px": round(center[1], 3),
                "bbox": [round(value, 3) for value in bbox],
            }
        )
    return rows


def build_benchmark_suite(output_dir: Path, manifest_path: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    scenarios: list[dict[str, object]] = []

    def _writer(path: Path):
        return cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 30.0, (720, 420))

    # Scenario 1: blur + glare.
    path = output_dir / "marker_blur_glare.mp4"
    positions: list[tuple[int, tuple[float, float], tuple[float, float, float, float]]] = []
    writer = _writer(path)
    x, y = 120.0, 290.0
    vx, vy = 4.8, -2.7
    for frame_index in range(90):
        frame = np.zeros((420, 720, 3), dtype=np.uint8)
        _draw_lab_background(frame)
        x += vx
        y += vy
        vy += 0.10
        if y >= 315:
            y = 315
            vy *= -0.88
        blur = frame_index in {22, 23, 24, 48, 49, 50}
        bbox = _draw_marker_object(frame, (x, y), 20, blur=blur, scale_y=1.0)
        if 38 <= frame_index <= 45:
            overlay = frame.copy()
            cv2.circle(overlay, (int(x + 34), int(y - 26)), 32, (255, 255, 255), -1)
            frame[:] = cv2.addWeighted(overlay, 0.22, frame, 0.78, 0.0)
        if 58 <= frame_index <= 66:
            frame[:] = cv2.convertScaleAbs(frame, alpha=1.07, beta=18)
        positions.append((frame_index, (x, y), bbox))
        writer.write(frame)
    writer.release()
    scenarios.append(
        {
            "name": "marker_blur_glare",
            "video_path": str(path.relative_to(manifest_path.parent)),
            "start_frame": 0,
            "initial_bbox": [positions[0][2][0], positions[0][2][1], positions[0][2][2], positions[0][2][3]],
            "tags": ["blur", "glare", "illumination_shift", "marker"],
            "annotations": _annotation_rows(positions),
        }
    )

    # Scenario 2: occlusion + disappearance + re-entry.
    path = output_dir / "marker_occlusion_reentry.mp4"
    positions = []
    writer = _writer(path)
    x, y = 118.0, 268.0
    vx, vy = 4.2, -1.3
    for frame_index in range(96):
        frame = np.zeros((420, 720, 3), dtype=np.uint8)
        _draw_lab_background(frame)
        x += vx
        y += vy
        if frame_index > 24:
            vy += 0.09
        if y >= 308:
            y = 308
            vy *= -0.84
        visible = not (46 <= frame_index <= 52)
        bbox = (x - 20, y - 20, 40, 40)
        if visible:
            bbox = _draw_marker_object(frame, (x, y), 20)
        if 34 <= frame_index <= 57:
            cv2.rectangle(frame, (340, 125), (388, 360), (212, 216, 224), -1)
            cv2.rectangle(frame, (340, 125), (388, 360), (151, 158, 170), 2)
        positions.append((frame_index, (x, y), bbox))
        writer.write(frame)
    writer.release()
    scenarios.append(
        {
            "name": "marker_occlusion_reentry",
            "video_path": str(path.relative_to(manifest_path.parent)),
            "start_frame": 0,
            "initial_bbox": [positions[0][2][0], positions[0][2][1], positions[0][2][2], positions[0][2][3]],
            "tags": ["occlusion", "disappearance", "marker"],
            "annotations": _annotation_rows(positions),
        }
    )

    # Scenario 3: camera jitter + distractor + scale drift.
    path = output_dir / "marker_jitter_distractor_scale.mp4"
    positions = []
    writer = _writer(path)
    x, y = 110.0, 282.0
    vx, vy = 5.1, -2.2
    distractor_x = 480
    distractor_y = 250
    for frame_index in range(100):
        jitter_x = int(round(np.sin(frame_index / 6.0) * 3.0))
        jitter_y = int(round(np.cos(frame_index / 7.0) * 2.0))
        frame = np.zeros((420, 720, 3), dtype=np.uint8)
        _draw_lab_background(frame, jitter_x=jitter_x, jitter_y=jitter_y)
        x += vx
        y += vy
        vy += 0.07
        if y >= 308:
            y = 308
            vy *= -0.85
        scale_y = 1.0 + 0.25 * (frame_index / 99.0)
        bbox = _draw_marker_object(frame, (x + jitter_x, y + jitter_y), 19, scale_y=scale_y)
        cv2.ellipse(frame, (distractor_x + jitter_x, distractor_y + jitter_y), (21, 21), 0, 0, 360, (46, 106, 190), -1)
        cv2.circle(frame, (distractor_x + jitter_x, distractor_y + jitter_y), 6, (235, 235, 235), -1)
        cv2.ellipse(frame, (distractor_x + jitter_x, distractor_y + jitter_y), (21, 21), 0, 0, 360, (14, 34, 72), 2)
        positions.append((frame_index, (x + jitter_x, y + jitter_y), bbox))
        writer.write(frame)
    writer.release()
    scenarios.append(
        {
            "name": "marker_jitter_distractor_scale",
            "video_path": str(path.relative_to(manifest_path.parent)),
            "start_frame": 0,
            "initial_bbox": [positions[0][2][0], positions[0][2][1], positions[0][2][2], positions[0][2][3]],
            "tags": ["camera_jitter", "distractor", "scale_drift", "marker"],
            "annotations": _annotation_rows(positions),
        }
    )

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps({"clips": scenarios}, indent=2), encoding="utf-8")
    return manifest_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate sample and benchmark videos for Tracker AI.")
    parser.add_argument("--output", default="sample_data/projectile_sample.mp4")
    parser.add_argument("--benchmark-suite", action="store_true", help="Generate the benchmark suite and manifest.")
    parser.add_argument("--benchmark-dir", default="sample_data/benchmarks")
    parser.add_argument("--benchmark-manifest", default="sample_data/benchmark_manifest.json")
    args = parser.parse_args()

    if args.benchmark_suite:
        path = build_benchmark_suite(Path(args.benchmark_dir), Path(args.benchmark_manifest))
    else:
        path = build_video(Path(args.output))
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
