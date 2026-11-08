# Kecilin — Architecture

**Scope:** the implementation as it exists today. Nothing here is aspirational; if a layer is thin, it says so.

---

## 1. Shape of the system

Kecilin is a Flutter application with two hand-written Kotlin subsystems reached over platform channels. There is no backend, no database, and no network layer.

```
┌──────────────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                                    │
│                                                                   │
│  feature/      screens: home, setup, run, result, settings        │
│  ui/           design tokens, shared widgets, file-action sheet   │
│  state/        CompressionController (queue, progress, cancel)    │
│  domain/       models + CompressionEngine contract + errors       │
│  data/         engines, channels, stores, pickers                 │
│  core/         byte formatting, size parsing, filename sanitising │
└───────────────────────────────┬──────────────────────────────────┘
                                │ MethodChannel / EventChannel
┌───────────────────────────────▼──────────────────────────────────┐
│ Kotlin (Android)                                                  │
│                                                                   │
│  CompressBridge   channel contract, single-thread serialisation    │
│    ImageCompressor        decode once + binary-search quality      │
│    PdfLightCompressor     PDFBox, in-place JPEG stream rewrite     │
│    PdfRasterCompressor    PdfRenderer → JPEG → RasterPdfWriter     │
│    RasterPdfWriter        hand-written streaming PDF writer        │
│    PdfInfo                page count, encryption probe             │
│    DownloadsSaver         MediaStore publish                      │
│  GalleryBridge    media permissions, thumbnails, materialisation   │
└──────────────────────────────────────────────────────────────────┘
```

### Why two languages

Dart has no first-class access to the platform's hardware-accelerated image codecs, `PdfRenderer`, or `MediaStore`. Compressing a 12 MP image in pure Dart is an order of magnitude slower and consumes more memory than the platform path. The split is not stylistic — it is the only way to hit the performance the product needs.

---

## 2. Dart layers

Dependency direction is strictly downward. `domain/` imports only `core/`; nothing imports `feature/` except `app.dart`.

### `core/` — pure functions

| File | Responsibility |
| --- | --- |
| `format.dart` | byte formatting, size parsing (`"1.5 MB"` → bytes), extension and stem helpers, filename sanitisation |

No Flutter imports, no I/O. Fully unit-tested.

Notable: `sanitizeFileName` strips control characters, path separators, Windows-reserved characters, bidi override characters (used to spoof extensions), trailing dots and spaces, and caps length at 100. Every generated filename passes through it.

### `domain/` — contracts and data

| Type | Purpose |
| --- | --- |
| `MediaKind` | image / pdf |
| `ImageMode` | `target` (byte ceiling), `quality` (fixed preset), `maximum` (near-lossless) |
| `PdfMode` | `light` (keep text layer), `raster` (rasterise pages) |
| `OutputFormat` | jpeg / webp |
| `CompressionOptions` | user choices, JSON-serialisable for persistence |
| `SelectedFile` | a picked file plus cheap metadata |
| `CompressionOutcome` | what an engine produced |
| `JobResult` | a completed job, persisted to history |
| `RunReport` / `RunFailure` / `RunProgress` | batch results and progress |
| `CompressionEngine` | 2-method interface: `kind`, `compress(...)` |
| `CompressionFailure` / `CompressionCancelled` | typed errors |

`CompressionOptions.targetBytes` is nullable and `null` means "no byte target", which is why `copyWith` carries an explicit `clearTarget` flag rather than relying on `??`.

### `data/` — platform edge

| File | Responsibility |
| --- | --- |
| `compress_channel.dart` | the two channels, active-job tracking, fire-and-forget cancel |
| `image_engine.dart` | Dart side of image compression, plus the "never bigger than source" guard |
| `pdf_engine.dart` | Dart side of PDF compression, error-code translation, page-count probe |
| `output_store.dart` | output path allocation, MediaStore publishing, cache cleanup |
| `picker.dart` | `file_selector` wrapper, batch cap (30), metadata enrichment |
| `gallery.dart` | the `…/gallery` channel client, permission states, history fallback |
| `history_store.dart` | last 40 `JobResult`s in `SharedPreferences` |
| `settings_store.dart` | theme, auto-save, last options |

Everything in this layer is failure-tolerant by design: a missing plugin, a platform error, or a `null` reply degrades the feature instead of crashing the app. This is a deliberate asymmetry — the picker must never take the screen down.

`OutputTarget` is an interface with one implementation. It exists so `CompressionController` can be tested without touching the filesystem or MediaStore. That is its only reason.

### `state/` — the run loop

`CompressionController extends ChangeNotifier` owns:

- the current selection (`List<SelectedFile>`)
- `CompressionOptions`
- `_running`, `_cancelRequested`, `_progress`, `_report`

`run()` processes files **sequentially**. For each file:

1. publish progress
2. reserve an output path
3. call the engine
4. optionally publish to `Download/Kecilin`
5. persist a history entry (failure here is swallowed — a cosmetic loss must not delete a successful result)
6. on `CompressionCancelled`, delete the reserved output and stop
7. on any other error, delete the reserved output, record a `RunFailure`, continue with the next file

Sequential processing is deliberate: native work is serialised anyway (one worker thread), and it keeps peak memory independent of batch size.

Cancellation is two-part: a Dart flag stops the next file, and `CompressChannel.cancelActive()` tells the native engine to abort the current one. Without the native call the user would be stuck on the progress screen until the current file finished.

### `ui/` — presentation layer

`app_theme.dart` defines real tokens rather than scattered constants:

- `AppSpace` (4/8/12/16/20/24/28)
- `AppRadius` (8/12/16/24/pill)
- `AppMotion` (160 ms selection, 260 ms progress)
- `AppColors` — a `ThemeExtension` with `light()` and `dark()` instances

`widgets.dart` holds shared primitives (`SizeBar`, `ChoicePill`, `OptionCard`). `file_actions.dart` is the bottom sheet for open/share/save/remove. `gallery_sheet.dart` is the picker grid: pagination (60/page), permission handling, selection ordering, and materialisation.

### `feature/` — screens

| Screen | Responsibility |
| --- | --- |
| `home_screen` | brand header, pick image/PDF, history summary, settings entry |
| `setup_screen` | per-kind compression settings, target input, validation preview |
| `run_screen` | progress, page counter, cancel confirmation |
| `result_screen` | per-file result, savings, share/open/save, failures |
| `settings_screen` | theme, auto-save, storage used, clear history/results |

Navigation is imperative (`Navigator.pushReplacement`) because the flow is linear: home → setup → run → result.

Composition happens once, in `main.dart`. There is no service locator and no global singleton.

---

## 3. Native layer

### 3.1 Channel contract

`com.maleolabs.kecilin/compress`

| Method | Arguments | Result |
| --- | --- | --- |
| `getImageInfo` | `path` | `{width, height}` |
| `getPdfInfo` | `path` | `{pages, bytes, encrypted}` |
| `compressImage` | `jobId, inputPath, outputPath, targetBytes, quality, minQuality, maxQuality, maxEdge, webp, maximumMode` | `{outputPath, beforeBytes, afterBytes, width, height, quality, targetMet}` |
| `compressPdf` | `jobId, inputPath, outputPath, mode, targetBytes, quality, minQuality, maxQuality, maxDpi` | `{outputPath, beforeBytes, afterBytes, pages, note}` |
| `saveToDownloads` | `path, displayName, mime` | `{uri, displayName, displayPath}` |
| `clearCache` | — | `{freedBytes}` |
| `cancel` | `jobId` | `true` |

`com.maleolabs.kecilin/gallery`

| Method | Arguments | Result |
| --- | --- | --- |
| `status` | — | `{access}` |
| `request` | — | `{access}` |
| `page` | `offset, limit` | `{items, hasMore}` |
| `materialize` | `id` | `{path, name, bytes, width, height}` |
| `clearCache` | — | `{freedBytes}` |

`com.maleolabs.kecilin/progress` (event channel) emits `{jobId, page, pages, stage}` for PDF and `{jobId, fraction, stage}` for images.

`access` is one of `granted`, `partial`, `denied`, `unavailable`.

### 3.2 Serialisation

`CompressBridge` runs every heavy call on a single-thread executor. Reasons:

- concurrent encodes on a low-end device cause heap spikes and OOM
- a single in-flight job makes cancellation unambiguous
- results stay ordered

A cancel that arrives before the job is registered is stored in `pendingCancels`, so losing the race between "user tapped cancel" and "job started" cannot strand the UI.

Progress events are posted to the main looper before reaching the event sink.

### 3.3 Image compression

`ImageCompressor`:

1. read bounds with `inJustDecodeBounds` (no pixel allocation)
2. decode **once**, with `inSampleSize` when the source exceeds 12 MP
3. apply EXIF rotation/mirror to pixels, not metadata
4. flatten onto a white canvas (transparent PNG must not become black JPEG)
5. if a byte target exists: estimate scale from `target / (0.16 × pixels)`, encode at `maxQuality`, binary-search quality in 40–93, and if still over, downscale (max 3 rounds), keeping the smallest result and reporting `targetMet = false` when impossible
6. otherwise encode at the fixed quality, with an optional edge cap

One decode and many encodes: no compounding generation loss, and batch throughput is far better than per-file library calls.

Trade-off: an aggressive target forces a resolution drop. That is intentional — a downscaled image reads better than a JPEG destroyed at quality 20.

### 3.4 PDF, light mode

`PdfLightCompressor` (PDFBox-Android) keeps document structure and the text layer. It only touches image XObjects with a `DCTDecode` filter:

- skips images with `SMask`/`Mask` (transparency would break)
- skips 4-component JPEG (CMYK/YCCK — `BitmapFactory` misreads them)
- skips images under 24 KB (not worth it)
- caps the longest edge at 2200 px, quality 45–90
- keeps a replacement only if it is ≥ 8% smaller
- strips document metadata

Critical implementation detail: replacement streams are written **in place** via `createRawOutputStream()` with `/Filter /DCTDecode` set manually. Swapping `PDResources` entries leaves the old stream alive in the document, so PDFBox writes it back and the "compressed" file ends up larger than the source.

`createOutputStream(DCT_DECODE)` cannot be used — `DCTFilter.encode` throws `UnsupportedOperationException` in pdfbox-android.

Measured on a 4-page 2400×3200 scan: **1,112,129 → 362,740 bytes (−67%)**.

Known limitation: images inside Form XObjects are not scanned, only per-page resources. The file stays valid; potential savings are left on the table.

### 3.5 PDF, aggressive mode

`PdfRasterCompressor` + `RasterPdfWriter`:

- each page rendered through `PdfRenderer` to a bitmap
- JPEG-encoded
- written into a new PDF with the original `MediaBox`
- the writer is hand-written (~150 lines) so it can stream: one page in memory at a time, not the whole document
- the first page calibrates the JPEG quality; if the total is still over target, DPI drops in up to 3 steps
- longest edge capped at 2400 px

Trade-off: the text layer is lost. The UI warns before this mode is used.

### 3.6 Gallery bridge

Reads `MediaStore` directly to build a thumbnail grid without loading originals:

- thumbnails at 320 px edge, `RGB_565` (half the memory of `ARGB_8888`)
- page size 60, hard cap 200
- rows are kept even when thumbnail generation fails, so pagination stays stable
- a picked original is copied into `cacheDir/gallery-in` through a `.part` file and an atomic rename, so a crash never leaves a file that looks valid
- reuse is decided by size + `DATE_MODIFIED`, avoiding a re-copy for the same photo

Permissions are requested on demand; `granted` / `partial` / `denied` / `unavailable` are all first-class states.

---

## 4. Data flow: one image, end to end

```
HomeScreen                    user taps "Gambar"
  FilePickerService.pickImages()      → file_selector (SAF, no permission)
  readImageSize(path)                 → native header parse
  controller.addFiles(...)
SetupScreen                   user picks "200 KB"
RunScreen                     controller.run()
  outputs.nextPath(file, options)     → <documents>/Kecilin/photo-kecil.jpg
  ImageCompressionEngine.compress()
    CompressBridge.compressImage()    → worker thread
      decode → rotate → flatten → binary search → write
      emit progress events            → EventChannel → UI
    result: afterBytes, targetMet
  guard: output >= source?            → copy original instead
  settings.autoSaveToDownloads?       → MediaStore → Download/Kecilin
  history.add(JobResult)
ResultScreen                  savings, share/open, failures
```

---

## 5. Persistence

| Store | Key | Contents | Limit |
| --- | --- | --- | --- |
| `SharedPreferences` | `history.v2` | JSON array of `JobResult` | 40 entries |
| `SharedPreferences` | `settings.v2` | theme, autoSave, last options | 1 record |

The `v2` suffix is a manual schema version. Corrupt or unreadable JSON falls back to defaults rather than crashing — a preferences file is not worth an exception on startup.

Backup and device transfer are disabled at the manifest level, so neither store leaves the device.

---

## 6. Error model

Three tiers, chosen per call site:

1. **Typed and surfaced.** Compression failures become `CompressionFailure` with an Indonesian message, collected per file in `RunFailure`. `PlatformException` codes are mapped (`OutOfMemoryError`, `SecurityException`, …).
2. **Degraded silently.** Gallery status, page loads, cache clearing, PDF page counts. The feature loses capability; the app keeps working.
3. **Swallowed with intent.** History persistence failure, stale output deletion. A convenience loss must never destroy a successful result.

Every channel call has an explicit timeout (5 s info, 30 s materialise, 10 min image, PDF bounded separately) because a native worker that dies will never reply.

---

## 7. Invariants worth protecting

These are behaviours the code guarantees today. Changing them is a product decision, not a refactor.

1. **Originals are never modified or deleted.** Outputs are new files with `-kecil` in the name.
2. **A result is never larger than its source.** If re-encoding grows the file, the original bytes are copied instead.
3. **A file already under target is untouched** when it is already JPEG and no resize/format change was requested.
4. **The file extension never lies.** When the original is kept, its real extension is used, not the requested one.
5. **Nothing is uploaded.** The release manifest has no `INTERNET` permission.
6. **Cancelling leaves no partial output.**
7. **A batch continues past a single failure.**
8. **`main` is the integration point.** No circular dependencies between layers.

---

## 8. Known architectural limits

| Limit | Consequence |
| --- | --- |
| Android only | No `ios/` platform folder exists |
| Sequential batch | A 30-file batch is slower than a parallel one; memory stays bounded |
| Imperative navigation | No deep links, no state restoration across process death |
| Single worker thread | Two independent compressions cannot overlap (by design) |
| History stores absolute paths | Entries break if files are moved externally |
| `GalleryBridge.sanitize` duplicates `DownloadsSaver.sanitize` | 12 intentional, documented lines; consolidating would widen package visibility |
| PDF Form XObject images not compressed | Valid output, missed savings |

---

## 9. Where to change what

| Goal | Touches |
| --- | --- |
| New compression option | `CompressionOptions`, `setup_screen`, channel args, native `Options` |
| New output format | `OutputFormat`, `ImageCompressor`, `mimeFor` |
| New screen | `feature/`, registered from the screen that navigates to it |
| New permission | Manifest **and** `docs/security/privacy-architecture.md` **and** the PR checklist |
| New dependency | `pubspec.yaml` **and** the dependency rule in `docs/security/privacy-architecture.md` §10 |
| Change to the channel | Both Dart clients and `CompressBridge`, plus the contract table in this document |
