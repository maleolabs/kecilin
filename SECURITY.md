# Security Policy

## Reporting a vulnerability

**Do not** open a public issue for a security or privacy problem.

Use these channels, in order of preference:

1. **GitHub Security Advisory** — the *Security* tab → *Report a vulnerability* on this repository (private, visible only to maintainers).
2. **Email** the Maleo Labs maintainers with the subject `[SECURITY] Kecilin`.

Include where possible:

- app version (from *Settings* → bottom of the screen) and build type (release/debug)
- Android version and device model
- the shortest reproduction steps
- the impact you believe it has
- whether user files could be read, modified, or lost

We will confirm receipt within 3 business days and give an estimate for the fix.

## Scope

**In scope:**

- disclosure of user data (files, file names, paths, document contents)
- any path that lets a file leave the device without the user acting
- bypassing Android permission checks
- corrupted or unopenable output files, especially ones that could overwrite or delete the original
- code execution through a malicious file processed by the app
- signing material or credentials committed to the repository

**Out of scope:**

- scenarios requiring root, unbounded physical access, or an already-rooted device
- attacks that depend on the user installing a debug APK
- automated scanner output without a demonstrated impact
- weak on-device storage encryption (the operating system's responsibility)

## Principles we hold

1. **No uploads.** Release builds do not declare the `INTERNET` permission. If you find any network path in a release build, that is a vulnerability — report it.
2. **Original files are never modified or deleted.** If you find a case where a source file changes or disappears, that is a high-priority vulnerability.
3. **No telemetry.** No analytics, no crash reporting. Nothing is collected without an explicit user action.
4. **No credentials in the repository.** CI fails if signing material or `.env` files get tracked.

## What we ask of you

- Give us reasonable time to fix the issue before publishing.
- Do not access other people's data while testing.
- Do not test on devices or accounts that are not yours.

## Supported versions

Only the latest release receives security fixes. The project does not yet have a
public release cycle; until it does, use the latest build from `main`.

Thank you for helping keep an app that handles personal documents safe.
