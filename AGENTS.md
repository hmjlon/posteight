# Posteight Contributor Guide

## Project Overview

Posteight is a macOS SwiftUI sticky-note checklist app. It keeps today's work visible on screen and stores notes locally for the current prototype.

## Product and Design Direction

Before changing product behavior, UX, or visual design, read the `Product Direction`
section in `README.md`. Treat it as the current source of truth for product positioning,
experience principles, menu bar behavior, design direction, priorities, and non-goals.
When those decisions change, update `README.md` in the same change.

## Repository Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
- `Tests/PosteightTests/`: unit tests for the store's pure logic and its save path
- `Posteight.xcodeproj`: Xcode app target; builds the real `.app` bundle
- `Package.swift`: Swift Package Manager configuration, for fast command-line builds
- `Packaging/Info.plist`: macOS app bundle metadata, shared by both build paths

The landing page is not in this repository. It lives in [posteight-landing](https://github.com/hmjlon/posteight-landing); send web changes there.

## Development Commands

There are two build paths. Use Xcode when you touch anything the bundle owns
(`Info.plist`, entitlements, signing, the app icon); use SwiftPM for a fast
compile check.

Open the app project in Xcode:

```bash
xed Posteight.xcodeproj
```

Build the real `.app` from the command line:

```bash
xcodebuild -project Posteight.xcodeproj -scheme Posteight -configuration Debug build
```

Fast compile check, no bundle:

```bash
swift build
```

Run the tests:

```bash
swift test
```

A distributable dmg comes from pushing a `v*` tag on `release`; `.github/workflows/release.yml`
builds and publishes it. Product > Archive in Xcode still works for a local one-off.

`swift run` still works, but it launches an unbundled binary: `Bundle.main.bundleIdentifier`
is `nil`, so macOS logs `linkd`/Process Instance Registry XPC failures and window positions
are saved separately. Those messages are noise, not app bugs. Run the Xcode target when the
bundle matters.

The project targets macOS 14 or later on Apple silicon only; `ARCHS` is pinned to `arm64`,
so the app does not run on Intel Macs. `Sources/Posteight` is a file system synchronized
group, so adding or deleting a Swift file needs no `project.pbxproj` change.

Keep every build setting in `Posteight.xcodeproj`. It is the only thing that builds the
app, and a second build path drifts out of sync with it.

## Implementation Notes

- Keep the visible product name as `Posteight`.
- Preserve the current local note and trash behavior unless a change is intentional.
- Notes live in `~/Library/Application Support/Posteight/`. Writes are debounced, so any new
  quit or sleep path must call `PosteightStore.flush()` or it drops the last half second of edits.
- The store still reads the legacy `UserDefaults` and `Posteat` keys so older installs migrate
  on first launch; do not remove that fallback without a migration plan.
- Title migration rewrites what users typed, so it is covered by tests. Change
  `legacyTitleDate` only with a test proving current-style titles stay untouched.
- Keep interactive changes focused and test text editing, checklist completion, note movement, resizing, trash, and persistence when those areas change.

## Git Workflow

- Commit to `dev` directly. This project does not use per-feature branches.
- `release` only receives merges from `dev`. Version tags are cut on `release`.
- Keep commits focused on one feature or change.
- Run `swift test` before every commit.
- Do not commit `.build/` or `dist/`; both are generated locally and ignored by Git.
