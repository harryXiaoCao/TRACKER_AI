from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .analysis import AnalysisConfig, AnalysisResult, analyze_track
from .calibration import CalibrationProfile
from .tracking import (
    BBox,
    PairwiseMetricResult,
    PairwiseMetricSample,
    TrackResult,
    TrackedObject,
    TrackingConfig,
    TrackingObservation,
    TrackingProfile,
    run_single_object_tracking,
)
from .video import VideoSource


@dataclass(frozen=True)
class ExperimentRunResult:
    display_track: TrackResult
    analysis_track: TrackResult
    reference_track: TrackResult | None
    analysis: AnalysisResult


@dataclass(frozen=True)
class MultiObjectExperimentResult:
    primary_track_id: str
    display_tracks: dict[str, TrackResult]
    analysis_tracks: dict[str, TrackResult]
    analyses: dict[str, AnalysisResult]
    pairwise_metrics: list[PairwiseMetricResult]
    reference_track: TrackResult | None


def apply_reference_motion_correction(primary_track: TrackResult, reference_track: TrackResult) -> TrackResult:
    reference_by_frame = reference_track.observation_by_frame()
    if not reference_track.observations:
        return primary_track
    reference_origin = reference_track.observations[0]

    corrected_observations: list[TrackingObservation] = []
    for observation in primary_track.observations:
        reference_observation = reference_by_frame.get(observation.frame_index)
        if reference_observation is None:
            corrected_observations.append(observation)
            continue
        dx = reference_observation.centroid_x_px - reference_origin.centroid_x_px
        dy = reference_observation.centroid_y_px - reference_origin.centroid_y_px
        corrected_debug = {
            **observation.debug,
            "reference_dx": round(dx, 4),
            "reference_dy": round(dy, 4),
            "reference_profile": reference_track.tracking_config.profile.value,
        }
        corrected_reason = observation.failure_reason
        if reference_observation.lost:
            corrected_reason = corrected_reason or "reference_marker_lost"
        corrected_observations.append(
            TrackingObservation(
                frame_index=observation.frame_index,
                timestamp=observation.timestamp,
                centroid_x_px=observation.centroid_x_px - dx,
                centroid_y_px=observation.centroid_y_px - dy,
                bbox=observation.bbox,
                confidence=min(observation.confidence, reference_observation.confidence),
                lost=observation.lost or reference_observation.lost,
                corrected=observation.corrected,
                state=observation.state if not reference_observation.lost else "suspect",
                failure_reason=corrected_reason,
                debug=corrected_debug,
                track_id=observation.track_id,
                track_name=observation.track_name,
                track_kind=observation.track_kind,
                source=observation.source,
                is_inferred=observation.is_inferred,
                is_interpolated=observation.is_interpolated,
            )
        )

    average_confidence = sum(observation.confidence for observation in corrected_observations) / len(corrected_observations)
    return TrackResult(
        observations=corrected_observations,
        tracker_name=f"{primary_track.tracker_name}_reference_corrected",
        average_confidence=float(average_confidence),
        start_frame=primary_track.start_frame,
        end_frame=primary_track.end_frame,
        initial_bbox=primary_track.initial_bbox,
        quality=primary_track.quality,
        tracking_config=primary_track.tracking_config,
        track_id=primary_track.track_id,
        track_name=primary_track.track_name,
        track_kind=primary_track.track_kind,
    )


def _reference_config_from(tracking_config: TrackingConfig) -> TrackingConfig:
    return TrackingConfig(
        profile=TrackingProfile.MARKER if tracking_config.profile == TrackingProfile.AUTO else tracking_config.profile,
        robust_recovery=tracking_config.robust_recovery,
        bidirectional_refinement=tracking_config.bidirectional_refinement,
        debug_tracking=tracking_config.debug_tracking,
        search_margin=tracking_config.search_margin,
        expanded_search_margin=tracking_config.expanded_search_margin,
        scale_factors=tracking_config.scale_factors,
        detection_threshold=tracking_config.detection_threshold,
        low_confidence_threshold=tracking_config.low_confidence_threshold,
        reacquire_threshold=tracking_config.reacquire_threshold,
        suspect_after_frames=tracking_config.suspect_after_frames,
        recovery_after_frames=tracking_config.recovery_after_frames,
        max_prediction_frames=tracking_config.max_prediction_frames,
        template_update_rate=tracking_config.template_update_rate,
        stable_update_threshold=tracking_config.stable_update_threshold,
        marker_confidence_bias=tracking_config.marker_confidence_bias,
        auto_marker_min_ratio=tracking_config.auto_marker_min_ratio,
        interpolate_short_gaps=tracking_config.interpolate_short_gaps,
        max_interpolation_gap=tracking_config.max_interpolation_gap,
    )


def run_multi_object_experiment(
    video: VideoSource,
    objects: list[TrackedObject],
    calibration: CalibrationProfile,
    analysis_config: AnalysisConfig,
    tracking_config: TrackingConfig,
    *,
    start_frame: int = 0,
    end_frame: int | None = None,
    reference_bbox: BBox | None = None,
    corrected: bool = False,
    primary_track_id: str = "primary",
) -> MultiObjectExperimentResult:
    display_tracks: dict[str, TrackResult] = {}
    analysis_tracks: dict[str, TrackResult] = {}
    analyses: dict[str, AnalysisResult] = {}

    reference_track: TrackResult | None = None
    if reference_bbox is not None:
        reference_track = run_single_object_tracking(
            video,
            reference_bbox,
            start_frame=start_frame,
            end_frame=end_frame,
            corrected=corrected,
            config=_reference_config_from(tracking_config),
            track_id="reference",
            track_name="Reference Marker",
            track_kind="reference",
        )

    for object_spec in objects:
        display_track = run_single_object_tracking(
            video,
            object_spec.bbox,
            start_frame=start_frame,
            end_frame=end_frame,
            corrected=corrected,
            config=tracking_config,
            track_id=object_spec.track_id,
            track_name=object_spec.name,
            track_kind=object_spec.kind,
        )
        analysis_track = apply_reference_motion_correction(display_track, reference_track) if reference_track is not None else display_track
        display_tracks[object_spec.track_id] = display_track
        analysis_tracks[object_spec.track_id] = analysis_track
        analyses[object_spec.track_id] = analyze_track(analysis_track, calibration, analysis_config)

    pairwise_metrics = build_pairwise_metrics(list(analysis_tracks.values()), analyses)
    return MultiObjectExperimentResult(
        primary_track_id=primary_track_id,
        display_tracks=display_tracks,
        analysis_tracks=analysis_tracks,
        analyses=analyses,
        pairwise_metrics=pairwise_metrics,
        reference_track=reference_track,
    )


def build_pairwise_metrics(tracks: list[TrackResult], analyses: dict[str, AnalysisResult]) -> list[PairwiseMetricResult]:
    results: list[PairwiseMetricResult] = []
    for index, primary in enumerate(tracks):
        primary_analysis = analyses[primary.track_id]
        primary_by_frame = primary.observation_by_frame()
        for secondary in tracks[index + 1 :]:
            secondary_analysis = analyses[secondary.track_id]
            secondary_by_frame = secondary.observation_by_frame()
            samples: list[PairwiseMetricSample] = []
            common_frames = sorted(set(primary_by_frame) & set(secondary_by_frame))
            for frame in common_frames:
                left = primary_by_frame[frame]
                right = secondary_by_frame[frame]
                left_index = next(i for i, observation in enumerate(primary.observations) if observation.frame_index == frame)
                right_index = next(i for i, observation in enumerate(secondary.observations) if observation.frame_index == frame)
                dx = secondary_analysis.x_units[right_index] - primary_analysis.x_units[left_index]
                dy = secondary_analysis.y_units[right_index] - primary_analysis.y_units[left_index]
                distance = float(np.sqrt(dx**2 + dy**2))
                relative_speed = float(
                    np.sqrt(
                        (secondary_analysis.x_velocity[right_index] - primary_analysis.x_velocity[left_index]) ** 2
                        + (secondary_analysis.y_velocity[right_index] - primary_analysis.y_velocity[left_index]) ** 2
                    )
                )
                samples.append(
                    PairwiseMetricSample(
                        frame_index=frame,
                        time_s=left.timestamp,
                        distance_units=distance,
                        relative_speed_units_s=relative_speed,
                        relative_dx_units=float(dx),
                        relative_dy_units=float(dy),
                    )
                )
            if not samples:
                continue
            collision_frame = next((sample.frame_index for sample in samples if sample.distance_units <= 0.05), None)
            primary_indices = [next(i for i, observation in enumerate(primary.observations) if observation.frame_index == sample.frame_index) for sample in samples]
            secondary_indices = [next(i for i, observation in enumerate(secondary.observations) if observation.frame_index == sample.frame_index) for sample in samples]
            com_x = [
                float((primary_analysis.x_units[left_index] + secondary_analysis.x_units[right_index]) / 2.0)
                for left_index, right_index in zip(primary_indices, secondary_indices, strict=False)
            ]
            com_y = [
                float((primary_analysis.y_units[left_index] + secondary_analysis.y_units[right_index]) / 2.0)
                for left_index, right_index in zip(primary_indices, secondary_indices, strict=False)
            ]
            results.append(
                PairwiseMetricResult(
                    primary_track_id=primary.track_id,
                    secondary_track_id=secondary.track_id,
                    samples=samples,
                    minimum_separation=min(sample.distance_units for sample in samples),
                    peak_relative_speed=max(sample.relative_speed_units_s for sample in samples),
                    collision_frame=collision_frame,
                    center_of_mass_x=com_x,
                    center_of_mass_y=com_y,
                )
            )
    return results


def run_experiment_analysis(
    video: VideoSource,
    primary_bbox: BBox,
    calibration: CalibrationProfile,
    analysis_config: AnalysisConfig,
    tracking_config: TrackingConfig,
    *,
    start_frame: int = 0,
    end_frame: int | None = None,
    reference_bbox: BBox | None = None,
    corrected: bool = False,
) -> ExperimentRunResult:
    multi = run_multi_object_experiment(
        video,
        [TrackedObject(track_id="primary", name="Primary Object", bbox=primary_bbox, kind="primary")],
        calibration,
        analysis_config,
        tracking_config,
        start_frame=start_frame,
        end_frame=end_frame,
        reference_bbox=reference_bbox,
        corrected=corrected,
        primary_track_id="primary",
    )
    return ExperimentRunResult(
        display_track=multi.display_tracks["primary"],
        analysis_track=multi.analysis_tracks["primary"],
        reference_track=multi.reference_track,
        analysis=multi.analyses["primary"],
    )
