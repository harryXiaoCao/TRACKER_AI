from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import numpy as np

from .analysis import AnalysisResult
from .calibration import CalibrationProfile
from .reporting import build_analysis_summary, build_analyzer_report, build_quality_report
from .tracking import PairwiseMetricResult, TrackResult


@dataclass(frozen=True)
class BatchTrialReport:
    trial_id: str
    video_path: str
    qc_badge: str
    peak_speed: float
    peak_acceleration: float
    scientific_confidence_mean: float
    analyzer_count: int

    def to_dict(self) -> dict[str, object]:
        return {
            "trial_id": self.trial_id,
            "video_path": self.video_path,
            "qc_badge": self.qc_badge,
            "peak_speed": self.peak_speed,
            "peak_acceleration": self.peak_acceleration,
            "scientific_confidence_mean": self.scientific_confidence_mean,
            "analyzer_count": self.analyzer_count,
        }


@dataclass(frozen=True)
class BatchAggregateReport:
    trial_count: int
    mean_peak_speed: float
    mean_peak_acceleration: float
    mean_scientific_confidence: float
    qc_badges: dict[str, int]
    trials: tuple[BatchTrialReport, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "trial_count": self.trial_count,
            "mean_peak_speed": self.mean_peak_speed,
            "mean_peak_acceleration": self.mean_peak_acceleration,
            "mean_scientific_confidence": self.mean_scientific_confidence,
            "qc_badges": self.qc_badges,
            "trials": [trial.to_dict() for trial in self.trials],
        }


def build_batch_trial_report(
    *,
    trial_id: str,
    video_path: str,
    analysis: AnalysisResult,
    track_result: TrackResult,
    calibration: CalibrationProfile,
    pairwise_metrics: list[PairwiseMetricResult] | None = None,
) -> BatchTrialReport:
    summary = build_analysis_summary(analysis, track_result, calibration)
    quality = build_quality_report(analysis, track_result, calibration)
    analyzers = build_analyzer_report(analysis, track_result, calibration, pairwise_metrics=pairwise_metrics)
    return BatchTrialReport(
        trial_id=trial_id,
        video_path=video_path,
        qc_badge=quality.qc_badge,
        peak_speed=summary.peak_speed,
        peak_acceleration=summary.peak_acceleration,
        scientific_confidence_mean=quality.scientific_confidence_mean,
        analyzer_count=len(analyzers),
    )


def build_batch_aggregate_report(trials: list[BatchTrialReport]) -> BatchAggregateReport:
    if not trials:
        return BatchAggregateReport(
            trial_count=0,
            mean_peak_speed=0.0,
            mean_peak_acceleration=0.0,
            mean_scientific_confidence=0.0,
            qc_badges={},
            trials=(),
        )
    badges: dict[str, int] = {}
    for trial in trials:
        badges[trial.qc_badge] = badges.get(trial.qc_badge, 0) + 1
    return BatchAggregateReport(
        trial_count=len(trials),
        mean_peak_speed=float(np.mean([trial.peak_speed for trial in trials])),
        mean_peak_acceleration=float(np.mean([trial.peak_acceleration for trial in trials])),
        mean_scientific_confidence=float(np.mean([trial.scientific_confidence_mean for trial in trials])),
        qc_badges=badges,
        trials=tuple(trials),
    )


def export_batch_aggregate_report(report: BatchAggregateReport, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    return path
