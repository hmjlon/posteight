# Posteight

Posteight is a local macOS sticky-note checklist app that keeps today's work visible across the desktop.

## Features

- Independent floating windows that can be moved and resized anywhere
- Frosted, colored paper with a compact glass toolbar
- Checklists with animated pen strike-through effects
- Paper colors, pen colors, pen styles, and category stickers
- Local persistence for note content, position, size, and appearance
- Trash with restore and permanent-delete actions
- Per-note "Notion log" toggle
- Daily work log preview and clipboard export as Markdown

## Develop with Xcode

Open the app project:

```bash
xed Posteight.xcodeproj
```

In Xcode, select the `Posteight` scheme and `My Mac`, then press `Command-R` to build and run.

For a fast command-line compile check:

```bash
swift build
```

Run the unit tests:

```bash
swift test
```

For a distributable app, use **Product > Archive** in Xcode.

## Project Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
- `Tests/PosteightTests/`: store and persistence tests
- `Posteight.xcodeproj`: Xcode app target and build settings
- `Packaging/Info.plist`: macOS bundle metadata

## Landing Page

The landing page lives in its own repository: [posteight-landing](https://github.com/hmjlon/posteight-landing).

## License

Proprietary. See [LICENSE](LICENSE). This is not open source.

## Current Scope

This prototype targets macOS 14 or later and stores notes locally in `~/Library/Application Support/Posteight/`. Notion synchronization is not implemented yet; the current integration surface is Markdown preview and export.
