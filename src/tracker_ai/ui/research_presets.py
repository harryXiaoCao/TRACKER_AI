from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ResearchPreset:
    key: str
    title: str
    description: str
    tracking_profile: str
    smoothing_window: int
    polyorder: int
    report_template: str
    review_focus: str
    setup_tip: str


PRESETS: tuple[ResearchPreset, ...] = (
    ResearchPreset(
        key="general",
        title="General Motion Study",
        description="Balanced defaults for everyday lab clips with one main target and moderate motion.",
        tracking_profile="auto",
        smoothing_window=7,
        polyorder=2,
        report_template="guided",
        review_focus="Check suspect spans and confirm the calibration line before exporting.",
        setup_tip="Use this when you want a safe baseline before specializing for a specific apparatus.",
    ),
    ResearchPreset(
        key="projectile",
        title="Projectile / Ballistics",
        description="Fast events with a clean launch, short airtime, and strong interest in apex and acceleration.",
        tracking_profile="marker",
        smoothing_window=5,
        polyorder=2,
        report_template="research",
        review_focus="Keep the smoothing window tight and mark launch, apex, and impact frames manually.",
        setup_tip="Great for launches, drops, trajectories, and impact timing experiments.",
    ),
    ResearchPreset(
        key="pendulum",
        title="Pendulum / Oscillation",
        description="Repeated motion where period, damping, and turning points matter more than one-off peaks.",
        tracking_profile="template",
        smoothing_window=9,
        polyorder=3,
        report_template="research",
        review_focus="Track at least two full oscillations and mark release plus turning points for validation.",
        setup_tip="Use an axis-aware calibration when angular interpretation matters.",
    ),
    ResearchPreset(
        key="collision",
        title="Collision / Multi-Object",
        description="Two or more bodies interacting with pairwise distance and relative speed analysis.",
        tracking_profile="marker",
        smoothing_window=5,
        polyorder=2,
        report_template="research",
        review_focus="Add every moving body you care about before running analysis and mark pre/post-contact frames.",
        setup_tip="Best for carts, beads, impacts, and separation timing studies.",
    ),
    ResearchPreset(
        key="rotation",
        title="Rotation / Circular Motion",
        description="Steady rotational or orbital motion where radius consistency and angular speed matter.",
        tracking_profile="marker",
        smoothing_window=9,
        polyorder=3,
        report_template="compact",
        review_focus="Use a stable reference marker whenever the camera or apparatus may drift.",
        setup_tip="Helpful for rotors, turntables, and circular path experiments.",
    ),
)


PRESET_BY_KEY = {preset.key: preset for preset in PRESETS}
