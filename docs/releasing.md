# Releasing

This document is for maintainers cutting a release. Contributors do not need it.

Two paths exist. The automated one is the default; the manual checklist is the
fallback for when Actions is unavailable.

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
new dated section using the heading form `## [1.0.0] — 2026-11-07`. The release
workflow reads that section for the release notes, so a missing or mistyped
heading means the notes fall back to GitHub's generated summary.

The tag is `v` plus the version before `+`: `1.0.0` becomes `v1.0.0`. The
workflow refuses to build when the tag and the `pubspec.yaml` version disagree.

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
  The keystore also never belongs in a git tag, a release asset, or an Actions
  artifact.
- `ci.yml` generates a throwaway keystore per run. Its artifacts are build proof
  only, never distributable.
- `release.yml` signs with the real key. The keystore is restored from
  environment secrets for the duration of one job and deleted at the end of it.
  This is the only workflow that produces artifacts anyone installs.

---

## 3. Automated release (GitHub Actions)

**This is the default path.** Cutting a release means pushing a tag.

1. `pubspec.yaml` is bumped, `CHANGELOG.md` has a matching section, and both are
   merged to `main`.
2. A maintainer pushes the tag: `git tag -a v1.0.0 -m "1.0.0"` then
   `git push origin v1.0.0`.
3. `.github/workflows/release.yml` starts and waits. It runs in the `release`
   environment, so a required reviewer must approve the deployment before any
   signing secret becomes available.
4. After approval the job restores the keystore, builds
   `flutter build apk --release --split-per-abi`, verifies the artifacts, and
   creates a **draft** GitHub release with exactly three assets:
   `kecilin-1.0.0-arm64-v8a.apk`, `kecilin-1.0.0-armeabi-v7a.apk`, and
   `SHA256SUMS.txt`.
5. A maintainer opens the draft, checks it, and publishes it.

The draft exists because the assets are what users install. If a check fails, no
release is created at all.

### What the workflow verifies

- The tag matches the `pubspec.yaml` version.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and
  `flutter test` pass on the tagged commit — the same gate as `ci.yml`, because a
  tag can point at a commit that never went through a pull request.
- Both APKs are signed with the release certificate: the signer SHA-256 must
  equal `RELEASE_CERT_SHA256`.
- Neither APK declares `android.permission.INTERNET`.
- `SHA256SUMS.txt` covers both APKs.

`x86_64` is deliberately excluded (emulator-only), and so is the AAB (signed with
the upload key, and Play re-signs it anyway, so it is useless to end users).

### Repository configuration

Set this up once, by hand, in GitHub repository settings. Nothing here is
committed to the repository.

| Setting | Where | Value |
| --- | --- | --- |
| Environment `release` | Settings → Environments | Required reviewers: at least one maintainer. Deployment branches and tags: tags matching `v*` only. "Allow administrators to bypass configured protection rules" **off**. |
| Environment secret `RELEASE_KEYSTORE_BASE64` | `release` environment → Environment secrets | The keystore file, base64-encoded on one line. |
| Environment secret `RELEASE_STORE_PASSWORD` | `release` environment → Environment secrets | The `storePassword` from `key.properties`. |
| Environment secret `RELEASE_KEY_ALIAS` | `release` environment → Environment secrets | The `keyAlias` from `key.properties` (`kecilin` for the setup above). |
| Environment secret `RELEASE_KEY_PASSWORD` | `release` environment → Environment secrets | The `keyPassword` from `key.properties`. |
| Repository variable `RELEASE_CERT_SHA256` | Settings → Secrets and variables → Actions → Variables | The certificate fingerprint (see below). A variable, not a secret: it is public by design. |
| Tag protection rule | Settings → Tags | Pattern `v*`; restrict who may create and delete these tags. |
| Immutable releases | Settings → General → Releases | Enabled. A published release and its assets cannot be moved afterwards. |

Environment secrets are only injected after the required reviewer approves, and
only for the environment's allowed refs. That restriction is what stops a branch
build from requesting the signing key.

**Base64 value:**

```bash
base64 -w0 android/keystore/kecilin-release.jks
```

macOS's `base64` has no `-w0`; `base64 -i android/keystore/kecilin-release.jks`
produces the same single-line output. Store the result as
`RELEASE_KEYSTORE_BASE64`. Wrapping or line breaks will make the decode produce a
corrupt keystore.

**Certificate fingerprint:**

```bash
keytool -list -v \
  -keystore android/keystore/kecilin-release.jks \
  -alias kecilin
```

Read the `SHA256:` line under `Certificate fingerprints`. `keytool` prints it
uppercase and colon-separated (`AA:BB:CC:...`). Paste it unchanged as
`RELEASE_CERT_SHA256`. The workflow strips colons and lowercases both sides
before comparing, so the colon-separated form and a bare lowercase hex string are
equivalent. Nothing else is.

If `RELEASE_CERT_SHA256` is missing, or the APK's signer does not match it, the
run fails. A debug-signed APK can never pass this check, which is why the
signing identity assertion is also the "not accidentally debug-signed" assertion.

### Signing identity across channels

GitHub Releases and Google Play will not share a signing key. Play App Signing
issues and holds its own app signing key; the AAB you upload is signed with an
upload key, and Play re-signs the artifacts it delivers.

Consequences, stated plainly:

- An APK installed from GitHub Releases cannot be updated by a build installed
  from Play, and the reverse. Android rejects an update whose signature differs.
- When the GitHub channel switches to Play-signed builds, existing sideload users
  must uninstall the app once and install it again from Play. In-app history and
  preferences are lost; files already saved to `Download/Kecilin` remain. This is
  an accepted, one-time cost of using Play App Signing, not a bug to work around.
- Keep GitHub Releases signed with `kecilin-release.jks` while sideload
  distribution is offered. The switch is user-visible, so announce it in the
  release that performs it.

Transferring the local key to Google was considered and rejected. Do not do it.

---

## 4. Manual release checklist (fallback)

Use this only when the automated path is unavailable — an Actions outage, or a
build that for some reason must be produced on a maintainer machine. It produces
the same artifacts by hand; the verification steps are not optional.

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
apksigner verify --print-certs build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk

# The offline guarantee: this must print no INTERNET permission
aapt2 dump permissions build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk

# Size sanity check against the previous release
ls -l build/app/outputs/apk/release/*.apk build/app/outputs/bundle/release/*.aab
```

If `aapt2 dump permissions` shows `android.permission.INTERNET`, **stop**. The
release build is not releasable, regardless of what else passes.

If `apksigner` is not on `PATH`, use the copy in
`$ANDROID_HOME/build-tools/<version>/`, same for `aapt2`.

---

## 5. Install a release build on a device

```bash
adb install -r build/app/outputs/apk/release/kecilin-1.0.0-arm64-v8a.apk
```

Then, by hand:

1. Compress one image and one PDF end to end.
2. Confirm the output lands in `Download/Kecilin`.
3. Confirm the original file is untouched.
4. Open the output from the app once (share sheet / open-with path).
5. Watch `adb logcat` for `FATAL EXCEPTION` or a missing-class error while doing it.

R8 regressions only appear at runtime, so this step is not optional.

---

## 6. Publishing

**GitHub Releases (default)**

1. Open the draft created by the workflow.
2. Check the version in the title and body against `pubspec.yaml` and
   `CHANGELOG.md`.
3. Check the asset list: `kecilin-1.0.0-arm64-v8a.apk`,
   `kecilin-1.0.0-armeabi-v7a.apk`, `SHA256SUMS.txt`. Nothing else.
4. Install the arm64 APK on a device and run the checks in section 5.
5. Publish. Users can verify a download with `sha256sum -c SHA256SUMS.txt`.

**Google Play**

1. Build and upload `build/app/outputs/bundle/release/app-release.aab` to the
   internal testing track first. The workflow builds APKs only, so the AAB has to
   be produced locally.
2. Check the Play Console pre-launch report and the declared permissions. There
   should be no network permission and no data-safety disclosure of collected
   data.
3. Promote to production only after the internal build has been installed from
   Play at least once.

**Direct distribution (sideload, manual path)**

Ship `kecilin-1.0.0-arm64-v8a.apk`; it covers essentially every phone released in
the last several years. Include `armeabi-v7a` only for older 32-bit devices, and
never `x86_64` — that one is for emulators.

Always state the version and the commit the APK was built from.

---

## 7. After the release

- Tag the commit: `git tag -a v1.0.0 -m "1.0.0"` and push the tag. On the
  automated path this is the release trigger, not an afterthought.
- Approve the `release` deployment when GitHub asks.
- Publish the draft once it looks right.
- On the manual path, attach the APK and the AAB to the GitHub release by hand,
  plus a short summary of what changed.
- Confirm `CHANGELOG.md` matches the tag.

## 8. If something goes wrong

- **Release workflow failed:** re-run the job from the Actions UI. If it had
  already created a draft, the re-run replaces that draft. It refuses to touch a
  release that is already published.
- **Bad build already published:** halt the rollout in Play Console. For direct
  distribution, delete the release and publish a patch version — never re-upload
  an APK under the same version code.
- **Keystore compromised:** rotate immediately. A new key means a new app id or a
  Play App Signing key reset request; plan for the migration before announcing it.
- **A file-corrupting bug is reported:** treat it as a security issue, follow
  [`SECURITY.md`](../SECURITY.md), and cut a patch release.
