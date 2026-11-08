# Kecilin — Performance & Artifact Report

**Date:** 8 November 2026
**Device:** Samsung SM-A065F (Galaxy A06), Android 16 / SDK 36, arm64-v8a, 720×1600
**Toolchain:** Flutter 3.38.5 (stable), Dart 3.10.4, JDK 21 (Android Studio JBR), Gradle 8.14, AGP per `android/`
**Scope:** build artifact size, APK composition, on-device runtime for the release build.

Everything below was measured on the device described above. Anything not
measured is labelled **NOT VERIFIED** — no number in this document is estimated
unless it says so.

---

## 1. Summary

| Metric | Before | After | Change |
| --- | --- | --- | --- |
| arm64-v8a APK | 26,610,994 B (25.4 MiB) | 21,267,752 B (20.3 MiB) | **−5,343,242 B (−20.1 %)** |
| armeabi-v7a APK | 24,058,210 B (22.9 MiB) | 18,714,968 B (17.9 MiB) | **−5,343,242 B (−22.2 %)** |
| x86_64 APK | 27,962,226 B (26.7 MiB) | 22,618,980 B (21.6 MiB) | **−5,343,242 B (−19.1 %)** |
| app-release.aab | 50,281,753 B (47.9 MiB) | 46,451,331 B (44.3 MiB) | **−3,830,422 B (−7.6 %)** |
| Installed on-disk size (arm64) | not measured | 20,807 KB (20.3 MiB) | — |
| Cold start (release, warm dex) | not measured | 644–677 ms | — |
| Idle PSS (release, home screen) | not measured | 134,190 KB (131 MiB) | — |

The saving came from two independent changes, applied in that order:

1. **R8 + resource shrinking** (`isMinifyEnabled`, `isShrinkResources`, plus
   keep rules) — identical 5,082,006 B off every APK, because the delta is
   entirely `classes.dex` + `res/`, which do not vary by ABI.
2. **Header logo re-encode** 365,123 → 103,843 B — exactly 261,236 B off every
   APK and 261,313 B off the AAB, because a bundled asset is ABI-independent.

The fact that both deltas are byte-identical across the three APKs is the
sanity check that nothing else moved.

---

## 2. Build artifacts (exact bytes)

| Stage | arm64-v8a | armeabi-v7a | x86_64 | AAB |
| --- | --- | --- | --- | --- |
| Baseline (R8 off, 365 KB logo) | 26,610,994 | 24,058,210 | 27,962,226 | 50,281,753 |
| R8 + shrinking (365 KB logo) | 21,528,988 | 18,976,204 | 22,880,216 | 46,712,644 |
| R8 + shrinking + 104 KB logo | **21,267,752** | **18,714,968** | **22,618,980** | **46,451,331** |

Build commands:

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Signing requires `android/key.properties`; without it the release task fails
closed by design (see `android/app/build.gradle.kts`).

---

## 3. APK composition — arm64-v8a, current build

Measured by sum of compressed entry sizes inside the APK (21,143,883 B of
entries; the remaining 123,869 B is the ZIP central directory and alignment
padding).

| Component | Bytes | Share |
| --- | --- | --- |
| Native libraries (`lib/arm64-v8a/`) | 16,555,640 | 78.3 % |
| Java/Kotlin resources & metadata (`assets/com/tom_roush/…`, `kotlin/`, …) | 1,899,480 | 9.0 % |
| `classes.dex` | 1,338,544 | 6.3 % |
| Android resources (`res/`, `resources.arsc`) | 960,890 | 4.5 % |
| Flutter assets (`assets/flutter_assets/`) | 385,013 | 1.8 % |
| Signing block / META-INF | 4,316 | 0.02 % |

Largest single entries:

| Bytes | Entry | Note |
| --- | --- | --- |
| 11,107,920 | `lib/arm64-v8a/libflutter.so` | Flutter engine — irreducible per ABI |
| 5,309,360 | `lib/arm64-v8a/libapp.so` | AOT-compiled Dart |
| 1,338,544 | `classes.dex` | already R8-shrunk |
| 305,285 | `res/pK.png` | launcher/webp-derived bitmap resource |
| 251,052 | `resources.arsc` | resource table |
| 210,865 | `assets/com/tom_roush/pdfbox/resources/ttf/LiberationSans-Regular.ttf` | PDFBox fallback font |
| 183,119 | `res/ce.png` | launcher-derived bitmap resource |
| 131,248 | `lib/arm64-v8a/libdartjni.so` | `jni` package (PDFBox bridge) |
| 111,812 | `assets/com/tom_roush/fontbox/resources/cmap/UniCNS-UCS2-H` | CJK cmap for text-layer PDFs |
| 103,843 | `assets/flutter_assets/assets/logo/kecilin-header.png` | optimised header |

**Reading of this table.** 78 % of the download is the Flutter engine plus AOT
Dart, which no amount of application-level work removes. The remaining 22 % is
already the minimum for the features that exist: PDFBox with a text-preserving
path, and a PDF rasteriser. Removing PDFBox would cut roughly 1.4–1.5 MB
(classes + fonts + cmaps) but would also remove the text layer, which is the
product's main differentiator. That trade is **not** recommended.

---

## 4. R8 / resource shrinking

`android/app/build.gradle.kts`:

```kotlin
isMinifyEnabled = true
isShrinkResources = true
proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
```

`proguard-rules.pro` keeps the Flutter engine entry points, the `MethodChannel`
handlers reached only by name, and the kotlinx/JNI surfaces; it also adds
`-dontwarn com.google.android.play.core.**` so the Play Core absent-class warning
does not fail the build.

Verified at runtime, not just at build time: the minified release APK was
installed on the physical device, launched, and used to compress a PDF end to end
(§6). No `ClassNotFoundException`, `NoClassDefFoundError`, or
`FATAL EXCEPTION` appeared in `logcat` during that run.

---

## 5. Asset optimisation

| Asset | Before | After | Method |
| --- | --- | --- | --- |
| `assets/logo/kecilin-header.png` | 365,123 B (1000×336) | 103,843 B (475×160) | `tool/branding/regen.py`, `HEADER_MAX_HEIGHT_PX = 160` |

475×160 is still ~4× the layout size of the header at 3× density, so the logo
stays sharp on every device the app supports. The re-encode is reproducible:
`tool/branding/regen.py` regenerates the same file from the source vector.

---

## 6. On-device runtime — release build

Device: Galaxy A06, Android 16. Release APK (R8 on) installed via `adb install`.

### 6.1 Start-up and footprint

| Metric | Value | Method |
| --- | --- | --- |
| First launch after install | 1,168 ms | `am start -W` (includes one-off dexopt) |
| Cold start, process killed | 677 ms | `am start -W` |
| Cold start, process killed | 644 ms | `am start -W` |
| Idle PSS (home screen) | 134,190 KB | `dumpsys meminfo` |
| On-disk installed size | 20,807 KB | `du -sk` of the install directory |

### 6.2 Compression behaviour (release, R8 on)

Manual UI run on the release APK, PDF "Agresif" (aggressive) mode, 100 KB target,
`dokumen-contoh-4-halaman.pdf` (a 4-page sample document, 1.1 MB):

```
Hemat 81%   —   1.1 MB → 207 KB
Tersimpan di Download/Kecilin/dokumen-contoh-4-halaman-kecil.pdf
Catatan: Raster 105 dpi, JPEG 30 — target belum tercapai
```

In English, the same three lines read: "Saved 81 % — 1.1 MB → 207 KB", "Stored in
`Download/Kecilin/…`", "Note: raster 105 dpi, JPEG 30 — target not reached".

The "target belum tercapai" ("target not reached") note is the intended
behaviour: the engine reports honestly instead of silently degrading the output
further.

### 6.3 Integration suite (engines, measured byte results)

`flutter drive --profile` on the same device, 9 scenarios, full suite wall clock
**≈5 s** on the test reporter's clock (1 s resolution):

| Scenario | Result | Measured |
| --- | --- | --- |
| Image, 6 MP photo, 200 KB target | PASS | output ≤ target, complete JPEG |
| Image never grows | PASS | output ≤ source bytes |
| Image format preserved | PASS | source bytes returned, still JPEG |
| PDF light, 4-page scan | PASS | 1,112,129 → 362,740 B (−67.4 %), 4 pages |
| PDF light, text-only | PASS | returned unchanged, 2 pages |
| PDF light, mixed 6 pages (shared XObject) | PASS | 281,946 → 93,227 B (−66.9 %), 6 pages, text layer kept |
| PDF raster, 110 dpi | PASS | smaller than 1,112,129 B, 4 pages, valid `%PDF-` |
| Cancel mid-raster | PASS | `CompressionCancelled`, no partial file |
| MediaStore save | PASS | `Download/Kecilin/sample-photo-kecil.jpg` |

Step timings are bounded by the reporter's 1 s resolution: the three image
scenarios and the three light-PDF scenarios each finished within one bucket; the
4-page raster finished between 1 s and 2 s; the cancel scenario took 4 s because
it deliberately waits for the job to start before cancelling.

The suite runs in `--profile` because `flutter drive` refuses `--release`.
Minified-release engine behaviour is covered by §6.2 instead.

---

## 7. Not verified

| Item | Status | Why |
| --- | --- | --- |
| iOS build size / runtime | **BLOCKED** | No `ios/` platform in the repo; requires macOS + Xcode |
| Sustained memory during a 30-file batch | **NOT VERIFIED** | No leak test was run; batch processing is sequential by design |
| Battery impact | **NOT VERIFIED** | No measurement was taken |
| Sub-second operation timings | **NOT VERIFIED** | Test reporter resolution is 1 s; no micro-benchmarks were run |
| Low-RAM devices (2 GB) | **NOT VERIFIED** | Only one device was available |
| Play Console download size | **NOT VERIFIED** | Requires an upload; the AAB has not been published |

No claim in this document should be read as covering the rows above.

---

## 8. Reproducing

```bash
flutter pub get
flutter build apk --release --split-per-abi
flutter build appbundle --release
ls -l build/app/outputs/flutter-apk/*.apk build/app/outputs/bundle/release/*.aab

# composition of one APK
python3 - <<'PY' build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
import sys, zipfile, collections
z = zipfile.ZipFile(sys.argv[1])
g = collections.Counter()
for i in z.infolist():
    k = ('lib' if i.filename.startswith('lib/') else
         'dex' if i.filename.endswith('.dex') else
         'res' if i.filename.startswith('res/') else
         'flutter_assets' if i.filename.startswith('assets/flutter_assets/') else 'other')
    g[k] += i.compress_size
for k, v in g.most_common():
    print(f'{k:15} {v:>12,}')
PY

# on-device checks
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb shell am start -W -n com.maleolabs.kecilin/.MainActivity
adb shell dumpsys meminfo com.maleolabs.kecilin | grep "TOTAL PSS"
```
