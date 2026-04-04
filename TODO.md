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
- `Sources/TrackerAIMac/Core/PythonEngineBridge.swift` is now limited to compatibility loading/saving for legacy JSON and exported bundles; the shipping app no longer shells out to `/usr/bin/python3`.
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

- [x] Move short-gap interpolation out of reconstruction-only logic and into the native runtime path.
- [x] Keep parity with Python’s interpolation gap limits and confidence penalties.
- [x] Ensure `TrackQualitySnapshot` is derived from native observations, not just rebuilt from CSV.
- [x] Validate lost/suspect/corrected span generation against existing Python fixtures.
  Shared runtime derivation now lives in `NativeTrackRuntimeDerivation`, is reused by both `NativeSingleObjectTrackingRunner` and `NativeTrackingPipeline`, and is covered by focused Swift tests for interpolation penalties, span/reacquisition metadata, and reconstruction config limits.

### 09. Port reference-motion correction into the native tracker pipeline

- [x] Recreate `apply_reference_motion_correction(...)` in the native runtime path.
- [x] Track the reference object with its own native config/profile rules.
- [x] Preserve corrected observation confidence and failure-reason semantics.
- [x] Verify parity for apparatus drift/camera-jitter scenarios.
  Native reference correction now lives in `Sources/TrackerAIMac/Core/NativeTrackingRuntime.swift`, with reference-aware runner entry points plus Swift regression coverage for correction semantics and synthetic drift stabilization in `tests/TrackerAIMacTests/NativeTrackingRuntimeTests.swift`.

### 10. Port multi-object experiment orchestration

- [x] Create a native equivalent of `run_multi_object_experiment(...)`.
- [x] Track primary plus secondary objects in one coordinated run.
- [x] Carry track IDs, names, and kinds through results and exports.
- [x] Keep the reference marker compatible with multi-object runs.
- [x] Replace the current “Python for tracking, Swift for pairwise reconstruction” split with one native path.
  Native multi-object orchestration now lives in `NativeMultiObjectTrackingRunner`, drives both single-run and workspace batch execution from Swift, exports per-track native bundles with coordinated pairwise metrics, and is covered by Swift regression tests for reference-aware multi-object runs.

### 11. Port native pairwise metrics from reconstruction helper to authoritative analysis output

- [x] Make pairwise metrics an official native analysis artifact, not just a post-load reconstruction.
- [x] Preserve collision frame, minimum separation, relative speed, and center-of-mass metrics.
- [x] Match CSV export schema expected by current results screens and reports.
- [x] Add tests using sessions with companion objects and pairwise expectations.
  Native pairwise metrics now persist as the authoritative `pairwise_metrics.csv` experiment artifact at bundle root, reload through `PythonEngineBridge.loadBundle(...)` instead of being dropped and rebuilt later, carry center-of-mass coordinates alongside collision/min-separation/relative-speed semantics, and are covered by focused Swift regressions for both live multi-object runs and export/reload persistence.

### 12. Port kinematic analysis as a primary native pipeline stage

- [x] Promote `NativeScientificProcessor` into the authoritative runtime analysis stage.
- [x] Confirm parity for smoothing, velocities, accelerations, uncertainties, and angle calculations.
- [x] Match Python handling of very short clips and edge-of-window smoothing cases.
- [x] Add fixture comparisons between Python `AnalysisResult` rows and Swift `AnalysisRow` outputs.
  Native kinematic processing now runs directly from `NativeTrackingObservation` output inside `NativeMultiObjectTrackingRunner`, gradient/smoothing behavior was tightened to match Python edge cases, and fixture-backed Swift tests now compare native rows against Python-generated analysis rows for short clips, penalty-bearing tracks, and smoothing-window corner cases.

### 13. Port derived event generation and selected-window analysis

- [x] Make native derived events the canonical source of events for Swift-run analyses.
- [x] Ensure peak speed, peak acceleration, apex, zero crossings, and window summaries match Python behavior closely enough.
- [x] Preserve manual event merge behavior without duplicating events.
- [x] Add tests for event timing and selected-window summary calculations.
  Native derived-event and selected-window calculations now live in `NativeScientificProcessor`, Swift exports honor the selected review window instead of the broader run range, manual markers win when they overlap a derived event, and focused Swift regressions cover canonical event timing plus selected-window summary export.

### 14. Port built-in analyzers and experiment classification fully

- [x] Confirm every Python analyzer has a Swift-native counterpart or explicit replacement.
- [x] Validate projectile, pendulum, rotation, and pairwise/collision logic against known fixtures.
- [x] Make experiment classification stable and test-backed, not just UI-friendly.
- [x] Document any intentional deviations from Python analyzer outputs.
  Swift now has fixture-backed parity coverage for all six built-in analyzer IDs (`projectile`, `pendulum`, `circular`, `incline`, `spring`, `collision`), and native classification uses an explicit specificity tie-break so rotation-style tracks prefer the `circular` analyzer and pairwise impact tracks prefer `collision` when confidence ties with broader overlap analyzers such as `projectile` or `incline`.

### 15. Replace `PythonEngineBridge.runAnalysis(...)` with a native run coordinator

- [x] Introduce a Swift-native analysis coordinator that drives the full run from session inputs to result bundle.
- [x] Keep `PythonEngineBridge` limited to legacy import support during transition.
- [x] Preserve progress reporting, cancellation, and error propagation in `AppModel`.
- [x] Add a feature flag if needed so native and Python engines can be compared side-by-side during migration.
  A standalone engine toggle was not needed once the native coordinator became the production path; instead, each native export is reloaded through the legacy importer so compatibility can still be checked without keeping Python in the execution loop.
  Native execution now flows through `Sources/TrackerAIMac/Core/NativeAnalysisCoordinator.swift`, which opens the video, runs native multi-object tracking, exports the research bundle, then reloads that bundle through the legacy importer for compatibility validation; `PythonEngineBridge` no longer owns the production run path, the setup UI now reflects native execution with progress/cancel affordances, and focused Swift coordinator tests plus the Python regression suite cover the migrated boundary.

### 16. Port correction replay as a native rerun workflow

- [x] Recreate the Python `apply_correction` workflow natively.
- [x] Support rerunning from the correction frame forward using the corrected bbox as the new seed.
- [x] Preserve correction anchors in session state and QC spans.
- [x] Make correction replay work for primary and, later, companion objects.
- [x] Add tests proving corrected reruns actually improve or change downstream observations.
  Native correction replay now lives in `AppModel.applyCorrectionReplay(...)` and `NativeSingleObjectTrackingRunner.replayCorrection(...)`, stores track-aware correction anchors in session JSON, replays the selected track from the correction frame forward before rebuilding native QC/pairwise/report state, and is covered by focused Swift regression tests for downstream observation replacement plus coordinator export smoke coverage.

### 17. Close the remaining setup/review parity gaps from the Qt app

- [x] Review `src/tracker_ai/ui/main_window.py` and port any remaining user-facing scientific controls still missing in Swift.
- [x] Confirm parity for:
  - advanced calibration editing
  - reference marker flows
  - track selector behavior
  - review navigation helpers
  - frame-HUD scientific context
- [x] Remove or redesign any UI concepts that only existed to accommodate Qt/Python constraints.
  Swift setup/review parity is now closed around the remaining Qt-era workflow helpers: setup gained `Use Current` frame capture for start/end bounds, the workspace and review surfaces now expose `Next Problem` / `Next Correction` navigation, multi-track runs can switch the active track directly from the workspace HUD and review queue instead of only from Results, and the workspace HUD now shows per-frame scientific context (time, track, state, tracker/scientific confidence, bbox, speed, acceleration, reference state) rather than the older Qt shell's split HUD/status labels. Advanced calibration editing and reference-marker authoring stayed native-first, while the Qt-only division between results selectors and review navigation was intentionally redesigned into the Swift workspace/review panels instead of copied verbatim. Focused Swift regressions for range capture, review navigation, and track-aware HUD context now live in `tests/TrackerAIMacTests/SetupReviewParityTests.swift`.

### 18. Port the batch engine to Swift-native execution

- [x] Replace Python CLI batch execution with a native batch coordinator operating on `WorkspaceClip` and `SessionSnapshot`.
- [x] Keep per-trial output folder semantics and aggregate summary parity.
- [x] Support mixed single-object and multi-object sessions natively.
- [x] Preserve reproducibility metadata and report generation for each batch trial.
  Native workspace batch execution now flows through `Sources/TrackerAIMac/Core/NativeBatchCoordinator.swift`, which accepts session-backed `WorkspaceClip` entries, runs each trial through the native analysis coordinator, preserves per-trial export directories plus aggregate `batch_summary.json` / `batch_comparison.json` / `batch_report.md` artifacts, and normalizes unique trial folder names without falling back to the Python CLI. `AppModel.runWorkspaceBatchAnalysis()` now delegates to that coordinator instead of owning the batch loop inline, so mixed single-object and multi-object sessions share the same Swift-native execution path while still reusing native post-processing for summaries, QC, pairwise metrics, reproduce commands, and track-level report bundles. Focused regression coverage now lives in `tests/TrackerAIMacTests/NativeBatchCoordinatorTests.swift`, and the full Swift suite passes with this batch migration in place.

### 19. Port the benchmark and regression harness to Swift

- [x] Reuse `sample_data/benchmark_manifest.json` from Swift.
- [x] Build a native benchmark runner for the real-world failure-mode clips.
- [x] Measure center error, IoU, lost rate, and reacquisition latency natively.
- [x] Treat benchmark parity as a release gate before removing the Python backend.
  Swift benchmark/regression coverage now lives in `Sources/TrackerAIMac/Core/NativeTrackingBenchmark.swift`, which loads `sample_data/benchmark_manifest.json`, computes per-clip and suite metrics (center error, IoU, lost rate, reacquisition latency), and provides a reusable native runner for the real benchmark clips. The Swift tests no longer duplicate manifest parsing or metric math ad hoc: `tests/TrackerAIMacTests/NativeTrackingRuntimeTests.swift` now covers manifest/tag coverage, metric computation, suite aggregation, and the existing benchmark-backed release-gate path, while coordinator and batch regressions reuse the same manifest loader for end-to-end native execution smoke coverage.

### 20. Create Swift-native test coverage before large engine replacement

- [x] Add a proper Swift test target to the package and/or Xcode project.
- [x] Port critical Python tests into Swift fixture-based tests.
- [x] Add golden-file tests for session JSON, workspace JSON, analysis rows, summary JSON, and report markdown.
- [x] Add cross-language comparison tests while both engines coexist.
  The existing SwiftPM `TrackerAIMacTests` target now carries dedicated migration coverage in `tests/TrackerAIMacTests/MigrationBacklog20Tests.swift`, backed by committed golden artifacts under `tests/TrackerAIMacTests/Fixtures/MigrationBacklog20/`. Those tests lock down Swift-native session/workspace serialization plus exported analysis/summary/report artifacts, and they run live Python-vs-Swift parity checks for both compatibility-bridge session loading and scientific row generation while the two engines still coexist. The session compatibility work also exposed and fixed decode gaps for Python-authored metadata and correction track IDs in `Sources/TrackerAIMac/Core/Domain.swift`, so the new cross-language suite is exercising the real shared contract instead of a lossy subset.

### 21. Remove App Store blockers caused by the embedded Python dependency

- [x] Eliminate runtime dependence on invoking `/usr/bin/python3` from the shipping app path.
- [x] Remove any product requirement for a local Python environment, Conda environment, or editable install.
- [x] Confirm all research exports can be generated from the native app alone.
- [x] Review sandbox, entitlements, and file access with the Python runtime removed from the critical path.
  App Store blocker cleanup is now in place across the product path: the Swift app surfaces native reproduction/export instructions instead of Python CLI commands, research bundles and saved workspace/session entries preserve security-scoped bookmark metadata for sandbox-safe reopen, the Xcode target now enables App Sandbox with user-selected read/write access, the README/product guidance makes the native macOS build the supported app path while clearly downgrading Conda/PyInstaller tooling to legacy compatibility work, and regression coverage now includes bookmark-metadata + native reproduction workflow checks in `tests/TrackerAIMacTests/MigrationBacklog21Tests.swift`. Verification passed through the full `swift test` suite and a successful `bash scripts/build_native_macos_app.sh` release build.

### 22. Harden packaging, signing, and distribution around the native-only app

- [x] Make `scripts/build_native_macos_app.sh` the primary supported build path.
- [x] Add release checks for app bundle completeness, assets, plist values, and entitlements.
- [x] Prepare for notarization, update delivery, crash reporting, and licensing once the native engine is self-contained.
- [x] Document the final supported architecture for App Store and direct distribution builds.
  Native release hardening now centers on `scripts/build_native_macos_app.sh`, which supports validated build and archive modes, optional pre-build `swift test`, and source-only validation for fast release-audit checks. `scripts/validate_native_macos_release.sh` enforces the native bundle contract by checking plist metadata, sandbox entitlements, app-icon completeness, and the finished `.app` bundle, while the regenerated AppIcon asset set gives the validator a real completeness gate instead of an empty placeholder catalog. The Xcode target's Release configuration is now correctly wired to `Release.xcconfig` instead of the debug settings, so release builds emit `TrackerAI.app`, produce dSYMs, sign to run locally, and validate cleanly. Distribution guidance for App Store versus direct distribution, including archive handoff, notarization, updater/crash-reporting/licensing planning, and channel-specific responsibilities, now lives in `docs/native_distribution.md`, with the README and in-app help center updated to point at the native-only release path. Verification passed through `swift test`, `bash scripts/build_native_macos_app.sh`, and `bash scripts/build_native_macos_app.sh --archive`.

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
- [x] The shipping app no longer depends on a local Python runtime.
- [ ] A Swift regression suite exists for the core scientific pipeline.
