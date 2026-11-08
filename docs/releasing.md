# Releasing

This document is for maintainers cutting a release. Contributors do not need it.

---

## 1. Versioning

The version lives in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^     ^
#        |     build number (must increase for every upload to Play)
#        semantic version shown to users
```

Bump both parts. `flutter build` propagates them to the Android manifest, so do
not edit `versionCode`/`versionName` in Gradle.

Update `CHANGELOG.md` in the same commit: move entries from `[Unreleased]` into a
new dated section.

---

## 2. Signing setup (once per machine)

Release builds fail closed: without `android/key.properties`, Gradle stops with
an explicit error. That is deliberate — a release APK silently signed with a
debug key is worse than a failed build.

```bash
keytool -genkeypair \
  -keystore android/keystore/kecilin-release.jks \
  -storetype PKCS12 \
  -alias kecilin \
  -keyalg RSA -keysize 4096 -validity 10000

cp android/key.properties.example android/key.properties
# then fill in storeFile, storePassword, keyAlias, keyPassword
```

Rules that are not negotiable:

- `android/key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.pem`, `*.key` are
  gitignored. Keep it that way.
- Back the keystore and its passwords up somewhere offline. Losing them means you
  can never ship an update to the same app id again.
- Never paste the passwords into an issue, a commit, a CI log, or a screenshot.
- CI uses a throwaway keystore generated per run. CI artifacts are build proof
  only, never distributable.

---

## 3. Release checklist

Run every step. Skipping the verification step is how a release with a broken
permission declaration reaches users.

```bash
# 1. Clean tree
git status --short          # must be empty
git pull

# 2. Gate
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze             # 0 issues
flutter test                # all pass

# 3. On-device engines (needs a connected device)
./tool/test_fixtures.sh
# add "- integration_test/assets/" to the assets: list in pubspec.yaml
flutter test integration_test/compression_test.dart -d DEVICE_ID
# remove that line
rm -rf integration_test/assets

# 4. Build
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Then verify the artifacts before publishing:

```bash
# Signed with the release key, not the debug key
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# The offline guarantee: this must print no INTERNET permission
aapt2 dump permissions build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Size sanity check against the previous release
ls -l build/app/outputs/flutter-apk/*.apk build/app/outputs/bundle/release/*.aab
```

If `aapt2 dump permissions` shows `android.permission.INTERNET`, **stop**. The
release build is not releasable, regardless of what else passes.

---

## 4. Install a release build on a device

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Then, by hand:

1. Compress one image and one PDF end to end.
2. Confirm the output lands in `Download/Kecilin`.
3. Confirm the original file is untouched.
4. Open the output from the app once (share sheet / open-with path).
5. Watch `adb logcat` for `FATAL EXCEPTION` or a missing-class error while doing it.

R8 regressions only appear at runtime, so this step is not optional.

---

## 5. Publishing

**Google Play**

1. Upload `build/app/outputs/bundle/release/app-release.aab` to the internal
   testing track first.
2. Check the Play Console pre-launch report and the declared permissions. There
   should be no network permission and no data-safety disclosure of collected
   data.
3. Promote to production only after the internal build has been installed from
   Play at least once.

**Direct distribution (sideload)**

Ship `app-arm64-v8a-release.apk`; it covers essentially every phone released in
the last several years. Include `armeabi-v7a` only for older 32-bit devices, and
never `x86_64` — that one is for emulators.

Always state the version and the commit the APK was built from.

---

## 6. After the release

- Tag the commit: `git tag -a v1.0.0 -m "1.0.0"` and push the tag.
- Attach the APK and the AAB to the GitHub release, plus a short summary of what
  changed.
- Confirm `CHANGELOG.md` matches the tag.

## 7. If something goes wrong

- **Bad build already published:** halt the rollout in Play Console. For direct
  distribution, delete the release and publish a patch version — never re-upload
  an APK under the same version code.
- **Keystore compromised:** rotate immediately. A new key means a new app id or a
  Play App Signing key reset request; plan for the migration before announcing it.
- **A file-corrupting bug is reported:** treat it as a security issue, follow
  [`SECURITY.md`](../SECURITY.md), and cut a patch release.
