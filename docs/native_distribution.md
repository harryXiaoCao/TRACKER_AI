# Native Distribution Architecture

Tracker AI now treats the native macOS app as the only supported product packaging path. The historical PyInstaller build remains in the repository only for compatibility work on legacy Python tooling and should not be used for product release candidates.

## Supported Build Paths

- `bash scripts/build_native_macos_app.sh`
  Builds the native app bundle through Xcode and validates source metadata, app-icon completeness, plist values, entitlements, and the finished `.app` bundle.
- `bash scripts/build_native_macos_app.sh --run-tests`
  Runs the Swift test suite before building the native release candidate.
- `bash scripts/build_native_macos_app.sh --archive`
  Produces `TrackerAI.xcarchive` for signing, notarization, and export handoff.
- `bash scripts/validate_native_macos_release.sh --source-only`
  Runs the native release configuration checks without building.

## App Store Build

Use the App Store path when the product is distributed through Apple-managed signing, receipt handling, and update delivery.

- Build surface: `TrackerAI.xcodeproj` archive from the shared `TrackerAI` scheme
- Runtime assumptions: native Swift engine only, App Sandbox enabled, user-selected file access
- Signing model: Xcode/App Store Connect managed signing with a real team and distribution certificate
- Update model: App Store updates only; no third-party updater framework
- Licensing model: App Store receipt and Apple commerce flow
- Crash reporting: App Store-safe crash collection provider or Apple crash reports

## Direct Distribution Build

Use the direct distribution path when the product is shipped outside the App Store.

- Build surface: `bash scripts/build_native_macos_app.sh --archive`
- Signing model: Developer ID Application signing
- Notarization: submit the archived app or exported zip/dmg to Apple notarization, then staple the ticket to the shipped artifact
- Update delivery: attach a signed updater framework and appcast/feed only to direct-distribution builds
- Licensing model: direct-license or account-based entitlements only in this channel
- Crash reporting: connect the chosen crash backend and upload dSYMs from the archive build

## Release Checklist

1. Run `bash scripts/build_native_macos_app.sh --run-tests`.
2. Confirm the release validator passes for source config and the built bundle.
3. Archive with `bash scripts/build_native_macos_app.sh --archive`.
4. Sign with the intended App Store or Developer ID identity.
5. Notarize and staple direct-distribution artifacts when shipping outside the App Store.
6. Upload dSYMs to the selected crash-reporting backend.
7. Keep updater and licensing integrations channel-specific:
   App Store builds rely on Apple-managed updates and receipts.
   Direct builds own updater feeds and license enforcement.

## Repository Contracts

- `macos/TrackerAI/Config/Base.xcconfig` defines bundle identifier, versioning, plist path, entitlements, and asset catalog names.
- `macos/TrackerAI/Config/Release.xcconfig` keeps release validation enabled and produces dSYMs.
- `macos/TrackerAI/Resources/TrackerAI.entitlements` preserves the sandbox contract for user-selected lab data.
- `macos/TrackerAI/Resources/Assets.xcassets/AppIcon.appiconset` now contains the required macOS icon sizes used to generate `AppIcon.icns`.
- `scripts/validate_native_macos_release.sh` is the release gate that should stay green before any distribution handoff.
