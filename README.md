# Tracker AI

Tracker AI is a Python desktop application for 2D planar motion analysis from video.
It combines a hybrid single-object tracker with calibration, smoothing, and physics-ready
kinematics export.

## Current Release-Candidate Track

- Load a video and map frame indices to timestamps
- Draw a physical calibration line directly on the frame
- Pick a start frame and draw the initial target box directly on the frame
- Track the object through the clip using a hybrid template + motion model pipeline
- Step frame-by-frame and apply correction boxes when tracking drifts
- Compute displacement, velocity, acceleration, speed, and acceleration magnitude
- Export CSV, plots, overlay video, report stub, and reusable session files
- Launch a Qt desktop shell when `PySide6` and `pyqtgraph` are installed

## Install

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

## Run the Desktop App

```bash
tracker-ai-ui
```

Suggested in-app workflow:

1. Open a video.
2. Step to the best setup frame and click `Use This Frame`.
3. Click `Draw Scale` and drag the calibration line.
4. Click `Draw Target` and drag the object box.
5. Click `Run Analysis`.
6. If tracking drifts, step to the failure frame, click `Draw Correction`, redraw the box, then click `Apply Correction`.
7. Click `Export Bundle`.

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

## macOS Packaging

The project now includes a release-candidate packaging path for macOS:

```bash
bash scripts/build_macos_app.sh
```

Expected artifact:

- `dist/TrackerAI.app`

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
- The existing Python engine remains the transitional analysis backend
- Session JSON, workspace JSON, and export bundles can be loaded directly into
  the native app model
- Native exports now preserve richer session state, manual events, correction anchors,
  and summary/quality/report artifacts inside standard bundle filenames

Intended local run path once a healthy Apple toolchain is available:

```bash
swift run TrackerAIMac
```

Intended Xcode-native path for product work:

```bash
open macos/TrackerAI/TrackerAI.xcodeproj
```

Command-line native build path once full Xcode is installed and selected:

```bash
bash scripts/build_native_macos_app.sh
```

If `xcodebuild` reports that the active developer directory points at Command
Line Tools, install full Xcode and switch with `xcode-select` before using the
native project.

The Xcode project is organized for the commercialization transition:

- `macos/TrackerAI/TrackerAI.xcodeproj` for native app target wiring
- `macos/TrackerAI/Config` for build configuration and release settings
- `macos/TrackerAI/Resources` for plist, entitlements, and asset catalogs
- `Sources/TrackerAIMac` for shared SwiftUI/AppKit source code

Recommended commercialization roadmap:

1. Keep the Python CLI as the scientific engine during product iteration.
2. Replace numeric setup entry with native drawing and annotation tools.
3. Keep porting session parity features from the Python app one workflow at a
   time, including multi-object setup, correction review, and export policy.
4. Move tracking/runtime-critical logic into native modules or a hardened
   embedded service boundary.
5. Add signing, notarization, crash reporting, onboarding, licensing, and
   update delivery for public distribution.

## Notes

- The desktop UI is local-first and uses the same analysis engine as the CLI.
- v1 assumes planar motion and a manually defined scale.
- The current release candidate prioritizes guided interaction and manual correction over full automation.
- The tracking core is designed to stay modular so detector-assisted recovery can be added later
  without replacing the rest of the pipeline.
