from __future__ import annotations

import contextlib
import csv
import io
import json
import os
from pathlib import Path
import tempfile

import cv2
import numpy as np

from .analysis import AnalysisResult, summarize_window
from .analyzers import AnalyzerResult
from .calibration import CalibrationProfile
from .experiment import MultiObjectExperimentResult
from .reporting import build_analysis_summary, build_analyzer_report, build_quality_report, export_summary_json
from .session import EventMarker, ProjectSession
from .tracking import PairwiseMetricResult, TrackResult
from .video import VideoSource

_CACHE_ROOT = Path(tempfile.gettempdir()) / "tracker_ai_cache"
_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("XDG_CACHE_HOME", str(_CACHE_ROOT))
os.environ.setdefault("MPLCONFIGDIR", str(_CACHE_ROOT / "matplotlib"))

with contextlib.redirect_stderr(io.StringIO()):
    try:
        import matplotlib.pyplot as plt
    except Exception:  # pragma: no cover - optional at runtime
        plt = None


def export_analysis_csv(
    analysis: AnalysisResult,
    output_path: str | Path,
    track_result: TrackResult | None = None,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = analysis.to_rows()
    if track_result is not None:
        observations = track_result.observations
        for row, observation in zip(rows, observations, strict=False):
            row["frame_index"] = observation.frame_index
            row["lost"] = observation.lost
            row["corrected"] = observation.corrected
            row["state"] = observation.state
            row["failure_reason"] = observation.failure_reason or ""
            row["bbox_x"] = observation.bbox.x
            row["bbox_y"] = observation.bbox.y
            row["bbox_width"] = observation.bbox.width
            row["bbox_height"] = observation.bbox.height
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def export_raw_track_csv(analysis: AnalysisResult, track_result: TrackResult, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    for observation, row in zip(track_result.observations, analysis.to_rows(), strict=False):
        rows.append(
            {
                "frame_index": observation.frame_index,
                "time_s": row["time_s"],
                "x_px": row["x_px"],
                "y_px": row["y_px"],
                "raw_x_units": row["raw_x_units"],
                "raw_y_units": row["raw_y_units"],
                "confidence": row["confidence"],
                "scientific_confidence": row["scientific_confidence"],
                "state": observation.state,
                "lost": observation.lost,
                "corrected": observation.corrected,
            }
        )
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def export_smoothed_track_csv(analysis: AnalysisResult, track_result: TrackResult, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    for observation, row in zip(track_result.observations, analysis.to_rows(), strict=False):
        rows.append(
            {
                "frame_index": observation.frame_index,
                "time_s": row["time_s"],
                "x_units": row["x_units"],
                "y_units": row["y_units"],
                "vx": row["vx"],
                "vy": row["vy"],
                "ax": row["ax"],
                "ay": row["ay"],
                "speed": row["speed"],
                "acceleration_magnitude": row["acceleration_magnitude"],
                "position_uncertainty": row["position_uncertainty"],
                "velocity_uncertainty": row["velocity_uncertainty"],
                "acceleration_uncertainty": row["acceleration_uncertainty"],
            }
        )
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def _event_marker_rows(markers: tuple[EventMarker, ...] | list[EventMarker]) -> list[dict[str, object]]:
    return [
        {
            "name": marker.name,
            "frame_index": marker.frame_index,
            "time_s": marker.time_s,
            "value": marker.value,
            "unit_label": marker.unit_label,
            "axis": marker.axis,
            "note": marker.note,
            "origin": marker.origin,
        }
        for marker in markers
    ]


def export_events_csv(
    analysis: AnalysisResult,
    output_path: str | Path,
    *,
    event_markers: tuple[EventMarker, ...] | list[EventMarker] | None = None,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = _event_marker_rows(event_markers) if event_markers is not None else analysis.event_rows()
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def export_quality_report_json(
    analysis: AnalysisResult,
    track_result: TrackResult,
    output_path: str | Path,
    *,
    calibration: CalibrationProfile | None = None,
) -> Path:
    report = build_quality_report(analysis, track_result, calibration)
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    return path


def export_analyzer_report_json(results: tuple[AnalyzerResult, ...], output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([result.to_dict() for result in results], indent=2), encoding="utf-8")
    return path


def export_selected_window_summary_json(
    analysis: AnalysisResult,
    start_frame: int,
    end_frame: int,
    output_path: str | Path,
) -> Path | None:
    window = summarize_window(analysis, start_frame, end_frame)
    if window is None:
        return None
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(window.__dict__, indent=2), encoding="utf-8")
    return path


def build_reproduce_command(session: ProjectSession) -> str:
    scale_points = " ".join(f"{value:g}" for value in (session.scale_points or (0.0, 0.0, session.calibration.pixel_distance, 0.0)))
    bbox = session.initial_bbox
    command = [
        "tracker-ai",
        "analyze",
        f"--video \"{session.video_path}\"",
        f"--bbox {bbox.x:g} {bbox.y:g} {bbox.width:g} {bbox.height:g}",
        f"--scale-points {scale_points}",
        f"--reference-length {session.calibration.reference_length:g}",
        f"--unit {session.calibration.unit_label}",
        f"--start-frame {session.selected_start_frame}",
        f"--window {session.analysis_config.smoothing_window}",
        f"--polyorder {session.analysis_config.smoothing_polyorder}",
    ]
    if session.selected_end_frame is not None:
        command.append(f"--end-frame {session.selected_end_frame}")
    if session.reference_bbox is not None:
        ref = session.reference_bbox
        command.append(f"--reference-bbox {ref.x:g} {ref.y:g} {ref.width:g} {ref.height:g}")
    if session.metadata.experiment_label:
        command.append(f"--experiment-label \"{session.metadata.experiment_label}\"")
    if session.metadata.trial_id:
        command.append(f"--trial-id \"{session.metadata.trial_id}\"")
    if session.metadata.operator_name:
        command.append(f"--operator \"{session.metadata.operator_name}\"")
    if session.metadata.notes:
        command.append(f"--notes \"{session.metadata.notes}\"")
    if session.metadata.tags:
        command.append("--tags " + " ".join(f"\"{tag}\"" for tag in session.metadata.tags))
    for item in session.additional_objects:
        bbox = item.bbox
        command.append(f"--extra-object {item.track_id} \"{item.name}\" {bbox.x:g} {bbox.y:g} {bbox.width:g} {bbox.height:g}")
    command.append(f"--tracking-profile {session.tracking_config.profile.value}")
    if session.tracking_config.debug_tracking:
        command.append("--debug-tracking")
    if not session.tracking_config.bidirectional_refinement:
        command.append("--disable-bidirectional-refinement")
    command.append("--output-dir <output-dir>")
    return " \\\n  ".join(command)


def export_experiment_manifest(
    session: ProjectSession,
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    output_path: str | Path,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "session_version": session.version,
        "video_path": session.video_path,
        "video_path_snapshot": session.provenance.video_path_snapshot,
        "tracking_profile": track_result.tracking_config.profile.value,
        "reference_length": calibration.reference_length,
        "unit_label": calibration.unit_label,
        "selected_start_frame": session.selected_start_frame,
        "selected_end_frame": session.selected_end_frame,
        "advanced_mode": session.advanced_mode,
        "additional_objects": [item.name for item in session.additional_objects],
        "event_count": len(analysis.events),
        "report_template": session.export_preferences.report_template,
        "reproduce_command": build_reproduce_command(session),
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return path


def export_pairwise_metrics_csv(metrics: list[PairwiseMetricResult], output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    for metric in metrics:
        for sample in metric.samples:
            rows.append(
                {
                    "primary_track_id": metric.primary_track_id,
                    "secondary_track_id": metric.secondary_track_id,
                    "frame_index": sample.frame_index,
                    "time_s": sample.time_s,
                    "distance_units": sample.distance_units,
                    "relative_speed_units_s": sample.relative_speed_units_s,
                    "relative_dx_units": sample.relative_dx_units,
                    "relative_dy_units": sample.relative_dy_units,
                }
            )
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def export_multi_object_bundle(
    experiment: MultiObjectExperimentResult,
    calibration: CalibrationProfile,
    session: ProjectSession,
    output_dir: str | Path,
) -> dict[str, object]:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    track_outputs: dict[str, object] = {}
    for track_id, track in experiment.analysis_tracks.items():
        track_dir = output_path / track_id
        track_outputs[track_id] = export_result_bundle(
            video_path=session.video_path,
            analysis=experiment.analyses[track_id],
            track_result=track,
            calibration=calibration,
            session=session,
            output_dir=track_dir,
            include_overlay=session.export_preferences.include_overlay and track_id == experiment.primary_track_id,
            include_debug_tracking=session.export_preferences.include_debug_tracking,
            overlay_track_result=experiment.display_tracks.get(track_id),
            reference_track=experiment.reference_track,
        )
    pairwise_path = export_pairwise_metrics_csv(experiment.pairwise_metrics, output_path / "pairwise_metrics.csv")
    return {"tracks": track_outputs, "pairwise_metrics": pairwise_path}


def export_tracking_debug_csv(track_result: TrackResult, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    all_debug_keys: set[str] = set()
    for observation in track_result.observations:
        all_debug_keys.update(observation.debug.keys())
    ordered_debug_keys = sorted(all_debug_keys)

    for observation in track_result.observations:
        row: dict[str, object] = {
            "frame_index": observation.frame_index,
            "timestamp": observation.timestamp,
            "state": observation.state,
            "confidence": observation.confidence,
            "failure_reason": observation.failure_reason or "",
            "lost": observation.lost,
        }
        for key in ordered_debug_keys:
            row[key] = observation.debug.get(key, "")
        rows.append(row)

    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    return path


def export_track_overlay(
    video: VideoSource,
    track_result: TrackResult,
    output_path: str | Path,
    *,
    reference_track: TrackResult | None = None,
) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = video.metadata
    writer = cv2.VideoWriter(
        str(path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        metadata.fps,
        (metadata.width, metadata.height),
    )
    try:
        observations = {o.frame_index: o for o in track_result.observations}
        reference_observations = reference_track.observation_by_frame() if reference_track is not None else {}
        for frame_index, frame in video.iter_frames(0):
            observation = observations.get(frame_index)
            if observation:
                x, y, w, h = observation.bbox.to_int_tuple()
                color = (244, 176, 64) if observation.corrected else ((0, 200, 0) if not observation.lost else (0, 120, 255))
                cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
                cv2.circle(frame, (int(observation.centroid_x_px), int(observation.centroid_y_px)), 3, color, -1)
                label = f"{observation.timestamp:.3f}s conf={observation.confidence:.2f} {observation.state}"
                if observation.corrected:
                    label += " corrected"
                if observation.failure_reason:
                    label += f" {observation.failure_reason}"
                cv2.putText(frame, label, (x, max(20, y - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)
            reference_observation = reference_observations.get(frame_index)
            if reference_observation is not None:
                rx, ry, rw, rh = reference_observation.bbox.to_int_tuple()
                ref_color = (43, 108, 176) if not reference_observation.lost else (0, 120, 255)
                cv2.rectangle(frame, (rx, ry), (rx + rw, ry + rh), ref_color, 2)
                cv2.circle(frame, (int(reference_observation.centroid_x_px), int(reference_observation.centroid_y_px)), 3, ref_color, -1)
                cv2.putText(frame, "reference", (rx, max(40, ry - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, ref_color, 1)
            writer.write(frame)
    finally:
        writer.release()
    return path


def export_analysis_plots(analysis: AnalysisResult, output_dir: str | Path) -> list[Path]:
    if plt is None:
        return []

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []

    def _save_plot(filename: str, title: str, series: list[tuple[np.ndarray, str, str]], ylabel: str) -> None:
        fig, ax = plt.subplots(figsize=(9, 4.5))
        for values, label, color in series:
            ax.plot(analysis.time_s, values, label=label, color=color, linewidth=2)
        ax.set_title(title)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel(ylabel)
        ax.grid(True, alpha=0.25)
        ax.legend()
        fig.tight_layout()
        path = output_path / filename
        fig.savefig(path, dpi=180)
        plt.close(fig)
        files.append(path)

    _save_plot(
        "position.png",
        "Position vs Time",
        [(analysis.x_units, "x", "#146C94"), (analysis.y_units, "y", "#19A7CE")],
        "Position",
    )
    _save_plot(
        "velocity.png",
        "Velocity vs Time",
        [(analysis.x_velocity, "vx", "#B31312"), (analysis.y_velocity, "vy", "#EA906C")],
        "Velocity",
    )
    _save_plot(
        "acceleration.png",
        "Acceleration vs Time",
        [
            (analysis.x_acceleration, "ax", "#2B2A4C"),
            (analysis.y_acceleration, "ay", "#556B2F"),
            (analysis.acceleration_magnitude, "|a|", "#7E1717"),
        ],
        "Acceleration",
    )
    return files


def export_experiment_report(
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    session: ProjectSession,
    output_path: str | Path,
) -> Path:
    summary = build_analysis_summary(analysis, track_result, calibration)
    quality_report = build_quality_report(analysis, track_result, calibration)
    analyzer_results = build_analyzer_report(analysis, track_result, calibration)
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    base_summary = (
        "# Tracker AI Experiment Report\n\n"
        f"- Experiment label: `{session.metadata.experiment_label or 'unspecified'}`\n"
        f"- Trial ID: `{session.metadata.trial_id or 'unspecified'}`\n"
        f"- Operator: `{session.metadata.operator_name or 'unspecified'}`\n"
        f"- Video: `{session.video_path}`\n"
        f"- Frame range: `{session.selected_start_frame}` to `{session.selected_end_frame if session.selected_end_frame is not None else 'end'}`\n"
        f"- Reference length: `{calibration.reference_length} {calibration.unit_label}`\n"
        f"- Reference marker enabled: `{session.reference_bbox is not None}`\n"
        f"- Smoothing: `{session.analysis_config.smoothing_method}` window `{session.analysis_config.smoothing_window}` "
        f"polyorder `{session.analysis_config.smoothing_polyorder}`\n"
        f"- Tracking profile: `{session.tracking_config.profile.value}`\n"
        f"- Robust recovery: `{session.tracking_config.robust_recovery}`\n"
        f"- Bidirectional refinement: `{session.tracking_config.bidirectional_refinement}`\n"
        f"- Tags: `{', '.join(session.metadata.tags) if session.metadata.tags else 'none'}`\n"
        f"- Notes: `{session.metadata.notes or 'none'}`\n"
        f"- Frames analyzed: `{summary.frame_count}`\n"
        f"- Average confidence: `{summary.average_confidence:.3f}`\n"
        f"- Low-confidence frames: `{summary.low_confidence_frame_count}`\n"
        f"- Suspect spans: `{summary.suspect_span_count}`\n"
        f"- Lost frames: `{summary.lost_frame_count}`\n"
        f"- Corrected frames: `{summary.corrected_frame_count}`\n"
        f"- Reacquisitions: `{summary.reacquisition_count}`\n"
        f"- Total path length: `{summary.total_path_length:.4f} {calibration.unit_label}`\n"
        f"- Net displacement: `{summary.net_displacement:.4f} {calibration.unit_label}`\n"
        f"- Peak speed: `{summary.peak_speed:.4f} {calibration.unit_label}/s`\n"
        f"- Mean speed: `{summary.mean_speed:.4f} {calibration.unit_label}/s`\n"
        f"- Peak acceleration: `{summary.peak_acceleration:.4f} {calibration.unit_label}/s^2`\n"
        f"- Mean acceleration: `{summary.mean_acceleration:.4f} {calibration.unit_label}/s^2`\n"
        f"- Review recommended: `{summary.review_recommended}`\n"
        f"- Scientific confidence mean: `{summary.scientific_confidence_mean:.3f}`\n"
        f"- QC badge: `{summary.qc_badge}`\n"
        f"- Peak position uncertainty: `{summary.peak_position_uncertainty:.4f} {calibration.unit_label}`\n"
        f"- Peak velocity uncertainty: `{summary.peak_velocity_uncertainty:.4f} {calibration.unit_label}/s`\n"
        f"- Events detected: `{summary.event_count}`\n"
    )
    reproduce_section = (
        "\n## Reproduce This Run\n\n"
        "```bash\n"
        f"{build_reproduce_command(session)}\n"
        "```\n"
    )
    quality_section = (
        "\n## Quality Notes\n\n"
        + "\n".join(f"- {note}" for note in quality_report.notes)
    )
    analyzer_section = (
        "\n\n## Experiment Modules\n\n"
        + "\n".join(
            f"- `{result.title}` ({result.confidence:.2f}): "
            + ", ".join(f"{metric.key}={metric.value:.4f} {metric.unit_label}".strip() for metric in result.metrics)
            for result in analyzer_results
        )
        if analyzer_results
        else ""
    )
    events_section = (
        "\n\n## Event Journal\n\n"
        + "\n".join(
            f"- `{event.name}` [{event.origin}] at frame `{event.frame_index}` (`{event.time_s:.3f}` s): "
            f"`{event.value:.4f} {event.unit_label}`{f' — {event.note}' if event.note else ''}"
            for event in session.event_markers
        )
        if session.event_markers
        else ""
    )
    if session.export_preferences.report_template == "compact":
        text = base_summary + quality_section
    elif session.export_preferences.report_template == "guided":
        text = (
            base_summary
            + "\n## Lab Guidance\n\n"
            + "- Review suspect and lost spans before using acceleration values in a report.\n"
            + "- Compare the raw and smoothed tracks if the peak values look physically implausible.\n"
            + reproduce_section
            + quality_section
            + analyzer_section
            + events_section
        )
    else:
        text = base_summary + reproduce_section + quality_section + analyzer_section + events_section
    path.write_text(text, encoding="utf-8")
    return path


def export_result_bundle(
    *,
    video_path: str,
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    session: ProjectSession,
    output_dir: str | Path,
    include_overlay: bool = True,
    include_debug_tracking: bool = False,
    overlay_track_result: TrackResult | None = None,
    reference_track: TrackResult | None = None,
) -> dict[str, object]:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    csv_path = export_analysis_csv(analysis, output_path / "analysis.csv", track_result=track_result)
    raw_track_path = export_raw_track_csv(analysis, track_result, output_path / "raw_track.csv")
    smoothed_track_path = export_smoothed_track_csv(analysis, track_result, output_path / "smoothed_track.csv")
    events_path = export_events_csv(analysis, output_path / "events.csv", event_markers=session.event_markers)
    plot_paths = export_analysis_plots(analysis, output_path / "plots") if session.export_preferences.include_plots else []
    summary = build_analysis_summary(analysis, track_result, calibration)
    summary_path = export_summary_json(summary, output_path / "summary.json")
    quality_report_path = export_quality_report_json(analysis, track_result, output_path / "quality_report.json", calibration=calibration)
    analyzer_results = build_analyzer_report(analysis, track_result, calibration)
    analyzer_report_path = export_analyzer_report_json(analyzer_results, output_path / "analysis_modules.json")
    report_path = export_experiment_report(analysis, track_result, calibration, session, output_path / "report.md")
    window_start = session.review_state.selected_window_start if session.review_state.selected_window_start is not None else track_result.start_frame
    window_end = (
        session.review_state.selected_window_end
        if session.review_state.selected_window_end is not None
        else track_result.end_frame
    )
    selected_window_path = export_selected_window_summary_json(
        analysis,
        window_start,
        window_end,
        output_path / "selected_window_summary.json",
    )
    session_path = session.save(output_path / "session.json")
    manifest_path = export_experiment_manifest(session, analysis, track_result, calibration, output_path / "experiment_manifest.json")
    reproduce_path = output_path / "reproduce_command.sh"
    reproduce_path.write_text(build_reproduce_command(session) + "\n", encoding="utf-8")
    debug_path: Path | None = None
    if include_debug_tracking:
        debug_path = export_tracking_debug_csv(track_result, output_path / "tracking_debug.csv")
    overlay_path: Path | None = None
    if include_overlay:
        with VideoSource(video_path) as video:
            overlay_path = export_track_overlay(
                video,
                overlay_track_result or track_result,
                output_path / "overlay.mp4",
                reference_track=reference_track,
            )
    return {
        "csv": csv_path,
        "raw_track": raw_track_path,
        "smoothed_track": smoothed_track_path,
        "events": events_path,
        "plots": plot_paths,
        "summary": summary_path,
        "quality_report": quality_report_path,
        "analyzers": analyzer_report_path,
        "report": report_path,
        "selected_window": selected_window_path,
        "session": session_path,
        "manifest": manifest_path,
        "reproduce": reproduce_path,
        "debug": debug_path,
        "overlay": overlay_path,
    }
