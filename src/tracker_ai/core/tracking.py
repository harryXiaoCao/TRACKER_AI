from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum

import cv2
import numpy as np

from .video import VideoSource


class TrackingProfile(str, Enum):
    AUTO = "auto"
    MARKER = "marker"
    GENERIC = "generic"
    BRIGHT = "bright"
    DARK = "dark"
    CIRCULAR = "circular"
    ELONGATED = "elongated"


class TrackingState(str, Enum):
    TRACKING = "tracking"
    SUSPECT = "suspect"
    LOST = "lost"
    REACQUIRED = "reacquired"


@dataclass(frozen=True)
class TrackingConfig:
    profile: TrackingProfile = TrackingProfile.AUTO
    robust_recovery: bool = True
    bidirectional_refinement: bool = True
    debug_tracking: bool = False
    search_margin: float = 2.4
    expanded_search_margin: float = 5.5
    scale_factors: tuple[float, ...] = (0.9, 1.0, 1.1)
    detection_threshold: float = 0.50
    low_confidence_threshold: float = 0.36
    reacquire_threshold: float = 0.56
    suspect_after_frames: int = 3
    recovery_after_frames: int = 5
    max_prediction_frames: int = 8
    template_update_rate: float = 0.10
    stable_update_threshold: float = 0.66
    marker_confidence_bias: float = 0.58
    auto_marker_min_ratio: float = 0.12
    interpolate_short_gaps: bool = True
    max_interpolation_gap: int = 3

    @classmethod
    def with_profile(cls, profile: str | TrackingProfile, *, debug_tracking: bool = False, robust_recovery: bool = True) -> "TrackingConfig":
        return cls(
            profile=TrackingProfile(profile),
            debug_tracking=debug_tracking,
            robust_recovery=robust_recovery,
        )


@dataclass(frozen=True)
class BBox:
    x: float
    y: float
    width: float
    height: float

    @property
    def center(self) -> tuple[float, float]:
        return (self.x + self.width / 2.0, self.y + self.height / 2.0)

    def area(self) -> float:
        return float(max(self.width, 0.0) * max(self.height, 0.0))

    def clipped(self, frame_width: int, frame_height: int) -> "BBox":
        x = min(max(self.x, 0.0), max(frame_width - 1.0, 0.0))
        y = min(max(self.y, 0.0), max(frame_height - 1.0, 0.0))
        width = min(self.width, max(frame_width - x, 1.0))
        height = min(self.height, max(frame_height - y, 1.0))
        return BBox(x=x, y=y, width=width, height=height)

    def scaled(self, factor: float, *, frame_width: int, frame_height: int) -> "BBox":
        center_x, center_y = self.center
        width = max(6.0, self.width * factor)
        height = max(6.0, self.height * factor)
        return BBox(center_x - width / 2.0, center_y - height / 2.0, width, height).clipped(frame_width, frame_height)

    def to_int_tuple(self) -> tuple[int, int, int, int]:
        return (
            int(round(self.x)),
            int(round(self.y)),
            max(1, int(round(self.width))),
            max(1, int(round(self.height))),
        )


@dataclass(frozen=True)
class TrackSpan:
    start_frame: int
    end_frame: int
    reason: str


@dataclass(frozen=True)
class CorrectionAnchor:
    frame_index: int
    bbox: BBox
    note: str = "manual_correction"
    track_id: str = "primary"


@dataclass(frozen=True)
class TrackQualityMetadata:
    lost_spans: list[TrackSpan] = field(default_factory=list)
    suspect_spans: list[TrackSpan] = field(default_factory=list)
    corrected_spans: list[TrackSpan] = field(default_factory=list)
    reacquisition_count: int = 0
    review_recommended: bool = False


@dataclass(frozen=True)
class TrackingObservation:
    frame_index: int
    timestamp: float
    centroid_x_px: float
    centroid_y_px: float
    bbox: BBox
    confidence: float
    lost: bool
    corrected: bool = False
    state: str = TrackingState.TRACKING.value
    failure_reason: str | None = None
    debug: dict[str, float | str] = field(default_factory=dict)
    track_id: str = "primary"
    track_name: str = "Primary Object"
    track_kind: str = "primary"
    source: str = "measured"
    is_inferred: bool = False
    is_interpolated: bool = False


@dataclass(frozen=True)
class TrackResult:
    observations: list[TrackingObservation]
    tracker_name: str
    average_confidence: float
    start_frame: int
    end_frame: int
    initial_bbox: BBox
    quality: TrackQualityMetadata = field(default_factory=TrackQualityMetadata)
    tracking_config: TrackingConfig = field(default_factory=TrackingConfig)
    track_id: str = "primary"
    track_name: str = "Primary Object"
    track_kind: str = "primary"

    def observation_by_frame(self) -> dict[int, TrackingObservation]:
        return {observation.frame_index: observation for observation in self.observations}


@dataclass(frozen=True)
class TrackedObject:
    track_id: str
    name: str
    bbox: BBox
    kind: str = "secondary"


@dataclass(frozen=True)
class PairwiseMetricSample:
    frame_index: int
    time_s: float
    distance_units: float
    relative_speed_units_s: float
    relative_dx_units: float
    relative_dy_units: float


@dataclass(frozen=True)
class PairwiseMetricResult:
    primary_track_id: str
    secondary_track_id: str
    samples: list[PairwiseMetricSample]
    minimum_separation: float
    peak_relative_speed: float
    collision_frame: int | None
    center_of_mass_x: list[float] = field(default_factory=list)
    center_of_mass_y: list[float] = field(default_factory=list)


@dataclass(frozen=True)
class _ScoredCandidate:
    bbox: BBox
    score: float
    template_score: float
    marker_score: float
    motion_score: float
    stability_score: float
    size_score: float
    search_mode: str


class RobustHybridTracker:
    def __init__(
        self,
        initial_frame: np.ndarray,
        initial_bbox: BBox,
        *,
        config: TrackingConfig | None = None,
    ) -> None:
        self.config = config or TrackingConfig()
        self.frame_height, self.frame_width = initial_frame.shape[:2]
        self.current_bbox = initial_bbox.clipped(self.frame_width, self.frame_height)
        self.frame_counter = 0
        self.bad_frame_streak = 0
        self.reacquire_streak = 0
        self.reacquisition_count = 0
        self.state = TrackingState.TRACKING
        self.last_failure_reason: str | None = None

        self.reference_frame = initial_frame.copy()
        self.reference_gray = self._preprocess_gray(initial_frame)

        self.long_term_template = self._extract_patch(initial_frame, self.current_bbox)
        if self.long_term_template.size == 0:
            raise ValueError("Initial bbox produced an empty template")
        self.short_term_template = self.long_term_template.copy()
        self.long_term_gray = self._preprocess_gray(self.long_term_template)
        self.short_term_gray = self.long_term_gray.copy()

        self.marker_range, self.marker_reference_ratio = self._build_marker_model(self.long_term_template)
        self.active_profile = self._resolve_profile(self.config.profile)
        self.kalman = self._build_kalman(self.current_bbox.center)

    def _resolve_profile(self, profile: TrackingProfile) -> TrackingProfile:
        if profile != TrackingProfile.AUTO:
            return profile
        marker_ready = self.marker_range is not None and self.marker_reference_ratio >= self.config.auto_marker_min_ratio
        if marker_ready:
            return TrackingProfile.MARKER
        patch = self.long_term_template
        gray = cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY)
        mean_intensity = float(np.mean(gray))
        aspect_ratio = patch.shape[1] / max(patch.shape[0], 1)
        if mean_intensity >= 180:
            return TrackingProfile.BRIGHT
        if mean_intensity <= 75:
            return TrackingProfile.DARK
        if 0.78 <= aspect_ratio <= 1.22:
            return TrackingProfile.CIRCULAR
        if aspect_ratio >= 1.5 or aspect_ratio <= 0.67:
            return TrackingProfile.ELONGATED
        return TrackingProfile.GENERIC

    def _build_kalman(self, center: tuple[float, float]) -> cv2.KalmanFilter:
        kalman = cv2.KalmanFilter(4, 2)
        kalman.transitionMatrix = np.array(
            [[1, 0, 1, 0], [0, 1, 0, 1], [0, 0, 1, 0], [0, 0, 0, 1]],
            dtype=np.float32,
        )
        kalman.measurementMatrix = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=np.float32)
        kalman.processNoiseCov = np.eye(4, dtype=np.float32) * 0.03
        kalman.measurementNoiseCov = np.eye(2, dtype=np.float32) * 0.35
        kalman.errorCovPost = np.eye(4, dtype=np.float32)
        kalman.statePost = np.array([[center[0]], [center[1]], [0.0], [0.0]], dtype=np.float32)
        return kalman

    def _preprocess_gray(self, image: np.ndarray) -> np.ndarray:
        if image.size == 0:
            return np.zeros((1, 1), dtype=np.uint8)
        lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
        l = clahe.apply(l)
        normalized = cv2.cvtColor(cv2.merge((l, a, b)), cv2.COLOR_LAB2BGR)
        gray = cv2.cvtColor(normalized, cv2.COLOR_BGR2GRAY)
        return cv2.GaussianBlur(gray, (5, 5), 0)

    def _extract_patch(self, frame: np.ndarray, bbox: BBox) -> np.ndarray:
        x, y, w, h = bbox.to_int_tuple()
        return frame[y : y + h, x : x + w].copy()

    def _resize_like(self, image: np.ndarray, template: np.ndarray) -> np.ndarray:
        return cv2.resize(image, (template.shape[1], template.shape[0]))

    def _build_marker_model(self, patch: np.ndarray) -> tuple[tuple[np.ndarray, np.ndarray] | None, float]:
        hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)
        saturation_mask = (hsv[:, :, 1] > 45) & (hsv[:, :, 2] > 35)
        if not np.any(saturation_mask):
            saturation_mask = np.ones(hsv.shape[:2], dtype=bool)
        samples = hsv[saturation_mask]
        if len(samples) < 20:
            return None, 0.0

        lower = np.percentile(samples, [10], axis=0)[0]
        upper = np.percentile(samples, [90], axis=0)[0]
        hue_pad = 8.0
        sat_pad = 28.0
        val_pad = 28.0
        low = np.array(
            [
                max(0.0, lower[0] - hue_pad),
                max(20.0, lower[1] - sat_pad),
                max(20.0, lower[2] - val_pad),
            ],
            dtype=np.uint8,
        )
        high = np.array(
            [
                min(179.0, upper[0] + hue_pad),
                min(255.0, upper[1] + sat_pad),
                min(255.0, upper[2] + val_pad),
            ],
            dtype=np.uint8,
        )
        ratio = float(np.count_nonzero(cv2.inRange(hsv, low, high))) / float(hsv.shape[0] * hsv.shape[1])
        return (low, high), ratio

    def _marker_mask(self, image: np.ndarray) -> np.ndarray:
        if self.marker_range is None or image.size == 0:
            return np.zeros(image.shape[:2], dtype=np.uint8)
        low, high = self.marker_range
        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(hsv, low, high)
        kernel = np.ones((3, 3), np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        return mask

    def _predict_bbox(self) -> BBox:
        prediction = self.kalman.predict()
        center_x = float(prediction[0, 0])
        center_y = float(prediction[1, 0])
        return BBox(
            x=center_x - self.current_bbox.width / 2.0,
            y=center_y - self.current_bbox.height / 2.0,
            width=self.current_bbox.width,
            height=self.current_bbox.height,
        ).clipped(self.frame_width, self.frame_height)

    def _search_region(self, frame: np.ndarray, predicted_bbox: BBox, *, mode: str) -> tuple[np.ndarray, int, int]:
        if mode == "full":
            return frame.copy(), 0, 0

        margin = self.config.search_margin if mode == "normal" else self.config.expanded_search_margin
        margin_x = predicted_bbox.width * margin
        margin_y = predicted_bbox.height * margin
        x0 = int(max(0, round(predicted_bbox.x - margin_x)))
        y0 = int(max(0, round(predicted_bbox.y - margin_y)))
        x1 = int(min(self.frame_width, round(predicted_bbox.x + predicted_bbox.width + margin_x)))
        y1 = int(min(self.frame_height, round(predicted_bbox.y + predicted_bbox.height + margin_y)))
        return frame[y0:y1, x0:x1], x0, y0

    def _template_candidates(self, region: np.ndarray, predicted_bbox: BBox, offset_x: int, offset_y: int, *, mode: str) -> list[BBox]:
        if region.size == 0:
            return []
        region_gray = self._preprocess_gray(region)
        candidates: list[BBox] = []
        template_pairs = [(self.short_term_gray, self.current_bbox), (self.long_term_gray, self.current_bbox)]
        for template_gray, _ in template_pairs:
            for scale in self.config.scale_factors:
                scaled_w = max(6, int(round(template_gray.shape[1] * scale)))
                scaled_h = max(6, int(round(template_gray.shape[0] * scale)))
                if region_gray.shape[0] < scaled_h or region_gray.shape[1] < scaled_w:
                    continue
                scaled_template = cv2.resize(template_gray, (scaled_w, scaled_h))
                result = cv2.matchTemplate(region_gray, scaled_template, cv2.TM_CCOEFF_NORMED)
                _, _, _, max_loc = cv2.minMaxLoc(result)
                candidates.append(
                    BBox(
                        x=float(offset_x + max_loc[0]),
                        y=float(offset_y + max_loc[1]),
                        width=float(scaled_w),
                        height=float(scaled_h),
                    ).clipped(self.frame_width, self.frame_height)
                )
        candidates.append(predicted_bbox.clipped(self.frame_width, self.frame_height))
        return candidates

    def _foreground_candidates(self, frame: np.ndarray, predicted_bbox: BBox, *, mode: str) -> list[BBox]:
        region, offset_x, offset_y = self._search_region(frame, predicted_bbox, mode=mode)
        if region.size == 0:
            return []

        candidates: list[BBox] = []

        marker_mask = self._marker_mask(region)
        contours, _ = cv2.findContours(marker_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            if w * h < max(36, predicted_bbox.area() * 0.12):
                continue
            candidates.append(
                BBox(
                    x=float(offset_x + x),
                    y=float(offset_y + y),
                    width=float(max(w, predicted_bbox.width * 0.75)),
                    height=float(max(h, predicted_bbox.height * 0.75)),
                ).clipped(self.frame_width, self.frame_height)
            )

        reference_region, _, _ = self._search_region(self.reference_frame, predicted_bbox, mode=mode)
        if reference_region.size != 0 and reference_region.shape == region.shape:
            current_gray = self._preprocess_gray(region)
            reference_gray = self._preprocess_gray(reference_region)
            diff = cv2.absdiff(current_gray, reference_gray)
            _, motion_mask = cv2.threshold(diff, 18, 255, cv2.THRESH_BINARY)
            kernel = np.ones((3, 3), np.uint8)
            motion_mask = cv2.morphologyEx(motion_mask, cv2.MORPH_OPEN, kernel)
            motion_mask = cv2.dilate(motion_mask, kernel, iterations=2)
            contours, _ = cv2.findContours(motion_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                x, y, w, h = cv2.boundingRect(contour)
                if w * h < max(48, predicted_bbox.area() * 0.10):
                    continue
                candidates.append(
                    BBox(
                        x=float(offset_x + x),
                        y=float(offset_y + y),
                        width=float(max(w, predicted_bbox.width * 0.70)),
                        height=float(max(h, predicted_bbox.height * 0.70)),
                    ).clipped(self.frame_width, self.frame_height)
                )

        return candidates

    def _score_candidate(self, frame: np.ndarray, bbox: BBox, predicted_bbox: BBox, *, search_mode: str) -> _ScoredCandidate:
        patch = self._extract_patch(frame, bbox)
        if patch.size == 0:
            return _ScoredCandidate(bbox, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, search_mode)

        patch_gray = self._preprocess_gray(patch)
        template_score = 0.0
        for template_gray in (self.short_term_gray, self.long_term_gray):
            resized_patch = self._resize_like(patch_gray, template_gray)
            candidate_score = float(cv2.matchTemplate(resized_patch, template_gray, cv2.TM_CCOEFF_NORMED)[0, 0])
            template_score = max(template_score, candidate_score)

        marker_mask = self._marker_mask(patch)
        marker_score = float(np.count_nonzero(marker_mask)) / float(marker_mask.size) if marker_mask.size else 0.0
        if self.marker_reference_ratio > 0:
            marker_score = min(marker_score / max(self.marker_reference_ratio, 1e-6), 1.0)

        x, y, w, h = bbox.to_int_tuple()
        reference_patch = self.reference_frame[y : y + h, x : x + w]
        motion_score = 0.0
        if reference_patch.size != 0 and reference_patch.shape == patch.shape:
            reference_gray = self._preprocess_gray(reference_patch)
            diff = cv2.absdiff(patch_gray, reference_gray)
            motion_score = float(np.mean(diff) / 255.0)

        distance = float(np.linalg.norm(np.array(bbox.center) - np.array(predicted_bbox.center)))
        reference = max(predicted_bbox.width, predicted_bbox.height, 1.0)
        stability_score = max(0.0, 1.0 - (distance / (reference * 2.0)))
        area_ratio = bbox.area() / max(predicted_bbox.area(), 1.0)
        size_score = max(0.0, 1.0 - abs(1.0 - area_ratio))
        brightness_score = float(np.mean(patch_gray) / 255.0)
        aspect_ratio = bbox.width / max(bbox.height, 1e-6)
        circularity_score = max(0.0, 1.0 - abs(1.0 - aspect_ratio))
        elongated_score = min(max(abs(aspect_ratio - 1.0) / 1.5, 0.0), 1.0)

        if self.active_profile == TrackingProfile.MARKER:
            score = (
                0.34 * max(template_score, 0.0)
                + 0.36 * marker_score
                + 0.12 * motion_score
                + 0.10 * stability_score
                + 0.08 * size_score
            )
        elif self.active_profile == TrackingProfile.BRIGHT:
            score = 0.42 * max(template_score, 0.0) + 0.18 * brightness_score + 0.16 * motion_score + 0.14 * stability_score + 0.10 * size_score
        elif self.active_profile == TrackingProfile.DARK:
            score = 0.42 * max(template_score, 0.0) + 0.18 * (1.0 - brightness_score) + 0.16 * motion_score + 0.14 * stability_score + 0.10 * size_score
        elif self.active_profile == TrackingProfile.CIRCULAR:
            score = 0.40 * max(template_score, 0.0) + 0.18 * circularity_score + 0.14 * motion_score + 0.14 * stability_score + 0.14 * size_score
        elif self.active_profile == TrackingProfile.ELONGATED:
            score = 0.40 * max(template_score, 0.0) + 0.18 * elongated_score + 0.14 * motion_score + 0.14 * stability_score + 0.14 * size_score
        else:
            score = (
                0.46 * max(template_score, 0.0)
                + 0.12 * marker_score
                + 0.16 * motion_score
                + 0.16 * stability_score
                + 0.10 * size_score
            )

        return _ScoredCandidate(
            bbox=bbox.clipped(self.frame_width, self.frame_height),
            score=float(max(0.0, min(score, 1.0))),
            template_score=float(max(0.0, min(template_score, 1.0))),
            marker_score=float(max(0.0, min(marker_score, 1.0))),
            motion_score=float(max(0.0, min(motion_score, 1.0))),
            stability_score=float(max(0.0, min(stability_score, 1.0))),
            size_score=float(max(0.0, min(size_score, 1.0))),
            search_mode=search_mode,
        )

    def _detect(self, frame: np.ndarray, predicted_bbox: BBox, *, mode: str) -> tuple[_ScoredCandidate, list[_ScoredCandidate]]:
        region, offset_x, offset_y = self._search_region(frame, predicted_bbox, mode=mode)
        candidates = self._template_candidates(region, predicted_bbox, offset_x, offset_y, mode=mode)
        candidates.extend(self._foreground_candidates(frame, predicted_bbox, mode=mode))

        best = _ScoredCandidate(predicted_bbox, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, mode)
        seen: set[tuple[int, int, int, int]] = set()
        ranked: list[_ScoredCandidate] = []
        for candidate in candidates:
            key = candidate.to_int_tuple()
            if key in seen:
                continue
            seen.add(key)
            scored = self._score_candidate(frame, candidate, predicted_bbox, search_mode=mode)
            ranked.append(scored)
            if scored.score > best.score:
                best = scored
        ranked.sort(key=lambda item: item.score, reverse=True)
        return best, ranked[:3]

    def _failure_reason_for(self, scored: _ScoredCandidate) -> str:
        if scored.search_mode == "full" and scored.score < self.config.low_confidence_threshold:
            return "search_exhausted"
        if self.active_profile == TrackingProfile.MARKER and scored.marker_score < 0.20:
            return "marker_missing"
        if scored.template_score < 0.20 and scored.motion_score < 0.08:
            return "weak_visual_signal"
        if scored.motion_score < 0.05:
            return "motion_only_prediction"
        return "low_confidence"

    def _refine_bbox_with_marker(self, frame: np.ndarray, bbox: BBox) -> tuple[BBox, tuple[float, float] | None]:
        if self.active_profile != TrackingProfile.MARKER:
            return bbox, None
        patch = self._extract_patch(frame, bbox)
        if patch.size == 0:
            return bbox, None
        mask = self._marker_mask(patch)
        if mask.size == 0 or np.count_nonzero(mask) < 10:
            return bbox, None
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return bbox, None
        contour = max(contours, key=cv2.contourArea)
        moments = cv2.moments(contour)
        if moments["m00"] <= 0:
            return bbox, None
        local_cx = moments["m10"] / moments["m00"]
        local_cy = moments["m01"] / moments["m00"]
        global_cx = bbox.x + local_cx
        global_cy = bbox.y + local_cy
        refined_bbox = BBox(
            x=global_cx - bbox.width / 2.0,
            y=global_cy - bbox.height / 2.0,
            width=bbox.width,
            height=bbox.height,
        ).clipped(self.frame_width, self.frame_height)
        return refined_bbox, (global_cx, global_cy)

    def _update_templates(self, frame: np.ndarray, bbox: BBox, confidence: float) -> None:
        if confidence < self.config.stable_update_threshold or self.state in {TrackingState.SUSPECT, TrackingState.LOST}:
            return
        refreshed = self._extract_patch(frame, bbox)
        if refreshed.size == 0:
            return
        resized = self._resize_like(refreshed, self.short_term_template)
        self.short_term_template = cv2.addWeighted(
            self.short_term_template,
            1.0 - self.config.template_update_rate,
            resized,
            self.config.template_update_rate,
            0.0,
        )
        self.short_term_gray = self._preprocess_gray(self.short_term_template)

    def update(self, frame: np.ndarray) -> tuple[BBox, tuple[float, float], float, bool, str, str | None, dict[str, float | str]]:
        self.frame_counter += 1
        predicted_bbox = self._predict_bbox()

        scored, ranked_candidates = self._detect(frame, predicted_bbox, mode="normal")
        if self.config.robust_recovery and self.bad_frame_streak >= self.config.recovery_after_frames and scored.score < self.config.reacquire_threshold:
            expanded, expanded_ranked = self._detect(frame, predicted_bbox, mode="expanded")
            if expanded.score >= scored.score:
                scored = expanded
                ranked_candidates = expanded_ranked
            if scored.score < self.config.reacquire_threshold:
                full_frame, full_ranked = self._detect(frame, predicted_bbox, mode="full")
                if full_frame.score >= scored.score:
                    scored = full_frame
                    ranked_candidates = full_ranked

        accepted = scored.score >= self.config.detection_threshold
        semi_accepted = scored.score >= self.config.low_confidence_threshold
        centroid_override: tuple[float, float] | None = None

        if accepted or semi_accepted:
            self.current_bbox = scored.bbox.clipped(self.frame_width, self.frame_height)
            self.current_bbox, centroid_override = self._refine_bbox_with_marker(frame, self.current_bbox)
            center_x, center_y = self.current_bbox.center
            measurement = np.array([[center_x], [center_y]], dtype=np.float32)
            self.kalman.correct(measurement)
        else:
            self.current_bbox = predicted_bbox

        previous_state = self.state
        failure_reason: str | None = None
        if accepted:
            if previous_state in {TrackingState.SUSPECT, TrackingState.LOST, TrackingState.REACQUIRED}:
                self.reacquire_streak += 1
                if self.reacquire_streak >= 2:
                    if previous_state != TrackingState.REACQUIRED:
                        self.reacquisition_count += 1
                    self.state = TrackingState.REACQUIRED
                else:
                    self.state = TrackingState.SUSPECT
            else:
                self.state = TrackingState.TRACKING
                self.reacquire_streak = 0
            self.bad_frame_streak = 0
        else:
            self.bad_frame_streak += 1
            self.reacquire_streak = 0
            failure_reason = self._failure_reason_for(scored)
            if self.bad_frame_streak >= self.config.max_prediction_frames:
                self.state = TrackingState.LOST
            elif self.bad_frame_streak >= self.config.suspect_after_frames:
                self.state = TrackingState.SUSPECT
            else:
                self.state = TrackingState.TRACKING

        if previous_state == TrackingState.REACQUIRED and accepted:
            self.state = TrackingState.TRACKING
        if self.state == TrackingState.REACQUIRED and not accepted:
            self.state = TrackingState.SUSPECT
        if self.state == TrackingState.LOST and semi_accepted:
            self.state = TrackingState.SUSPECT

        lost = self.state == TrackingState.LOST
        confidence = scored.score if accepted or semi_accepted else max(0.08, scored.score * 0.6)
        self.last_failure_reason = failure_reason

        self._update_templates(frame, self.current_bbox, confidence)

        debug = {
            "search_mode": scored.search_mode,
            "template_score": round(scored.template_score, 4),
            "marker_score": round(scored.marker_score, 4),
            "motion_score": round(scored.motion_score, 4),
            "stability_score": round(scored.stability_score, 4),
            "size_score": round(scored.size_score, 4),
            "profile": self.active_profile.value,
        }
        if not self.config.debug_tracking:
            debug = {"search_mode": scored.search_mode, "profile": self.active_profile.value}
        else:
            debug["candidate_rankings"] = " | ".join(
                f"{index + 1}:{candidate.score:.3f}@{candidate.search_mode}"
                for index, candidate in enumerate(ranked_candidates)
            )
            if ranked_candidates:
                debug["candidate_count"] = str(len(ranked_candidates))

        centroid = centroid_override if centroid_override is not None else self.current_bbox.center
        return self.current_bbox, centroid, float(max(0.0, min(confidence, 1.0))), lost, self.state.value, failure_reason, debug


def _build_spans(observations: list[TrackingObservation], *, predicate, reason: str) -> list[TrackSpan]:
    spans: list[TrackSpan] = []
    start_frame: int | None = None
    end_frame: int | None = None
    for observation in observations:
        is_active = bool(predicate(observation))
        if is_active and start_frame is None:
            start_frame = observation.frame_index
        if is_active:
            end_frame = observation.frame_index
        if not is_active and start_frame is not None and end_frame is not None:
            spans.append(TrackSpan(start_frame=start_frame, end_frame=end_frame, reason=reason))
            start_frame = None
            end_frame = None
    if start_frame is not None and end_frame is not None:
        spans.append(TrackSpan(start_frame=start_frame, end_frame=end_frame, reason=reason))
    return spans


def _compute_quality_metadata(observations: list[TrackingObservation]) -> TrackQualityMetadata:
    lost_spans = _build_spans(observations, predicate=lambda observation: observation.lost, reason="lost_tracking")
    suspect_spans = _build_spans(
        observations,
        predicate=lambda observation: observation.state in {TrackingState.SUSPECT.value, TrackingState.REACQUIRED.value},
        reason="tracking_recovery",
    )
    corrected_spans = _build_spans(observations, predicate=lambda observation: observation.corrected, reason="manual_correction")
    reacquisition_count = sum(1 for observation in observations if observation.state == TrackingState.REACQUIRED.value)
    review_recommended = bool(lost_spans) or bool(suspect_spans) or any(observation.confidence < 0.35 for observation in observations)
    return TrackQualityMetadata(
        lost_spans=lost_spans,
        suspect_spans=suspect_spans,
        corrected_spans=corrected_spans,
        reacquisition_count=reacquisition_count,
        review_recommended=review_recommended,
    )


def _interpolate_short_gaps(observations: list[TrackingObservation], config: TrackingConfig) -> list[TrackingObservation]:
    if not config.interpolate_short_gaps or len(observations) < 3:
        return observations
    interpolated = list(observations)
    for index in range(1, len(interpolated) - 1):
        current = interpolated[index]
        if not current.lost:
            continue
        start = index
        end = index
        while end + 1 < len(interpolated) and interpolated[end + 1].lost:
            end += 1
        gap = end - start + 1
        if gap > config.max_interpolation_gap or start == 0 or end >= len(interpolated) - 1:
            continue
        previous = interpolated[start - 1]
        following = interpolated[end + 1]
        if previous.lost or following.lost:
            continue
        for offset, target_index in enumerate(range(start, end + 1), start=1):
            alpha = offset / float(gap + 1)
            bbox = BBox(
                x=(1.0 - alpha) * previous.bbox.x + alpha * following.bbox.x,
                y=(1.0 - alpha) * previous.bbox.y + alpha * following.bbox.y,
                width=(1.0 - alpha) * previous.bbox.width + alpha * following.bbox.width,
                height=(1.0 - alpha) * previous.bbox.height + alpha * following.bbox.height,
            )
            interpolated[target_index] = TrackingObservation(
                frame_index=current.frame_index + (target_index - start),
                timestamp=interpolated[target_index].timestamp,
                centroid_x_px=(1.0 - alpha) * previous.centroid_x_px + alpha * following.centroid_x_px,
                centroid_y_px=(1.0 - alpha) * previous.centroid_y_px + alpha * following.centroid_y_px,
                bbox=bbox,
                confidence=min(previous.confidence, following.confidence) * 0.72,
                lost=False,
                corrected=interpolated[target_index].corrected,
                state=TrackingState.SUSPECT.value,
                failure_reason="short_gap_interpolated",
                debug={**interpolated[target_index].debug, "interpolation": "linear_short_gap"},
                track_id=interpolated[target_index].track_id,
                track_name=interpolated[target_index].track_name,
                track_kind=interpolated[target_index].track_kind,
                source="interpolated",
                is_inferred=True,
                is_interpolated=True,
            )
    return interpolated


def _resolved_tracking_config(config: TrackingConfig, resolved_profile: TrackingProfile) -> TrackingConfig:
    return TrackingConfig(
        profile=resolved_profile,
        robust_recovery=config.robust_recovery,
        bidirectional_refinement=config.bidirectional_refinement,
        debug_tracking=config.debug_tracking,
        search_margin=config.search_margin,
        expanded_search_margin=config.expanded_search_margin,
        scale_factors=config.scale_factors,
        detection_threshold=config.detection_threshold,
        low_confidence_threshold=config.low_confidence_threshold,
        reacquire_threshold=config.reacquire_threshold,
        suspect_after_frames=config.suspect_after_frames,
        recovery_after_frames=config.recovery_after_frames,
        max_prediction_frames=config.max_prediction_frames,
        template_update_rate=config.template_update_rate,
        stable_update_threshold=config.stable_update_threshold,
        marker_confidence_bias=config.marker_confidence_bias,
        auto_marker_min_ratio=config.auto_marker_min_ratio,
        interpolate_short_gaps=config.interpolate_short_gaps,
        max_interpolation_gap=config.max_interpolation_gap,
    )


def _build_track_result(
    observations: list[TrackingObservation],
    *,
    tracker_name: str,
    start_frame: int,
    end_frame: int,
    initial_bbox: BBox,
    tracking_config: TrackingConfig,
    track_id: str = "primary",
    track_name: str = "Primary Object",
    track_kind: str = "primary",
) -> TrackResult:
    ordered = sorted(observations, key=lambda observation: observation.frame_index)
    ordered = _interpolate_short_gaps(ordered, tracking_config)
    average_confidence = float(np.mean([o.confidence for o in ordered])) if ordered else 0.0
    return TrackResult(
        observations=ordered,
        tracker_name=tracker_name,
        average_confidence=average_confidence,
        start_frame=start_frame,
        end_frame=end_frame,
        initial_bbox=initial_bbox,
        quality=_compute_quality_metadata(ordered),
        tracking_config=tracking_config,
        track_id=track_id,
        track_name=track_name,
        track_kind=track_kind,
    )


def _run_tracking_pass(
    video: VideoSource,
    initial_bbox: BBox,
    *,
    start_frame: int,
    end_frame: int,
    step: int,
    corrected: bool,
    config: TrackingConfig,
    track_id: str,
    track_name: str,
    track_kind: str,
) -> TrackResult:
    initial_frame = video.read_frame(start_frame)
    tracker = RobustHybridTracker(initial_frame, initial_bbox, config=config)
    observations: list[TrackingObservation] = []

    for frame_index, frame in video.iter_frames(start_frame, end_index=end_frame, step=step):
        if frame_index == start_frame:
            bbox = initial_bbox.clipped(frame.shape[1], frame.shape[0])
            centroid = bbox.center
            confidence = 1.0
            lost = False
            state = TrackingState.TRACKING.value
            failure_reason = None
            debug = {"search_mode": "initial", "profile": tracker.active_profile.value}
        else:
            bbox, centroid, confidence, lost, state, failure_reason, debug = tracker.update(frame)

        center_x, center_y = centroid
        observations.append(
            TrackingObservation(
                frame_index=frame_index,
                timestamp=video.frame_timestamp(frame_index),
                centroid_x_px=center_x,
                centroid_y_px=center_y,
                bbox=bbox,
                confidence=confidence,
                lost=lost,
                corrected=corrected,
                state=state,
                failure_reason=failure_reason,
                debug=debug,
                track_id=track_id,
                track_name=track_name,
                track_kind=track_kind,
                source="measured" if not lost else "predicted",
                is_inferred=lost,
            )
        )

    return _build_track_result(
        observations,
        tracker_name="robust_hybrid_tracker",
        start_frame=min(start_frame, end_frame),
        end_frame=max(start_frame, end_frame),
        initial_bbox=initial_bbox,
        tracking_config=_resolved_tracking_config(config, tracker.active_profile),
        track_id=track_id,
        track_name=track_name,
        track_kind=track_kind,
    )


def _merge_bidirectional_observations(forward: TrackingObservation, backward: TrackingObservation) -> TrackingObservation:
    if forward.lost != backward.lost:
        preferred = forward if not forward.lost else backward
        return TrackingObservation(
            frame_index=preferred.frame_index,
            timestamp=preferred.timestamp,
            centroid_x_px=preferred.centroid_x_px,
            centroid_y_px=preferred.centroid_y_px,
            bbox=preferred.bbox,
            confidence=preferred.confidence,
            lost=preferred.lost,
            corrected=preferred.corrected or backward.corrected,
            state=preferred.state,
            failure_reason=preferred.failure_reason,
            debug={**forward.debug, **backward.debug, "merge_mode": "preferred_non_lost"},
        )

    forward_weight = max(forward.confidence, 0.05)
    backward_weight = max(backward.confidence, 0.05)
    total = forward_weight + backward_weight

    if abs(forward.confidence - backward.confidence) > 0.10:
        preferred = forward if forward.confidence >= backward.confidence else backward
        return TrackingObservation(
            frame_index=preferred.frame_index,
            timestamp=preferred.timestamp,
            centroid_x_px=preferred.centroid_x_px,
            centroid_y_px=preferred.centroid_y_px,
            bbox=preferred.bbox,
            confidence=preferred.confidence,
            lost=preferred.lost,
            corrected=preferred.corrected or forward.corrected or backward.corrected,
            state=preferred.state,
            failure_reason=preferred.failure_reason,
            debug={**forward.debug, **backward.debug, "merge_mode": "preferred_confidence"},
        )

    merged_bbox = BBox(
        x=(forward.bbox.x * forward_weight + backward.bbox.x * backward_weight) / total,
        y=(forward.bbox.y * forward_weight + backward.bbox.y * backward_weight) / total,
        width=(forward.bbox.width * forward_weight + backward.bbox.width * backward_weight) / total,
        height=(forward.bbox.height * forward_weight + backward.bbox.height * backward_weight) / total,
    )
    merged_confidence = (forward.confidence * forward_weight + backward.confidence * backward_weight) / total
    merged_state = forward.state if forward.state == backward.state else (
        forward.state if forward.confidence >= backward.confidence else backward.state
    )
    merged_reason = forward.failure_reason or backward.failure_reason
    return TrackingObservation(
        frame_index=forward.frame_index,
        timestamp=forward.timestamp,
        centroid_x_px=(forward.centroid_x_px * forward_weight + backward.centroid_x_px * backward_weight) / total,
        centroid_y_px=(forward.centroid_y_px * forward_weight + backward.centroid_y_px * backward_weight) / total,
        bbox=merged_bbox,
        confidence=merged_confidence,
        lost=forward.lost and backward.lost,
        corrected=forward.corrected or backward.corrected,
        state=merged_state,
        failure_reason=merged_reason,
        debug={**forward.debug, **backward.debug, "merge_mode": "blended"},
    )


def _merge_bidirectional_tracks(forward: TrackResult, backward: TrackResult) -> TrackResult:
    backward_by_frame = backward.observation_by_frame()
    merged: list[TrackingObservation] = []
    for observation in forward.observations:
        reverse_observation = backward_by_frame.get(observation.frame_index)
        if reverse_observation is None:
            merged.append(observation)
            continue
        merged.append(_merge_bidirectional_observations(observation, reverse_observation))
    return _build_track_result(
        merged,
        tracker_name="robust_bidirectional_tracker",
        start_frame=forward.start_frame,
        end_frame=forward.end_frame,
        initial_bbox=forward.initial_bbox,
        tracking_config=forward.tracking_config,
    )


def run_single_object_tracking(
    video: VideoSource,
    initial_bbox: BBox,
    *,
    start_frame: int = 0,
    end_frame: int | None = None,
    corrected: bool = False,
    config: TrackingConfig | None = None,
    track_id: str = "primary",
    track_name: str = "Primary Object",
    track_kind: str = "primary",
) -> TrackResult:
    tracking_config = config or TrackingConfig()
    selected_end_frame = video.metadata.frame_count - 1 if end_frame is None else min(end_frame, video.metadata.frame_count - 1)
    if selected_end_frame < start_frame:
        raise ValueError("end_frame must be greater than or equal to start_frame")

    forward_track = _run_tracking_pass(
        video,
        initial_bbox,
        start_frame=start_frame,
        end_frame=selected_end_frame,
        step=1,
        corrected=corrected,
        config=tracking_config,
        track_id=track_id,
        track_name=track_name,
        track_kind=track_kind,
    )
    if not tracking_config.bidirectional_refinement or selected_end_frame - start_frame < 8:
        return forward_track

    seed_observation = next(
        (
            observation
            for observation in reversed(forward_track.observations)
            if not observation.lost and observation.confidence >= tracking_config.detection_threshold
        ),
        forward_track.observations[-1],
    )
    if seed_observation.frame_index <= start_frame:
        return forward_track

    backward_track = _run_tracking_pass(
        video,
        seed_observation.bbox,
        start_frame=seed_observation.frame_index,
        end_frame=start_frame,
        step=-1,
        corrected=corrected,
        config=tracking_config,
        track_id=track_id,
        track_name=track_name,
        track_kind=track_kind,
    )
    merged = _merge_bidirectional_tracks(forward_track, backward_track)
    return merged


def merge_track_results(base: TrackResult, replacement: TrackResult) -> TrackResult:
    merged: list[TrackingObservation] = []
    for observation in base.observations:
        if observation.frame_index < replacement.start_frame:
            merged.append(observation)
    merged.extend(replacement.observations)
    merged.sort(key=lambda item: item.frame_index)

    average_confidence = float(np.mean([o.confidence for o in merged])) if merged else 0.0
    quality = _compute_quality_metadata(merged)
    corrected_span = TrackSpan(
        start_frame=replacement.start_frame,
        end_frame=replacement.observations[-1].frame_index if replacement.observations else replacement.start_frame,
        reason="manual_correction",
    )
    quality = TrackQualityMetadata(
        lost_spans=quality.lost_spans,
        suspect_spans=quality.suspect_spans,
        corrected_spans=base.quality.corrected_spans + [corrected_span],
        reacquisition_count=quality.reacquisition_count,
        review_recommended=quality.review_recommended,
    )
    return TrackResult(
        observations=merged,
        tracker_name=base.tracker_name,
        average_confidence=average_confidence,
        start_frame=base.start_frame,
        end_frame=max(base.end_frame, replacement.end_frame),
        initial_bbox=base.initial_bbox,
        quality=quality,
        tracking_config=replacement.tracking_config,
        track_id=base.track_id,
        track_name=base.track_name,
        track_kind=base.track_kind,
    )


def track_result_to_dicts(track_result: TrackResult) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for observation in track_result.observations:
        row = asdict(observation)
        row["bbox"] = asdict(observation.bbox)
        rows.append(row)
    return rows
