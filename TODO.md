# Tracker AI Swift Migration TODO

## Project Introduction

Tracker AI is a lab and research tool for tracking the motion of objects in video so students, educators, and researchers can turn recorded experiments into quantitative measurements.

In practical terms, the app helps a user:

- load a video of a moving object
- define a physical scale from the video image
- mark the target object and optional secondary objects
- track motion frame by frame
- review drift, lost tracking spans, and manual corrections
- compute kinematic quantities such as position, velocity, acceleration, path length, and event timings
- export reproducible research artifacts including tables, summaries, reports, and session files

The repository currently contains two major product layers:

- a mature Python analysis engine and desktop workflow under `src/tracker_ai`
- a newer native macOS SwiftUI/AppKit application under `Sources/TrackerAIMac`

The current mission of this codebase is to move the product from a Python-based research desktop tool into a fully native Swift macOS application suitable for long-term productization and eventual App Store distribution, while preserving scientific behavior, reproducibility, and export compatibility during the transition.

## Current Snapshot

This repository is in a real hybrid state, not an early prototype:

- The Python app under `src/tracker_ai` is still the scientific engine of record.
- The native macOS app under `Sources/TrackerAIMac` already owns the product shell, direct-on-video drawing workflow, session/workspace loading and saving, results browsing, and native research export/report generation.
- `Sources/TrackerAIMac/Core/PythonEngineBridge.swift` still launches `python3 -m tracker_ai.cli analyze` for actual analysis runs.
- The Swift side already reconstructs a lot of post-analysis science natively:
  - smoothing and derived kinematics
  - QC summaries
  - analyzer summaries
  - pairwise metric reconstruction
  - native report and bundle export
- The Python side still owns the runtime-critical pieces:
  - video decode/frame iteration
  - robust object tracking
  - reference-marker correction during tracking
  - multi-object experiment execution
  - authoritative CLI/batch execution path
  - benchmark harness
- Python coverage is currently much stronger than Swift coverage.
- `python3 -m pytest -q tests` passes locally: `20 passed`.

## What Is Already Meaningfully Native

- [x] SwiftUI/AppKit app shell and navigation
- [x] Native workspace rail and session/workspace JSON handling
- [x] Native direct-on-video drawing for target, scale, corrections, and companion objects
- [x] Native review journal, manual event journal, and results surfaces
- [x] Native post-processing of `analysis.csv` into richer summaries/QC/analyzers
- [x] Native research export packaging and markdown reporting
- [x] Native batch summary export on top of session-backed workspace clips

## Main Remaining Migration Boundary

The biggest remaining boundary is: Swift can present, reconstruct, and export results, but Python still produces the tracked observations and the primary analysis payload.

The goal of the next migration phase should be to eliminate `PythonEngineBridge.runAnalysis(...)` as the production path, then progressively retire the Python CLI from the app build and App Store story.

---

## Migration Backlog

### 01. Port native video ingestion and frame timing

- [x] Create a Swift-native video reader abstraction that can replace `tracker_ai.core.video.VideoSource`.
- [x] Support random access by frame index, sequential iteration, and timestamp extraction.
- [x] Match the Python behavior for `start_frame` / `end_frame` inclusive ranges.
- [x] Preserve source video metadata needed by the workspace player and exports.
- [x] Add fixture-based tests proving frame count and timestamp parity against sample clips.

### 02. Port the full calibration model, not just single-line scaling

- [x] Create a Swift-native equivalent of `CalibrationProfile` with parity for:
  - `single_line`
  - `two_axis`
  - `marker_size`
  - `homography`
  - origin offsets
  - axis rotation
  - axis inversion
- [x] Port `transform_point(...)` behavior exactly.
- [x] Preserve serialized session compatibility with existing Python JSON files.
- [x] Add unit tests covering each calibration mode and coordinate transform edge cases.

### 03. Bring Swift setup UI to parity with the Python calibration controls

- [x] Add advanced calibration controls to the Swift setup panel for origin, axis angle, marker size, homography, invert X, and invert Y.
- [x] Wire those controls into `SessionSnapshot` and native processing instead of dropping them.
- [x] Make `advancedMode` actually expose meaningful scientific setup, not just a shell toggle.
- [x] Add validation and inline error messaging for malformed homography input.

### 04. Add native reference-marker authoring and reference track workflow

- [x] Add a first-class “Draw Reference Marker” workflow to the Swift setup UI.
- [x] Surface reference marker state in the workspace HUD and setup forms.
- [x] Keep `referenceBox` editable, clearable, and session-persistent.
- [x] Thread reference marker data through native analysis and export.
- [x] Add regression tests for sessions containing `reference_bbox`.

### 05. Port the full tracking configuration schema to Swift

- [x] Add Swift-native equivalents for the Python `TrackingConfig` fields that are not yet surfaced or preserved.
- [x] Include thresholds and recovery parameters such as:
  - search margins
  - detection thresholds
  - suspect/recovery frame counts
  - interpolation settings
  - template update controls
  - marker confidence bias
- [x] Ensure `SessionSnapshot` can round-trip every field needed for reproducible runs.
- [x] Decide which controls stay user-facing vs. internal-only.
  Swift now keeps `profile`, `robust recovery`, `bidirectional refinement`, and debug export user-facing, while preserving deeper tracker thresholds/tuning internally in the session schema and reproduce path.

### 06. Port single-object tracker runtime from Python/OpenCV to Swift

- [x] Reimplement the `RobustHybridTracker` core in Swift.
- [x] Cover template matching, motion prediction, patch extraction, scoring, and state transitions.
- [x] Match Python output fields closely enough to preserve downstream scientific calculations.
- [x] Keep the tracker modular so future detector-assisted recovery can slot in cleanly.
- [x] Define acceptable parity targets against the benchmark clips before replacing Python in production.
  Native runtime work now lives in `Sources/TrackerAIMac/Core/NativeTrackingRuntime.swift`, with modular candidate providers for template-grid and foreground search, and the current benchmark release gate codified in `tests/TrackerAIMacTests/NativeTrackingRuntimeTests.swift` via `NativeTrackingParityTargets`.

### 07. Port recovery, reacquisition, and tracker state logic

- [x] Recreate Python tracking states: `tracking`, `suspect`, `lost`, `reacquired`.
- [x] Port robust recovery search modes: normal, expanded, and full-frame.
- [x] Port failure reason generation and debug ranking metadata.
- [x] Preserve reacquisition counts and review recommendations used by QC/reporting.
- [x] Add targeted tests using synthetic failure cases and benchmark clips.
  Native recovery-state coverage now lives in `Sources/TrackerAIMac/Core/NativeTrackingRuntime.swift` and `tests/TrackerAIMacTests/NativeTrackingRuntimeTests.swift`, including synthetic loss/reacquisition fixtures plus benchmark-backed review/QC assertions for occlusion and re-entry clips.

### 08. Port interpolation and track-quality derivation as first-class runtime behavior

- [ ] Move short-gap interpolation out of reconstruction-only logic and into the native runtime path.
- [ ] Keep parity with Python’s interpolation gap limits and confidence penalties.
- [ ] Ensure `TrackQualitySnapshot` is derived from native observations, not just rebuilt from CSV.
- [ ] Validate lost/suspect/corrected span generation against existing Python fixtures.

### 09. Port reference-motion correction into the native tracker pipeline

- [ ] Recreate `apply_reference_motion_correction(...)` in the native runtime path.
- [ ] Track the reference object with its own native config/profile rules.
- [ ] Preserve corrected observation confidence and failure-reason semantics.
- [ ] Verify parity for apparatus drift/camera-jitter scenarios.

### 10. Port multi-object experiment orchestration

- [ ] Create a native equivalent of `run_multi_object_experiment(...)`.
- [ ] Track primary plus secondary objects in one coordinated run.
- [ ] Carry track IDs, names, and kinds through results and exports.
- [ ] Keep the reference marker compatible with multi-object runs.
- [ ] Replace the current “Python for tracking, Swift for pairwise reconstruction” split with one native path.

### 11. Port native pairwise metrics from reconstruction helper to authoritative analysis output

- [ ] Make pairwise metrics an official native analysis artifact, not just a post-load reconstruction.
- [ ] Preserve collision frame, minimum separation, relative speed, and center-of-mass metrics.
- [ ] Match CSV export schema expected by current results screens and reports.
- [ ] Add tests using sessions with companion objects and pairwise expectations.

### 12. Port kinematic analysis as a primary native pipeline stage

- [ ] Promote `NativeScientificProcessor` into the authoritative runtime analysis stage.
- [ ] Confirm parity for smoothing, velocities, accelerations, uncertainties, and angle calculations.
- [ ] Match Python handling of very short clips and edge-of-window smoothing cases.
- [ ] Add fixture comparisons between Python `AnalysisResult` rows and Swift `AnalysisRow` outputs.

### 13. Port derived event generation and selected-window analysis

- [ ] Make native derived events the canonical source of events for Swift-run analyses.
- [ ] Ensure peak speed, peak acceleration, apex, zero crossings, and window summaries match Python behavior closely enough.
- [ ] Preserve manual event merge behavior without duplicating events.
- [ ] Add tests for event timing and selected-window summary calculations.

### 14. Port built-in analyzers and experiment classification fully

- [ ] Confirm every Python analyzer has a Swift-native counterpart or explicit replacement.
- [ ] Validate projectile, pendulum, rotation, and pairwise/collision logic against known fixtures.
- [ ] Make experiment classification stable and test-backed, not just UI-friendly.
- [ ] Document any intentional deviations from Python analyzer outputs.

### 15. Replace `PythonEngineBridge.runAnalysis(...)` with a native run coordinator

- [ ] Introduce a Swift-native analysis coordinator that drives the full run from session inputs to result bundle.
- [ ] Keep `PythonEngineBridge` limited to legacy import support during transition.
- [ ] Preserve progress reporting, cancellation, and error propagation in `AppModel`.
- [ ] Add a feature flag if needed so native and Python engines can be compared side-by-side during migration.

### 16. Port correction replay as a native rerun workflow

- [ ] Recreate the Python `apply_correction` workflow natively.
- [ ] Support rerunning from the correction frame forward using the corrected bbox as the new seed.
- [ ] Preserve correction anchors in session state and QC spans.
- [ ] Make correction replay work for primary and, later, companion objects.
- [ ] Add tests proving corrected reruns actually improve or change downstream observations.

### 17. Close the remaining setup/review parity gaps from the Qt app

- [ ] Review `src/tracker_ai/ui/main_window.py` and port any remaining user-facing scientific controls still missing in Swift.
- [ ] Confirm parity for:
  - advanced calibration editing
  - reference marker flows
  - track selector behavior
  - review navigation helpers
  - frame-HUD scientific context
- [ ] Remove or redesign any UI concepts that only existed to accommodate Qt/Python constraints.

### 18. Port the batch engine to Swift-native execution

- [ ] Replace Python CLI batch execution with a native batch coordinator operating on `WorkspaceClip` and `SessionSnapshot`.
- [ ] Keep per-trial output folder semantics and aggregate summary parity.
- [ ] Support mixed single-object and multi-object sessions natively.
- [ ] Preserve reproducibility metadata and report generation for each batch trial.

### 19. Port the benchmark and regression harness to Swift

- [ ] Reuse `sample_data/benchmark_manifest.json` from Swift.
- [ ] Build a native benchmark runner for the real-world failure-mode clips.
- [ ] Measure center error, IoU, lost rate, and reacquisition latency natively.
- [ ] Treat benchmark parity as a release gate before removing the Python backend.

### 20. Create Swift-native test coverage before large engine replacement

- [ ] Add a proper Swift test target to the package and/or Xcode project.
- [ ] Port critical Python tests into Swift fixture-based tests.
- [ ] Add golden-file tests for session JSON, workspace JSON, analysis rows, summary JSON, and report markdown.
- [ ] Add cross-language comparison tests while both engines coexist.

### 21. Remove App Store blockers caused by the embedded Python dependency

- [ ] Eliminate runtime dependence on invoking `/usr/bin/python3` from the shipping app path.
- [ ] Remove any product requirement for a local Python environment, Conda environment, or editable install.
- [ ] Confirm all research exports can be generated from the native app alone.
- [ ] Review sandbox, entitlements, and file access with the Python runtime removed from the critical path.

### 22. Harden packaging, signing, and distribution around the native-only app

- [ ] Make `scripts/build_native_macos_app.sh` the primary supported build path.
- [ ] Add release checks for app bundle completeness, assets, plist values, and entitlements.
- [ ] Prepare for notarization, update delivery, crash reporting, and licensing once the native engine is self-contained.
- [ ] Document the final supported architecture for App Store and direct distribution builds.

---

## Recommended Execution Order

If the goal is to maximize progress while reducing risk, tackle the migration in this order:

1. 01-05: finish the data model, calibration, and config parity work.
2. 06-10: replace the Python tracking/runtime path.
3. 11-16: finish scientific parity and native rerun/correction workflows.
4. 17-20: close workflow parity and build a real Swift regression net.
5. 21-22: finalize commercialization and remove Python as a shipping dependency.

## Definition Of Done For The Swift Migration

The Python-to-Swift transformation is only truly complete when all of the following are true:

- [ ] The macOS app can analyze a video end-to-end without launching Python.
- [ ] Existing session/workspace JSON files still load correctly.
- [ ] Native results match Python closely enough on synthetic tests and benchmark clips.
- [ ] Native batch execution replaces `tracker_ai cli batch` for product usage.
- [ ] The shipping app no longer depends on a local Python runtime.
- [ ] A Swift regression suite exists for the core scientific pipeline.
