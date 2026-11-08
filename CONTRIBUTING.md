# Contributing to Kecilin

Thanks for taking the time to contribute. Kecilin handles personal documents, so
the bar here is a bit higher than "it compiles": a change that risks a user's
file is a change we cannot merge.

## Before you start

For anything larger than a typo or a one-line fix, open an issue first and
describe what you intend to change. It saves you from building something that
does not fit the design.

Good first contributions:

- a failing test that reproduces a bug
- documentation that is wrong or unclear
- an accessibility or layout fix in the Flutter UI
- a compression case that produces a worse result than it should

## Prerequisites

| Tool | Version |
| --- | --- |
| Flutter | 3.38.x (stable) |
| Dart | 3.10.x (ships with Flutter) |
| JDK | 21 (Temurin or the Android Studio JBR) |
| Android SDK | API 36 platform + build tools |
| Gradle | use the wrapper — do not install your own |

> JDK 25 currently breaks the Kotlin `JavaVersion` parser used by the Gradle
> plugin (`25.0.4.1`). Stick to 21 unless you are prepared to debug that.

## Setup

```bash
git clone git@github.com:maleolabs/kecilin.git
cd kecilin
flutter pub get
flutter run          # needs a connected device or a running emulator
```

## Before you open a pull request

Every one of these must pass locally. CI runs the same set.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze                  # must report 0 issues
flutter test                     # 22 unit + widget tests
```

If your change touches the Kotlin engines (anything under
`android/app/src/main/kotlin/`), run the on-device suite as well:

```bash
./tool/test_fixtures.sh
# add "- integration_test/assets/" to the existing assets: list in pubspec.yaml
flutter test integration_test/compression_test.dart -d DEVICE_ID
# remove the line again
rm -rf integration_test/assets
```

`integration_test/assets/` is gitignored and must never be committed.

## Coding standards

- **Formatting** is `dart format` — not a matter of taste, just run it.
- **Lints** live in `analysis_options.yaml`. Unused code is an error, not a hint.
  Do not add `// ignore:` comments without a one-line reason.
- **Comments explain why, not what.** English, full sentences, no commented-out
  code left behind.
- **No new dependencies** without a justification in the pull request. Every
  dependency is a maintenance and supply-chain liability.
- **Do not replace a working engine.** The compression algorithms are the product;
  changes there need measured before/after numbers, not opinions.
- **Keep the layering.** `lib/data/` talks to platform channels, `lib/domain/` holds
  pure logic and models, `lib/feature/` holds screens. Do not import Flutter
  widgets from `domain/`.

## Invariants you must not break

These are contract-level, not stylistic:

1. The original file is never modified or deleted.
2. Output is never larger than the source; if re-encoding grows it, return the original bytes.
3. A file already below target is left untouched unless a resize was requested.
4. The file extension always matches the actual encoding.
5. Cancelling leaves no partial output file.
6. One failing item does not abort the rest of the queue.
7. Release builds declare no `INTERNET` permission.

If a change requires breaking one of these, open an issue and argue for it
explicitly. Do not slip it into a refactor.

## Pull requests

- Keep them small and single-purpose. Reviewing a 900-line diff is not review.
- Describe the problem, the change, and how you verified it.
- Include before/after numbers if the change affects output size or speed.
- Fill in the pull request template; the checklist is not decoration.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`). One logical change per
commit.

## Security-sensitive changes

Anything touching file I/O, permissions, the manifest, `MediaStore`, or signing
gets an additional review pass. Never commit keystores, `key.properties`, `.env`
files, or anything that looks like a credential. If you think you spotted one in
the repository, report it privately following [`SECURITY.md`](SECURITY.md).

## Community

Be direct and be kind. Critique code, not people. Assume the other person read
the code before commenting on it — because they did.
