# Kecilin — Privacy Architecture

**Purpose:** state precisely what data Kecilin touches, where it goes, how long it lives, and what would have to change for the privacy promise to break.
**Audience:** maintainers, security reviewers, and anyone evaluating the app before installing it.

This document describes the implementation as it exists. Where something is unknown or unmeasured, it says so.

---

## 1. The promise, and what enforces it

Kecilin's claim is: **your documents are compressed on your phone and never leave it.**

Three independent mechanisms enforce it.

| Mechanism | Strength |
| --- | --- |
| The release manifest does not declare `INTERNET` | **Strong.** Android blocks socket creation at the platform level. Library code cannot bypass a missing permission. |
| No networking dependency is compiled into the app | Strong. Nothing is present to attempt a connection. |
| No analytics, crash reporting, or remote config SDK | Strong. There is no telemetry channel to leak metadata through. |

The promise is not enforced by developer discipline. It is enforced by the absence of a permission that the OS checks.

### What would break it

Any of these changes would invalidate the guarantee and must trigger a privacy review:

- adding `<uses-permission android:name="android.permission.INTERNET"/>` to `src/main/AndroidManifest.xml`
- adding any dependency that performs network I/O (`http`, `dio`, `firebase_*`, `sentry_flutter`, `amplitude`, …)
- adding a `WebView`
- adding a `google-services.json` or equivalent
- adding a share **extension** or background service that transmits files

The pull request template asks about all of these.

---

## 2. Data inventory

| Data | Category | Collected? | Stored where | Leaves device |
| --- | --- | --- | --- | --- |
| Selected image / PDF contents | Document | Processed only | Read from source path; output written to app documents dir | No |
| File name | Metadata | Yes (locally) | `SharedPreferences` history, up to 40 entries | No |
| Source file path | Metadata | Yes (locally) | `SharedPreferences` history | No |
| Output file path | Metadata | Yes (locally) | `SharedPreferences` history | No |
| File size (source/output) | Metadata | Yes (locally) | `SharedPreferences` history | No |
| Page count | Metadata | Yes (locally) | `SharedPreferences` history | No |
| Processing duration | Telemetry-like, local only | Yes (locally) | `SharedPreferences` history | No |
| Image dimensions | Metadata | In memory only | Not persisted | No |
| EXIF / GPS metadata | Sensitive metadata | **Stripped** on re-encode | Written outputs contain no metadata | No |
| Compression preferences | Settings | Yes (locally) | `SharedPreferences` | No |
| Theme preference | Settings | Yes (locally) | `SharedPreferences` | No |
| Device identifiers (IMEI, Android ID, advertising ID) | Identifier | **No** | — | No |
| Location | Sensitive | **No** | — | No |
| Contacts, calendar, SMS, call log | Sensitive | **No** | — | No |
| Camera / microphone | Sensitive | **No permission requested** | — | No |
| Crash reports | Diagnostics | **No SDK** | — | No |
| Usage analytics | Telemetry | **No SDK** | — | No |
| Account / email / phone | Personal | **No account system exists** | — | No |

There is no user account, no sign-in, no cloud sync, and no server. Kecilin cannot associate anything with a person because it never learns who they are.

---

## 3. Data flows

### 3.1 Image compression

```
[user picks a file]
        │
        ├── system picker (SAF): app receives a content URI it can read
        └── in-app gallery: app copies the original into cacheDir/gallery-in
                                    (so native code can open a real file path)
        │
        ▼
[native decode: bounds → sampled decode → EXIF rotation applied to pixels]
        │
        ▼
[encode: binary-search quality against optional byte target]
        │
        ▼
[app documents dir: <stem>-kecil.jpg/webp]
        │
        ├── "never bigger than source" guard may copy the original instead
        ├── optional: publish to Download/Kecilin via MediaStore (user setting)
        └── optional: hand the file to the OS share sheet (explicit user action)
                                    │
                                    └── this is the ONLY path off the device,
                                        and the user chooses the destination
```

### 3.2 PDF compression

Same shape. Two engines:

- **Ringan (light):** PDFBox rewrites embedded JPEG streams in place, keeps the text layer, strips document metadata.
- **Agresif (raster):** `PdfRenderer` renders each page, JPEG-encodes it, and a hand-written writer emits a new PDF. Text layer is intentionally lost; the UI warns first.

Neither path contacts anything. PDFBox scratch space is `cacheDir/pdfbox`, configured as temp-file-only so large documents do not exhaust the heap.

### 3.3 Share action

`share_plus` hands a file path to the Android share sheet. The OS then shows the user which apps can receive it. Kecilin does not know or record the destination, and does not upload anything itself.

This is a deliberate user-initiated egress. It is the only one.

---

## 4. Storage and retention

| Location | Contents | Lifetime | Cleared by |
| --- | --- | --- | --- |
| `<app documents>/Kecilin/` | Compressed results | Until the user deletes them | "Hapus file hasil" (delete result files) in settings; app uninstall |
| `cacheDir/gallery-in/` | Copies of gallery picks | Until next app start (or explicit cleanup) | `main()` on launch; "Hapus file hasil" |
| `cacheDir/gallery-thumbs/` | 320 px thumbnails | Until next app start | same |
| `cacheDir/pdfbox/` | PDFBox scratch | Until next app start | same |
| `SharedPreferences` (`history.v2`) | Last 40 job records | Until the user clears history | "Hapus riwayat" (clear history); app uninstall |
| `SharedPreferences` (`settings.v2`) | Theme, auto-save, last options | Permanent | App uninstall |

Design notes:

- Results live in the app's documents directory, not in shared storage. Copying into `Download/Kecilin` happens only through MediaStore, only for files the user produced, and only on an explicit action or the auto-save setting.
- Cache cleanup runs at startup rather than at exit. An exit-time sweep can race with an in-flight compression; a startup sweep always runs before any new work begins. The cost is that a staged copy can survive until the next launch. It is inside an app-private directory.
- The history deliberately keeps absolute paths so "open the result" and "reuse a source" work after restart. If a file is deleted externally, the entry still renders but the action fails with a clear message. This is the one place where persistent file paths exist, and it is why history is user-clearable.

### 4.1 Backup exclusion

`allowBackup="false"`, `fullBackupContent="false"`, and `data_extraction_rules.xml` excluding `root`, `file`, `database`, `sharedpref`, and `external` from **both** cloud backup and device-to-device transfer.

Rationale: a document tool should not silently replicate a user's compression history — including file names that reveal what was compressed — into a Google account or onto a new phone during setup. The cost is that reinstalling loses history and settings. That is the correct trade.

---

## 5. Permissions, and why each one exists

| Permission | Ask when | What it enables | If denied |
| --- | --- | --- | --- |
| `READ_MEDIA_IMAGES` (33+) | On opening the in-app gallery | Grid of recent photos with thumbnails | System picker + Kecilin history remain usable |
| `READ_MEDIA_VISUAL_USER_SELECTED` (34+) | Same | Partial access: user selects which photos to expose | Same fallbacks |
| `READ_EXTERNAL_STORAGE` (≤ 32) | Same | Gallery on older Android | Same fallbacks |

Not requested, by design: `WRITE_EXTERNAL_STORAGE` (MediaStore handles writes), `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `MANAGE_EXTERNAL_STORAGE` (all explicitly removed in the manifest), camera, microphone, location, contacts, `INTERNET`, and any advertising ID permission.

### 5.1 The honest trade-off

The in-app gallery is a **convenience feature**, not a functional requirement. The primary picker (`file_selector`) uses the Storage Access Framework and requires no permission at all. The media permissions exist because the grid wants to show recent photos without forcing a full picker dialog every time.

If a future version wants to minimise its permission surface aggressively, removing the custom gallery and relying solely on SAF would remove all three media permissions at the cost of the thumbnail grid. That is a product decision, not a security defect, and it is recorded here so the trade-off is visible rather than implicit.

Android 14+ partial access is treated as a first-class state (`GalleryAccess.partial`), not as an error: the grid shows what the user allowed and the picker keeps working.

---

## 6. Metadata handling

| Metadata | Behaviour |
| --- | --- |
| EXIF orientation | Applied to pixels, then discarded — the rotated image is correct without the tag |
| EXIF GPS | **Dropped.** Re-encoding through a bitmap produces no EXIF. This is a deliberate privacy property, not an accident. |
| Camera make/model, timestamps | Dropped for images |
| ICC profile | Not preserved through bitmap re-encode |
| PDF document metadata (author, title, producer, creation dates) | Explicitly removed in Ringan mode |
| PDF XMP | Not preserved through rewrite |

Two consequences worth stating plainly:

1. Compressed images are **more** private than the originals for photos, because location data is destroyed.
2. "Maximum" image mode advertises "metadata removed" in the UI, so the behaviour is user-visible rather than surprising.

Note the inverse edge case: if a file is already smaller than the requested
target, Kecilin **copies the original unchanged** instead of re-encoding. In that
case existing metadata is preserved, because modifying a file that needs no
modification would be worse. This is documented behaviour, and the UI reports
"file tidak diubah" (file unchanged).

---

## 7. What Kecilin specifically does not do

- No account, login, or identity.
- No upload, ever, of any file.
- No filename, path, or metadata transmission.
- No crash reporting, so a stack trace never leaves the phone.
- No analytics, so no usage funnel exists.
- No advertising SDK, so no advertising ID.
- No remote configuration, so no behaviour is changed from outside.
- No A/B testing.
- No third-party SDK that receives data.
- No `WebView`.
- No logging of file contents, names, or paths — there is no logging framework at all.

---

## 8. Threat model

| Threat | Impact | Mitigation |
| --- | --- | --- |
| Another app reading Kecilin's files | Document disclosure | App-private storage; `cacheDir` is unreadable by other apps on Android 7+ |
| Cloud backup leaking history/filenames | Metadata disclosure | Backup and device transfer fully disabled |
| An attacker on the network | Remote data theft | No network permission exists; there is no channel to attack |
| Malicious file exploiting native decoders | Code execution | Standard Android `BitmapFactory` / `PdfRenderer` / PDFBox paths. No custom parsers. Known residual risk shared with any document tool. |
| Filename-based attacks (path traversal, extension spoofing) | Writing outside intended directory, misleading the user | Central sanitisation strips separators and bidi overrides; outputs are always generated names, never user-supplied paths |
| Lost or stolen device | Document disclosure | Out of scope — relies on OS-level device encryption and screen lock |
| Malicious build of the app | Everything | Out of scope — the release is signed; install only trusted builds |
| Debug APK distributed by mistake | `INTERNET`-enabled build in the wild | Release signing fails closed; README documents the constraint; CI builds release |

---

## 9. Verifying these claims yourself

```bash
# 1. No network permission in the release manifest
grep -c "android.permission.INTERNET" android/app/src/main/AndroidManifest.xml   # expect 0

# 2. No network dependency
grep -E "http|dio|socket|firebase|sentry" pubspec.yaml                            # expect nothing

# 3. No network calls in application code
grep -rn "HttpClient\|Dio\|WebView" lib/ android/app/src/main/kotlin/             # expect nothing

# 4. Backup disabled
grep -E "allowBackup|fullBackupContent" android/app/src/main/AndroidManifest.xml   # expect both false

# 5. No personal documents committed
git ls-files | grep -Ei '\.(jpe?g|pdf|docx?)$'                                    # expect nothing

# 6. Permissions actually present
aapt2 dump permissions build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk
```

The `aapt2` dump is the authoritative check: it lists what the merged release manifest actually declares, after library merging and `tools:node="remove"` stripping.

---

## 10. Change policy

Any change that touches the following requires a privacy review before merge:

1. The Android manifest (any permission).
2. `pubspec.yaml` dependencies.
3. The share/open code path.
4. Anything that persists a new category of data.
5. Anything that constructs a URL or a socket.

The review question is not "does this send data today" but "does this create a channel that could later send data without anyone noticing".
