from __future__ import annotations

from dataclasses import dataclass
from math import cos, hypot, radians, sin

import numpy as np


@dataclass(frozen=True)
class CalibrationProfile:
    reference_length: float
    unit_label: str
    pixel_distance: float
    mode: str = "single_line"
    origin_x_px: float = 0.0
    origin_y_px: float = 0.0
    axis_angle_deg: float = 0.0
    invert_x: bool = False
    invert_y: bool = False
    homography: tuple[float, ...] | None = None
    preset_name: str = ""

    def __post_init__(self) -> None:
        if self.reference_length <= 0:
            raise ValueError("reference_length must be positive")
        if self.pixel_distance <= 0:
            raise ValueError("pixel_distance must be positive")
        if self.homography is not None and len(self.homography) != 9:
            raise ValueError("homography must contain 9 values")

    @property
    def units_per_pixel(self) -> float:
        return self.reference_length / self.pixel_distance

    def pixels_to_units(self, value: float) -> float:
        return value * self.units_per_pixel

    def transform_point(self, x_px: float, y_px: float) -> tuple[float, float]:
        point = np.array([[[float(x_px), float(y_px)]]], dtype=np.float32)
        if self.homography is not None:
            matrix = np.array(self.homography, dtype=np.float32).reshape(3, 3)
            point = np.array(np.squeeze(cv2_perspective_transform(point, matrix)), dtype=np.float32)
        else:
            point = np.array([float(x_px), float(y_px)], dtype=np.float32)

        translated_x = float(point[0] - self.origin_x_px)
        translated_y = float(point[1] - self.origin_y_px)
        theta = radians(self.axis_angle_deg)
        rotated_x = translated_x * cos(theta) + translated_y * sin(theta)
        rotated_y = -translated_x * sin(theta) + translated_y * cos(theta)
        if self.invert_x:
            rotated_x *= -1.0
        if self.invert_y:
            rotated_y *= -1.0
        return rotated_x * self.units_per_pixel, rotated_y * self.units_per_pixel

    @classmethod
    def from_points(
        cls,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        *,
        reference_length: float,
        unit_label: str,
    ) -> "CalibrationProfile":
        pixel_distance = hypot(x2 - x1, y2 - y1)
        return cls(
            reference_length=reference_length,
            unit_label=unit_label,
            pixel_distance=pixel_distance,
            mode="single_line",
            origin_x_px=float(x1),
            origin_y_px=float(y1),
        )

    @classmethod
    def from_axis_points(
        cls,
        origin_x: float,
        origin_y: float,
        axis_x: float,
        axis_y: float,
        *,
        reference_length: float,
        unit_label: str,
        invert_x: bool = False,
        invert_y: bool = False,
    ) -> "CalibrationProfile":
        pixel_distance = hypot(axis_x - origin_x, axis_y - origin_y)
        axis_angle_deg = np.degrees(np.arctan2(axis_y - origin_y, axis_x - origin_x))
        return cls(
            reference_length=reference_length,
            unit_label=unit_label,
            pixel_distance=pixel_distance,
            mode="two_axis",
            origin_x_px=float(origin_x),
            origin_y_px=float(origin_y),
            axis_angle_deg=float(axis_angle_deg),
            invert_x=invert_x,
            invert_y=invert_y,
        )

    @classmethod
    def from_marker_size(
        cls,
        marker_bbox_width_px: float,
        *,
        reference_length: float,
        unit_label: str,
        preset_name: str = "",
    ) -> "CalibrationProfile":
        return cls(
            reference_length=reference_length,
            unit_label=unit_label,
            pixel_distance=float(marker_bbox_width_px),
            mode="marker_size",
            preset_name=preset_name,
        )

    @classmethod
    def from_homography(
        cls,
        homography: list[float] | tuple[float, ...],
        *,
        reference_length: float,
        unit_label: str,
        pixel_distance: float,
        origin_x_px: float = 0.0,
        origin_y_px: float = 0.0,
        preset_name: str = "",
    ) -> "CalibrationProfile":
        return cls(
            reference_length=reference_length,
            unit_label=unit_label,
            pixel_distance=pixel_distance,
            mode="homography",
            origin_x_px=origin_x_px,
            origin_y_px=origin_y_px,
            homography=tuple(float(value) for value in homography),
            preset_name=preset_name,
        )


def cv2_perspective_transform(point: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    homogeneous = np.concatenate([point.reshape(-1, 2), np.ones((point.shape[0], 1), dtype=np.float32)], axis=1)
    transformed = homogeneous @ matrix.T
    transformed_xy = transformed[:, :2] / np.maximum(transformed[:, 2:3], 1e-6)
    return transformed_xy.reshape(point.shape[0], 1, 2)
