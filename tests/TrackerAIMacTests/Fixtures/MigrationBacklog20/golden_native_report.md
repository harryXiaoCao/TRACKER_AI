# Tracker AI Experiment Report

- Experiment label: `Golden Fixture Experiment`
- Trial ID: `trial-golden-01`
- Operator: `Codex`
- Video: `/tmp/golden-video.mp4`
- Active track: `Primary Marker` [primary]
- Frame range: `3` to `18`
- Reference length: `2.0000 m`
- Reference marker enabled: `true`
- Smoothing window: `5` polyorder `2`
- Tracking profile: `marker`
- Robust recovery: `false`
- Bidirectional refinement: `false`
- Tags: `golden, native, migration`
- Notes: `Fixture-backed migration regression`
- Frames analyzed: `4`
- Average confidence: `0.9125`
- Low-confidence frames: `0`
- Suspect spans: `1`
- Lost frames: `1`
- Corrected frames: `1`
- Reacquisitions: `1`
- Total path length: `0.4000 m`
- Net displacement: `0.3953 m`
- Peak speed: `3.9051 m/s`
- Mean speed: `2.3425 m/s`
- Peak acceleration: `1.1402 m/s^2`
- Mean acceleration: `0.4647 m/s^2`
- Review recommended: `true`
- Scientific confidence mean: `0.8475`
- QC badge: `too_much_interpolation`
- Quality index: `0.4960`
- Classification: `Incline Motion` (`0.8475`)
- Peak position uncertainty: `0.0600 m`
- Peak velocity uncertainty: `0.2200 m/s`
- Events detected: `5`
## Reproduce This Run

```bash
tracker-ai \
  analyze \
  --video "/tmp/golden-video.mp4" \
  --bbox 12 24 28 22 \
  --scale-points 10 20 90 20 \
  --reference-length 2 \
  --unit m \
  --start-frame 3 \
  --window 5 \
  --polyorder 2 \
  --tracking-profile marker \
  --report-template research \
  --end-frame 18 \
  --reference-bbox 100 32 18 18 \
  --skip-overlay \
  --skip-plots \
  --debug-tracking \
  --experiment-label "Golden Fixture Experiment" \
  --trial-id "trial-golden-01" \
  --operator "Codex" \
  --notes "Fixture-backed migration regression" \
  --tags "golden" "native" "migration" \
  --extra-object secondary_1 "Secondary Marker" 42 40 14 14 \
  --output-dir <output-dir>
```
## Experiment Classification

- Classification: `Incline Motion`
- Confidence: `0.8475`
- Summary: Estimated from a line fit through the smoothed path.
- Supporting analyzers: `circular, incline`
## Quality Notes

- Quality index: `0.4960`
- Calibration confidence: `0.8200`
- Drift sensitivity: `0.0300`
- Interpolated burden ratio: `0.5000`

- Lost frames detected; review reacquisition spans before publication use.
- Manual corrections were applied; keep the session file with the exported run.
- 1 event markers are attached to this session and should travel with exports.
- Native QC flagged 3 elevated anomaly clusters; inspect the anomaly register before publication use.
- The highest-severity review span is suspect_tracking across frames 7-8.
## Pairwise Metrics

- `primary` vs `secondary_1`: min separation `0.2600 m`, mean separation `0.3400 m`, peak relative speed `1.4000 m/s`, collision frame `none`
## Native QC Anomaly Register

- [HIGH] `Suspect Tracking Span` at frame(s) `7-8` score `1.0000`: Reason: tracking_recovery. Tracker confidence 0.0000; scientific confidence 0.0000. Action: Review this segment frame-by-frame and confirm the target box before exporting.
- [HIGH] `Lost Tracking Span` at frame(s) `9-10` score `1.0000`: Reason: lost_tracking. Tracker confidence 0.0000; scientific confidence 0.0000. Action: Inspect reacquisition behavior and verify interpolation before publication reporting.
- [HIGH] `Manual Correction Span` at frame(s) `11-14` score `0.8800`: Reason: manual_correction. Tracker confidence 0.0000; scientific confidence 0.0000. Action: Keep the native session file with the export so manual interventions remain reproducible.
## Native Span Severity Ledger

- `suspect_tracking` frames `7-8` score `1.0000` tracker `0.0000` scientific `0.0000`: tracking_recovery. Action: Review this segment frame-by-frame and confirm the target box before exporting.
- `lost_tracking` frames `9-10` score `1.0000` tracker `0.0000` scientific `0.0000`: lost_tracking. Action: Inspect reacquisition behavior and verify interpolation before publication reporting.
- `manual_correction` frames `11-14` score `0.8800` tracker `0.0000` scientific `0.0000`: manual_correction. Action: Keep the native session file with the export so manual interventions remain reproducible.
## Experiment Modules

- `Circular Motion` (0.5648): mean_radius=0.1380 m, angular_velocity=4.0705 rad/s, circularity=0.5648
- `Incline Motion` (0.8475): track_angle_deg=-17.6592 deg, along_track_acceleration=0.0436 m/s^2, line_residual_std=0.0121 m
## Event Journal

- `apex` [derived] at frame `3` (`0.1500` s): `0.2250 m` - Maximum vertical position
- `manual_release` [manual] at frame `4` (`0.2000` s): `0.0000 s` - operator-marked release
- `peak_speed` [derived] at frame `5` (`0.2500` s): `3.9051 m/s` - Maximum speed
- `furthest_x` [derived] at frame `6` (`0.3000` s): `0.4250 m` - Maximum horizontal position
- `peak_acceleration` [derived] at frame `6` (`0.3000` s): `1.1402 m/s^2` - Maximum acceleration