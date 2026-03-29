from __future__ import annotations

import argparse
import json
from pathlib import Path

from .core.analysis import AnalysisConfig
from .core.batch import build_batch_aggregate_report, build_batch_trial_report, export_batch_aggregate_report
from .core.calibration import CalibrationProfile
from .core.experiment import run_experiment_analysis, run_multi_object_experiment
from .core.export import export_multi_object_bundle, export_result_bundle
from .core.session import EventMarker, ExportPreferences, ExperimentMetadata, ProjectSession, ProvenanceMetadata, SessionReviewState
from .core.tracking import BBox, TrackedObject, TrackingConfig, TrackingProfile
from .core.video import VideoSource


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="tracker-ai")
    subparsers = parser.add_subparsers(dest="command", required=True)

    analyze = subparsers.add_parser("analyze", help="Track a single object and export analysis outputs.")
    analyze.add_argument("--video", required=True, help="Path to the input video.")
    analyze.add_argument("--bbox", nargs=4, type=float, required=True, metavar=("X", "Y", "W", "H"))
    analyze.add_argument("--reference-bbox", nargs=4, type=float, metavar=("X", "Y", "W", "H"))
    analyze.add_argument(
        "--scale-points",
        nargs=4,
        type=float,
        required=True,
        metavar=("X1", "Y1", "X2", "Y2"),
        help="Known reference line in pixel coordinates.",
    )
    analyze.add_argument("--reference-length", type=float, required=True, help="Real-world reference length.")
    analyze.add_argument("--unit", default="m", help="Physical unit label.")
    analyze.add_argument("--output-dir", required=True, help="Directory for exported outputs.")
    analyze.add_argument("--start-frame", type=int, default=0)
    analyze.add_argument("--end-frame", type=int, default=None, help="Last frame to analyze (inclusive).")
    analyze.add_argument("--window", type=int, default=7, help="Savitzky-Golay smoothing window.")
    analyze.add_argument("--polyorder", type=int, default=2, help="Savitzky-Golay polynomial order.")
    analyze.add_argument("--experiment-label", default="", help="Experiment or lab name.")
    analyze.add_argument("--trial-id", default="", help="Trial identifier.")
    analyze.add_argument("--operator", default="", help="Operator name.")
    analyze.add_argument("--notes", default="", help="Freeform experiment notes.")
    analyze.add_argument("--tags", nargs="*", default=[], help="Optional tags for the run.")
    analyze.add_argument(
        "--tracking-profile",
        choices=[profile.value for profile in TrackingProfile],
        default=TrackingProfile.AUTO.value,
        help="Tracking profile to use for the analysis.",
    )
    analyze.add_argument(
        "--debug-tracking",
        action="store_true",
        help="Export per-frame tracking state and score details.",
    )
    analyze.add_argument(
        "--disable-bidirectional-refinement",
        action="store_true",
        help="Disable the offline backward refinement pass.",
    )
    analyze.add_argument(
        "--skip-overlay",
        action="store_true",
        help="Skip exporting the annotated overlay video.",
    )
    analyze.add_argument(
        "--skip-plots",
        action="store_true",
        help="Skip exporting plot images.",
    )
    analyze.add_argument(
        "--report-template",
        choices=["research", "guided", "compact"],
        default="research",
        help="Report style to export.",
    )
    analyze.add_argument(
        "--extra-object",
        nargs=6,
        action="append",
        metavar=("TRACK_ID", "NAME", "X", "Y", "W", "H"),
        help="Add an extra tracked object by id, display name, and bbox.",
    )
    batch = subparsers.add_parser("batch", help="Run a batch of session or manifest-based analyses.")
    batch.add_argument("--manifest", help="Path to a JSON manifest of sessions to process.")
    batch.add_argument("--session", nargs="*", default=[], help="One or more saved session files to process.")
    batch.add_argument("--output-dir", required=True, help="Directory where per-trial outputs will be created.")
    batch.add_argument("--skip-overlay", action="store_true", help="Skip overlay exports for the batch.")

    return parser.parse_args()


def run_analysis(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    bbox = BBox(*args.bbox)
    calibration = CalibrationProfile.from_points(
        *args.scale_points,
        reference_length=args.reference_length,
        unit_label=args.unit,
    )
    config = AnalysisConfig(smoothing_window=args.window, smoothing_polyorder=args.polyorder)
    tracking_config = TrackingConfig(
        profile=TrackingProfile(args.tracking_profile),
        bidirectional_refinement=not args.disable_bidirectional_refinement,
        debug_tracking=bool(args.debug_tracking),
    )
    scale_points = tuple(float(value) for value in args.scale_points)
    reference_bbox = BBox(*args.reference_bbox) if args.reference_bbox else None
    metadata = ExperimentMetadata(
        experiment_label=args.experiment_label,
        trial_id=args.trial_id,
        operator_name=args.operator,
        notes=args.notes,
        tags=tuple(args.tags or []),
    )

    extra_objects = [
        TrackedObject(track_id=item[0], name=item[1], bbox=BBox(float(item[2]), float(item[3]), float(item[4]), float(item[5])), kind="secondary")
        for item in (args.extra_object or [])
    ]

    with VideoSource(args.video) as video:
        if extra_objects:
            multi = run_multi_object_experiment(
                video,
                [TrackedObject(track_id="primary", name="Primary Object", bbox=bbox, kind="primary"), *extra_objects],
                calibration,
                config,
                tracking_config,
                start_frame=args.start_frame,
                end_frame=args.end_frame,
                reference_bbox=reference_bbox,
                primary_track_id="primary",
            )
            experiment = None
        else:
            experiment = run_experiment_analysis(
                video,
                primary_bbox=bbox,
                reference_bbox=reference_bbox,
                calibration=calibration,
                analysis_config=config,
                tracking_config=tracking_config,
                start_frame=args.start_frame,
                end_frame=args.end_frame,
            )

    session = ProjectSession(
        video_path=args.video,
        initial_bbox=bbox,
        reference_bbox=reference_bbox,
        calibration=calibration,
        analysis_config=config,
        tracking_config=(experiment.display_track.tracking_config if experiment is not None else multi.display_tracks["primary"].tracking_config),
        metadata=metadata,
        selected_start_frame=args.start_frame,
        selected_end_frame=args.end_frame,
        scale_points=scale_points,
        track_quality=(experiment.analysis_track.quality if experiment is not None else multi.analysis_tracks["primary"].quality),
        event_markers=tuple(
            EventMarker(
                name=event.name,
                frame_index=event.frame_index,
                time_s=event.time_s,
                value=event.value,
                unit_label=event.unit_label,
                axis=event.axis,
                note=event.note,
            )
            for event in (experiment.analysis.events if experiment is not None else multi.analyses["primary"].events)
        ),
        export_preferences=ExportPreferences(
            include_overlay=not args.skip_overlay,
            include_debug_tracking=bool(args.debug_tracking),
            include_plots=not args.skip_plots,
            report_template=args.report_template,
        ),
        provenance=ProvenanceMetadata(video_path_snapshot=args.video),
        review_state=SessionReviewState(last_frame_index=args.start_frame),
        additional_objects=tuple(extra_objects),
    )
    if experiment is not None:
        bundle = export_result_bundle(
            video_path=args.video,
            analysis=experiment.analysis,
            track_result=experiment.analysis_track,
            calibration=calibration,
            session=session,
            output_dir=output_dir,
            include_overlay=not args.skip_overlay,
            include_debug_tracking=args.debug_tracking,
            overlay_track_result=experiment.display_track,
            reference_track=experiment.reference_track,
        )
    else:
        bundle = export_multi_object_bundle(multi, calibration, session, output_dir)

    if experiment is not None:
        print(f"CSV: {bundle['csv']}")
        if bundle["overlay"] is not None:
            print(f"Overlay: {bundle['overlay']}")
        print(f"Summary: {bundle['summary']}")
        print(f"Report: {bundle['report']}")
        print(f"Session: {bundle['session']}")
        if bundle["debug"] is not None:
            print(f"Tracking debug: {bundle['debug']}")
        if bundle["plots"]:
            print("Plots:")
            for plot_file in bundle["plots"]:
                print(f"  - {plot_file}")
        print(f"Frames tracked: {len(experiment.display_track.observations)}")
        print(f"Frame range: {experiment.display_track.start_frame} -> {experiment.display_track.end_frame}")
        print(f"Average confidence: {experiment.analysis_track.average_confidence:.3f}")
    else:
        print(f"Multi-object export root: {output_dir}")
        print(f"Pairwise metrics: {bundle['pairwise_metrics']}")
    return 0


def _load_sessions_from_args(args: argparse.Namespace) -> list[ProjectSession]:
    sessions: list[ProjectSession] = []
    if args.manifest:
        payload = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        for session_path in payload.get("sessions", []):
            sessions.append(ProjectSession.load(session_path))
    for session_path in args.session:
        sessions.append(ProjectSession.load(session_path))
    if not sessions:
        raise ValueError("Provide at least one --session or a --manifest with sessions.")
    return sessions


def run_batch(args: argparse.Namespace) -> int:
    output_root = Path(args.output_dir)
    output_root.mkdir(parents=True, exist_ok=True)
    sessions = _load_sessions_from_args(args)
    batch_trials = []

    for index, session in enumerate(sessions, start=1):
        trial_name = session.metadata.trial_id or session.metadata.experiment_label or Path(session.video_path).stem or f"trial_{index:02d}"
        trial_output = output_root / trial_name
        with VideoSource(session.video_path) as video:
            if session.additional_objects:
                multi = run_multi_object_experiment(
                    video,
                    [TrackedObject(track_id="primary", name="Primary Object", bbox=session.initial_bbox, kind="primary"), *list(session.additional_objects)],
                    session.calibration,
                    session.analysis_config,
                    session.tracking_config,
                    start_frame=session.selected_start_frame,
                    end_frame=session.selected_end_frame,
                    reference_bbox=session.reference_bbox,
                    primary_track_id="primary",
                )
                bundle = export_multi_object_bundle(multi, session.calibration, session, trial_output)
                batch_trials.append(
                    build_batch_trial_report(
                        trial_id=trial_name,
                        video_path=session.video_path,
                        analysis=multi.analyses["primary"],
                        track_result=multi.analysis_tracks["primary"],
                        calibration=session.calibration,
                        pairwise_metrics=multi.pairwise_metrics,
                    )
                )
            else:
                experiment = run_experiment_analysis(
                    video,
                    primary_bbox=session.initial_bbox,
                    reference_bbox=session.reference_bbox,
                    calibration=session.calibration,
                    analysis_config=session.analysis_config,
                    tracking_config=session.tracking_config,
                    start_frame=session.selected_start_frame,
                    end_frame=session.selected_end_frame,
                )
                bundle = export_result_bundle(
                    video_path=session.video_path,
                    analysis=experiment.analysis,
                    track_result=experiment.analysis_track,
                    calibration=session.calibration,
                    session=session,
                    output_dir=trial_output,
                    include_overlay=not args.skip_overlay,
                    include_debug_tracking=session.tracking_config.debug_tracking,
                    overlay_track_result=experiment.display_track,
                    reference_track=experiment.reference_track,
                )
                batch_trials.append(
                    build_batch_trial_report(
                        trial_id=trial_name,
                        video_path=session.video_path,
                        analysis=experiment.analysis,
                        track_result=experiment.analysis_track,
                        calibration=session.calibration,
                    )
                )
        status_target = bundle["summary"] if "summary" in bundle else bundle["pairwise_metrics"]
        print(f"[{index}/{len(sessions)}] {trial_name}: {status_target}")
    aggregate = build_batch_aggregate_report(batch_trials)
    report_path = export_batch_aggregate_report(aggregate, output_root / "batch_summary.json")
    print(f"Batch summary: {report_path}")
    return 0


def main() -> int:
    args = _parse_args()
    if args.command == "analyze":
        return run_analysis(args)
    if args.command == "batch":
        return run_batch(args)
    raise ValueError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
