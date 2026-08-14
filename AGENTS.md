# Posteight Contributor Guide

## Project Overview

Posteight is a macOS SwiftUI sticky-note checklist app. It keeps today's work visible on screen and stores notes locally for the current prototype.

## Repository Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
- `Package.swift`: Swift Package Manager configuration
- `Packaging/Info.plist`: macOS app bundle metadata
- `build_app.sh`: creates the local `dist/Posteight.app` release bundle

The landing page is not in this repository. It lives in [posteight-landing](https://github.com/hmjlon/posteight-landing); send web changes there.

## Development Commands

Run the debug app:

```bash
swift run
```

Build the project:

```bash
swift build
```

Create the double-clickable macOS app bundle:

```bash
./build_app.sh
```

The project targets macOS 14 or later.

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
