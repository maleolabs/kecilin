# Changelog

All notable changes to Kecilin are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
