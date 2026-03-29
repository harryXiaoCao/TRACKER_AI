from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import cv2
import numpy as np


@dataclass(frozen=True)
class VideoMetadata:
    path: str
    fps: float
    frame_count: int
    width: int
    height: int

    @property
    def duration_seconds(self) -> float:
        if self.fps <= 0:
            return 0.0
        return self.frame_count / self.fps


class VideoSource:
    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        self._capture = cv2.VideoCapture(self.path)
        if not self._capture.isOpened():
            raise FileNotFoundError(f"Unable to open video: {self.path}")

        fps = float(self._capture.get(cv2.CAP_PROP_FPS) or 0.0)
        frame_count = int(self._capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        width = int(self._capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(self._capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        self.metadata = VideoMetadata(
            path=self.path,
            fps=fps if fps > 0 else 30.0,
            frame_count=frame_count,
            width=width,
            height=height,
        )

    def __enter__(self) -> "VideoSource":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        if self._capture.isOpened():
            self._capture.release()

    def frame_timestamp(self, frame_index: int) -> float:
        return frame_index / self.metadata.fps

    def read_frame(self, frame_index: int) -> np.ndarray:
        self._capture.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = self._capture.read()
        if not ok or frame is None:
            raise IndexError(f"Unable to read frame {frame_index}")
        return frame

    def iter_frames(
        self,
        start_index: int = 0,
        *,
        end_index: int | None = None,
        step: int = 1,
    ) -> Iterator[tuple[int, np.ndarray]]:
        if step == 0:
            raise ValueError("step must not be 0")
        if end_index is None:
            end_index = self.metadata.frame_count - 1 if step > 0 else 0

        frame_index = start_index
        if step > 0:
            while frame_index <= end_index:
                yield frame_index, self.read_frame(frame_index)
                frame_index += step
            return

        while frame_index >= end_index:
            yield frame_index, self.read_frame(frame_index)
            frame_index += step
