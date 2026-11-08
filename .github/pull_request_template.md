## Summary

<!-- What changed and why. One paragraph is enough. -->

-

## Scope

- [ ] Changes stay inside the stated scope (no drive-by refactors or cleanups)
- [ ] Existing behaviour is unchanged — or the change is explained below
- [ ] No signing material (`android/key.properties`, `*.jks`) touched and no secrets added

## Compression verification

- [ ] Images: output checked by hand — smaller size, sane resolution/EXIF, no visible artefacts
- [ ] PDF: both modes checked (**Light** = text still selectable, **Aggressive** = per-page raster)
- [ ] Originals untouched; output suffixed `-kecil` and written to `Download/Kecilin/`

## Security and privacy

- [ ] No new Android permission in `AndroidManifest.xml`
- [ ] No new network call, socket, or telemetry (this app must stay 100% offline)
- [ ] No user data, local paths, or document contents written to logs

## Quality

- [ ] `flutter analyze` clean (0 issues)
- [ ] `dart format --output=none --set-exit-if-changed .` clean
- [ ] `flutter test` green; new logic has new tests
- [ ] Changes touching the Kotlin engines were tested on a device (`integration_test/`, synthetic fixtures)

## Documentation

- [ ] README / `docs/` updated for any behaviour, format, or build change
- [ ] Migration notes written if the change affects existing installs

## Notes for the reviewer

<!-- Trade-offs, parts not tested, or things deliberately left out. -->
