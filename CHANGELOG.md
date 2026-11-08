# Changelog

All notable changes to Kecilin are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] — 2026-11-08

### Added

- First-launch welcome modal: short intro, core features, and the 100 % on-device
  privacy statement. Shown once, dismiss-guarded.
- "What's new" modal after a manual update, listing the user-facing changes for
  the new version. Update detection is entirely local (stored seen-version
  compared against the build version) — no network access, no new dependencies.

### Changed

- Refreshed visual design built on a glass design system: shared theme tokens
  for derived text colours, soft containers, glass surfaces, radius, and motion
  across every screen.
- Restructured home screen: storage stats card with a savings chip and ratio
  bar, always-visible quick-start pickers for images and PDFs, functional
  history filter pills, per-row relative timestamps, and a privacy trust footer.
- Compression results now record their finish time (backward-compatible JSON),
  shown as relative timestamps in history rows.
- Setup screen cross-fades its option blocks when the compression mode changes,
  and its footer shows the total selected size.
- Settings screen uses danger-styled destructive buttons and a shared confirm
  dialog for file and history cleanup.
- Gallery and file action sheets get a frosted glass backdrop, drag handle,
  file header with a kind glyph, and haptic feedback.

## [1.0.0] — 2026-11-08

First public release. Android only.

### Added

- Local image compression: JPG, JPEG, PNG, WebP, HEIC/HEIF, BMP → JPG or WebP,
  with byte-size targets (100 KB / 200 KB / 500 KB / 1 MB / 2 MB), fixed-quality
  presets, near-lossless mode, and resolution caps.
- Local PDF compression: Light mode (text layer preserved, embedded images
  re-encoded) and Aggressive mode (per-page rasterisation into a new PDF).
- Batches of up to 30 files with per-page progress and mid-run cancellation.
- Optional in-app gallery using partial media access on Android 14+.
- Local history with total savings, share, open-with, light/dark theme.
- Output saved to `Download/Kecilin` through MediaStore, no storage permission.
- Architecture, development, privacy, and performance documentation under
  `docs/`.
- CI (format, analyze, tests, release build check) and a tag-triggered release
  workflow that verifies the signing certificate and the absence of the
  `INTERNET` permission before creating a draft release.

### Security

- The release build declares no `INTERNET` permission: there is no network path
  for a document to leave the device.
- EXIF metadata (including GPS) is stripped whenever an image is re-encoded.
- Cloud backup and device transfer are disabled at the manifest level.
- Original files are never modified or deleted; every output is a new file
  suffixed `-kecil`.
- Release APKs are named `kecilin-<version>-<abi>.apk` and published with a
  `SHA256SUMS.txt` so downloads can be verified.
