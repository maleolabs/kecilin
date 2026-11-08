# Changelog

All notable changes to Kecilin are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Architecture, development, security, and performance documentation under `docs/`.
- GitHub Actions workflow: formatting, static analysis, tests, and a release build check.
- Pull request and issue templates.
- `LICENSE` (MIT), `.gitattributes`, `.editorconfig`, `android/key.properties.example`.
- `.github/workflows/release.yml`: tag-triggered release that verifies the signing
  certificate and the absence of the `INTERNET` permission, then creates a draft
  GitHub release with the APKs and `SHA256SUMS.txt`.

### Changed

- Release APKs are now named `kecilin-<version>-<abi>.apk` (for example
  `kecilin-1.0.0-arm64-v8a.apk`) by the Gradle build; `release.yml` attaches
  those files from `build/app/outputs/apk/release/`.
- `tool/test_fixtures.sh` now generates its fixtures; it no longer reads any file
  from outside the repository.
- `docs/releasing.md`: the automated release path is now the default and the manual
  checklist is documented as the fallback.
- Test fixtures were renamed (`sample-photo.jpg`) so nothing in the suite
  suggests a real document.
- Lint baseline tightened: `unused_import`, `dead_code` and related rules are now
  errors instead of warnings.
- Code formatted with `dart format` (10 files reformatted).

### Fixed

- `run_screen.dart` no longer ignores the `Future` returned by `pushReplacement`.

### Security

- `.gitignore` extended to cover all signing material (`*.jks`, `*.keystore`,
  `*.p12`, `*.pem`, `*.key`) and environment files.
- Release builds now use R8 and resource shrinking (arm64 APK: 25.4 MiB → 20.3 MiB).

### Removed

- Dependencies that were never imported: `cupertino_icons`, `intl`, `path`.

## [1.0.0] — 2026-11-07

First internal release. Android only.

- Local image compression: byte-size targets, quality presets, resolution caps,
  JPEG/WebP output.
- Local PDF compression: Light mode (text layer preserved) and Aggressive mode
  (rasterisation).
- Batches of up to 30 files, per-page progress, mid-run cancellation.
- Optional in-app gallery using partial media access on Android 14+.
- Local history and savings statistics, light/dark theme.
- Output saved to `Download/Kecilin` through MediaStore, no storage permission.
