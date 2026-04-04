# Tracker AI

Tracker AI is a native macOS application for 2D planar motion analysis from video.
It combines native video tracking, calibration, review tooling, and research-ready
exports for classroom and lab workflows, while still preserving compatibility with
legacy session and bundle formats from the earlier Python tooling.

## Current Release-Candidate Track

- Load a video and map frame indices to timestamps
- Draw a physical calibration line directly on the frame
- Pick a start frame and draw the initial target box directly on the frame
- Track the object through the clip using a hybrid template + motion model pipeline
- Step frame-by-frame and apply correction boxes when tracking drifts
- Compute displacement, velocity, acceleration, speed, and acceleration magnitude
- Export CSV, plots, overlay video, report stub, and reusable session files
- Launch a Qt desktop shell when `PySide6` and `pyqtgraph` are installed

## Native macOS App

Primary local build path:

```bash
bash scripts/build_native_macos_app.sh
```

Release-candidate build with tests:

```bash
bash scripts/build_native_macos_app.sh --run-tests
```

Archive build for signing/notarization handoff:

```bash
bash scripts/build_native_macos_app.sh --archive
```

Primary product-work path in Xcode:

```bash
open macos/TrackerAI/TrackerAI.xcodeproj
```

Suggested in-app workflow:

1. Open a video.
2. Step to the best setup frame and click `Use This Frame`.
3. Click `Draw Scale` and drag the calibration line.
4. Click `Draw Target` and drag the object box.
5. Click `Run Analysis`.
6. If tracking drifts, step to the failure frame, click `Draw Correction`, redraw the box, then click `Apply Correction`.
7. Click `Export Bundle`.

The native app no longer requires a local Python environment, Conda environment, or editable install to run analysis or generate research exports. The native build script now validates release metadata, entitlements, and app-icon completeness before it treats a build as distribution-ready.

## Legacy Python Tooling

The repository still contains the legacy Python CLI and regression harness for compatibility checks and historical workflows.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## Run the CLI

```bash
tracker-ai analyze \
  --video /path/to/video.mp4 \
  --bbox 120 90 55 55 \
  --scale-points 20 430 200 430 \
  --reference-length 0.5 \
  --unit m \
  --output-dir outputs/run1
```

This exports:

- `analysis.csv`
- `summary.json`
- `session.json`
- `overlay.mp4`
- `plots/position.png`
- `plots/velocity.png`
- `plots/acceleration.png`

## Conda Setup

```bash
conda env create -f environment.yml
conda activate tracker-ai
```

## Generate a Sample Video

```bash
python scripts/create_sample_video.py
```

Then analyze it with:

```bash
tracker-ai analyze \
  --video sample_data/projectile_sample.mp4 \
  --bbox 100 350 45 45 \
  --scale-points 120 500 320 500 \
  --reference-length 0.5 \
  --unit m \
  --output-dir outputs/sample_run
```

## Legacy macOS Packaging

The historical PyInstaller path is still available for compatibility work only:

```bash
bash scripts/build_macos_app.sh
```

## Native macOS Commercialization Track

The repository now also includes a native macOS application shell built with
SwiftUI/AppKit under `Sources/TrackerAIMac`, plus an Xcode app project under
`macos/TrackerAI/TrackerAI.xcodeproj`.

This native app follows the redesigned "Research Mission Control" information
architecture:

- Overview dashboard for trial readiness and experiment presets
- Setup workspace for metadata, direct-on-video calibration/target drawing, and execution
- Review journal for manual event marking, imported quality spans, and correction anchors
- Results lab for insights, graphs, events, quality, and reproducibility
- Native research exports and workspace batch orchestration layered on top of the macOS shell

Current native architecture:

- SwiftUI/AppKit handles the product shell and desktop workflow
- Native tracking, scientific processing, export generation, and batch coordination now run inside the Swift app
- Session JSON, workspace JSON, and export bundles can be loaded directly into
  the native app model for compatibility
- Native exports now preserve richer session state, manual events, correction anchors,
  and summary/quality/report artifacts inside standard bundle filenames
- Security-scoped bookmarks keep user-selected files and export directories compatible with App Sandbox

If `xcodebuild` reports that the active developer directory points at Command
Line Tools, install full Xcode and switch with `xcode-select` before using the
native project.

The Xcode project is organized for the commercialization transition:

- `macos/TrackerAI/TrackerAI.xcodeproj` for native app target wiring
- `macos/TrackerAI/Config` for build configuration and release settings
- `macos/TrackerAI/Resources` for plist, entitlements, and asset catalogs
- `Sources/TrackerAIMac` for shared SwiftUI/AppKit source code

Recommended commercialization roadmap:

1. Keep refining native setup/review/document workflows around the now-native engine.
2. Use `scripts/build_native_macos_app.sh` plus `scripts/validate_native_macos_release.sh` as the supported release gate for local builds and archive handoff.
3. Wire the final external services for signing/notarization credentials, update delivery, crash reporting, and licensing as the launch plan solidifies.
4. Preserve compatibility import coverage for legacy JSON/session artifacts while retiring unsupported Python-era packaging assumptions.

The supported App Store and direct-distribution architecture is documented in [docs/native_distribution.md](/Users/Harry-Cao/Desktop/TRACKER_AI/docs/native_distribution.md).

## Notes

- The native macOS app is now the primary product surface and can generate research exports without a Python runtime.
- v1 assumes planar motion and a manually defined scale.
- The current release candidate prioritizes guided interaction and manual correction over full automation.
- The tracking core is designed to stay modular so detector-assisted recovery can be added later
  without replacing the rest of the pipeline.
