# Posteight Contributor Guide

## Project Overview

Posteight is a macOS SwiftUI sticky-note checklist app. It keeps today's work visible on screen and stores notes locally for the current prototype.

## Repository Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
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

For a distributable bundle, use Product > Archive in Xcode.

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
- The store migrates data from the legacy `Posteat` storage keys; do not remove that compatibility without a migration plan.
- Keep interactive changes focused and test text editing, checklist completion, note movement, resizing, trash, and persistence when those areas change.

## Git Workflow

- Commit to `main` directly. This project does not use feature branches.
- Keep commits focused on one feature or change.
- Run `swift build` before every commit.
- Do not commit `.build/` or `dist/`; both are generated locally and ignored by Git.
