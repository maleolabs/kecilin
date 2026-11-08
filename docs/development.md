# Kecilin — Development Guide

Everything a developer needs to run, test, and build Kecilin from a clean clone.

---

## 1. Prerequisites

| Tool | Version used by this project | Notes |
| --- | --- | --- |
| Flutter | 3.38.5 (stable) | `flutter --version` must report this or a compatible 3.38.x |
| Dart | 3.10.4 | Bundled with Flutter |
| JDK | **21** | Required for Gradle. JDK 25 breaks the Kotlin compiler — see §8 |
| Android SDK | Platform 36, build-tools 36 | `flutter doctor` must be green for Android |
| Android NDK | version pinned by `flutter.ndkVersion` | Installed automatically by Gradle if missing |
| Gradle | 8.14 (wrapper) | Never install manually; use `./gradlew` |

Optional, only for specific tasks:

| Tool | Needed for |
| --- | --- |
| ImageMagick + Ghostscript | Regenerating on-device test fixtures |
| A physical Android device or emulator | `integration_test/` |
| macOS + Xcode | iOS (not implemented yet) |

Verify:

```bash
flutter doctor -v
```

---

## 2. First run

```bash
git clone <repo-url> kecilin
cd kecilin
flutter pub get
flutter run
```

That is genuinely all that is needed for a debug build. There is no code
generation step, no `.env` to create, and no local configuration file.

### 2.1 Release builds need signing material

`android/app/build.gradle.kts` **fails hard** when `android/key.properties` is
missing. This is intentional: a release APK signed with the debug key can never
update an installed build, and that failure is easy to ship without noticing.

For local release builds:

```bash
cp android/key.properties.example android/key.properties
# fill in storeFile / storePassword / keyAlias / keyPassword
chmod 600 android/key.properties
```

Neither `key.properties` nor `android/keystore/` is ever committed. Signing is
covered in §6.

---

## 3. Everyday commands

```bash
flutter pub get              # resolve dependencies
dart format .                # format (CI checks this, do not skip)
flutter analyze              # static analysis — must report 0 issues
flutter test                 # 22 unit + widget tests
flutter run                  # debug build on the attached device
```

Run the JVM tests for the hand-written PDF writer:

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

The JVM test writes a two-page PDF through `RasterPdfWriter` and verifies the
header, object count, and that **every xref offset points at the right `N 0 obj`**.
A malformed xref is the classic way a hand-written PDF writer produces a file
that opens in one viewer and not another, so this test is not decorative.

> If `./gradlew` fails on a machine where `flutter build` works, you are almost
> certainly on JDK 25. See §8.

---

## 4. Testing

Three tiers, each catching different failures.

### 4.1 Unit tests — `test/`

Pure logic: byte formatting, size parsing, filename sanitisation, the controller
run loop with fake engines and a fake `OutputTarget`.

```bash
flutter test
```

Fast (~10 s). No device, no filesystem surprises.

### 4.2 Widget tests — `test/widgets_test.dart`

Renders shared widgets and asserts layout proportions and tap behaviour.

### 4.3 On-device integration tests — `integration_test/`

The only tests that exercise the **real** Kotlin engines: the Android decoder,
PDFBox, `PdfRenderer`, and MediaStore. If the app "works" but these fail, the app
does not work.

They need fixtures, which are synthesised, gitignored, and not part of any build:

```bash
./tool/test_fixtures.sh          # writes integration_test/assets/ (~5 MB)
```

Then temporarily add the fixture folder to the **existing** `assets:` list in
`pubspec.yaml` (do not add a second `assets:` key — duplicate keys break the
build; there must be exactly one list):

```yaml
  assets:
    - assets/logo/
    - integration_test/assets/   # temporary, remove after the run
```

Run on a connected device:

```bash
flutter test integration_test/compression_test.dart -d <device-id>
# or, when a driver harness is needed:
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/compression_test.dart --profile -d <device-id>
```

`flutter drive` refuses `--release`, so on-device suites run in `debug` or
`profile`. Minified-release behaviour is verified separately by installing the
release APK and driving the UI by hand (see `docs/performance/performance-report.md`).

Afterwards, revert both steps:

```bash
# remove the "- integration_test/assets/" line again
rm -rf integration_test/assets
```

**Never commit `integration_test/assets/`.** It is gitignored, and the fixture
generator reads no external input, so a leaked fixture is not a privacy event —
but it is 5 MB of build noise.

What the nine integration tests cover:

| Test | Proves |
| --- | --- |
| 200 KB target on a 6 MP photo | binary search converges, output is a complete JPEG |
| never-bigger guard | an already-small source is returned untouched |
| format preservation | a PNG source is not written into a `.jpg` name |
| light mode shrinks a scan | PDFBox path produces a smaller file |
| light mode does not inflate a text-only PDF | the "already optimal" branch works |
| light mode keeps the text layer | shared images compressed, text still selectable |
| aggressive mode produces a valid document | `RasterPdfWriter` output parses |
| cancel stops a job | no partial file remains |
| MediaStore save | lands in `Download/Kecilin/` |

Three PDFs are exported to `Download/Kecilin/verify-*.pdf` so they can be
validated off-device:

```bash
adb pull /sdcard/Download/Kecilin/verify-light.pdf
pdfinfo verify-light.pdf
gs -q -dNOPAUSE -dBATCH -sDEVICE=nullpage verify-light.pdf
```

The test runner uninstalls the app afterwards, which is why the export exists.

---

## 5. Build

### 5.1 Debug

```bash
flutter run
```

Debug builds carry the `INTERNET` permission because the Flutter tool needs it
for hot reload. **Never distribute a debug APK.**

### 5.2 Release APK (per ABI)

```bash
flutter build apk --release --split-per-abi
```

Output:

```
build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk      ~21 MB
build/app/outputs/apk/release/kecilin-1.0.0-armeabi-v7a.apk    ~19 MB
build/app/outputs/apk/release/kecilin-1.0.0-x86_64.apk         ~23 MB
```

The Flutter tool also copies default-named APKs into
`build/app/outputs/flutter-apk/` (`app-<abi>-release.apk`); those copies are
duplicates, and `release.yml` consumes the Gradle output directory instead.

Install the arm64 build on a modern phone:

```bash
adb install -r build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk
```

A fat APK (all ABIs, ~55 MB) is also possible via `flutter build apk --release`,
but there is no reason to ship one.

### 5.3 App bundle

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab` (~47 MB). This is the
upload artifact; Google Play splits it per device, so users never download the
full size.

### 5.4 Size analysis

```bash
flutter build apk --release --analyze-size --target-platform android-arm64
```

Writes a size report to `<project>/.dart_tool/flutter_build/…/app-arm64-v8a.json`.
Feed it to DevTools:

```bash
flutter pub global activate devtools
flutter pub global run devtools --appSizeBase=<path-to-json>
```

### 5.5 Release shrinking

R8 and resource shrinking are **on**. Rules live in
`android/app/proguard-rules.pro`. If a release build fails with "Missing class",
the message names the exact class — add a `-dontwarn` only for classes that are
genuinely optional, never a blanket `-dontwarn **`.

---

## 6. Signing

Two files, both gitignored:

```
android/keystore/kecilin-release.jks
android/key.properties
```

| Concern | Answer |
| --- | --- |
| Where are the credentials? | In `key.properties` on the developer machine, mode `0600` |
| Are they in git? | No, and CI fails if they ever are |
| What if the keystore is lost? | You cannot update an existing install. Users must uninstall first. **Back it up offline.** |
| Can CI sign releases? | Only `release.yml`, on a `v*` tag, with the release key held in the `release` environment behind an approval gate. `ci.yml` never does |
| Should the password be rotated? | Recommended before any public distribution. Rotating after release means a new signing identity |

The release keystore is held in the `release` environment's secrets, so it is
only available to a job that a required reviewer has approved, and only on a
`v*` tag. A signing key that is lost cannot be recovered, and an install cannot
be updated without the original key, so back it up offline regardless.

---

## 7. Project layout

```
lib/                  Dart application (see architecture.md)
android/              Android host, Kotlin engines, resources
assets/               fonts (with OFL license) and logo
test/                 unit and widget tests
integration_test/     on-device tests (fixtures generated, not committed)
tool/                 fixture generator, branding regeneration
docs/                 architecture, development, releasing, security, performance
.github/              CI, PR and issue templates
```

---

## 8. Troubleshooting

### `./gradlew` fails with `java.lang.IllegalArgumentException: 25.0.4.1`

Kotlin 2.2.20 ships an IntelliJ `JavaVersion` parser that cannot read the
four-part JDK version string. `flutter build` works because the Flutter tool uses
the JDK configured for Android Studio (21).

Fix:

```bash
export JAVA_HOME=/opt/android-studio/jbr        # or any JDK 21
# or pin it for the project:
# echo "org.gradle.java.home=/path/to/jdk-21" >> android/gradle.properties
```

`android/gradle.properties` is committed, so prefer `JAVA_HOME` or a local
`~/.gradle/gradle.properties` unless the team agrees on one path.

**Do not "fix" this by upgrading Kotlin without running the full build.**

### `flutter build apk --release` fails: `android/key.properties is missing`

Expected. A release build refuses to fall back to the debug key. Copy
`android/key.properties.example`, fill it in (§2.1), and build again.

### `flutter test` is slow on first run

Widget tests load the bundled fonts. ~40 s cold, ~10 s warm.

### Integration test: `missing test asset …`

You forgot `./tool/test_fixtures.sh`, or you did not add
`- integration_test/assets/` to the `assets:` list in `pubspec.yaml`.

### Emulator cannot compress a large PDF

Emulators have limited heap. `OutOfMemoryError` on a 50-page scan is an emulator
limitation, not a product regression. Verify large-document behaviour on a
physical device.

### `flutter analyze` reports an issue in `integration_test/`

The integration test imports `package:kecilin/...`, so it is analysed with the
app. Keep it clean; CI runs the same command.

---

## 9. Change checklist

Before opening a pull request:

```bash
dart format .
flutter analyze
flutter test
flutter build apk --release --split-per-abi   # if native or build config changed
```

Then confirm:

- [ ] no new permission in `AndroidManifest.xml`
- [ ] no new dependency that performs network I/O
- [ ] no file contents, names, or paths written to logs
- [ ] originals are still never modified or overwritten
- [ ] `docs/` updated if a contract, permission, or dependency changed

The pull request template asks for exactly these.
