# Posteight

Posteight is a local macOS sticky-note checklist app that keeps today's work visible across the desktop.

## Product Direction

Posteight began with a simple workplace problem: paper sticky notes keep today's
tasks visible, but their contents remain exposed on a shared desk. Traditional
task managers are private, but the next action often disappears inside another
app.

Posteight combines the useful parts of both:

> Private sticky notes for your Mac — visible on your terms.

The product is intended for people who work on a Mac in open offices, shared
workspaces, or screen-sharing-heavy environments. Notes should remain easy for
the owner to see during work and easy to hide when the situation changes.

This is visual privacy, not a security-vault promise. Posteight can reduce
accidental exposure when the user steps away or shares a screen, but it cannot
prevent someone nearby from reading content that is currently visible on an
unlocked display.

### Experience Principles

- **Quick to place:** capture a task without leaving the current workflow.
- **Hard to forget:** keep independent notes where the work happens.
- **Easy to hide:** provide one clear control for hiding and restoring every note.
- **Private by default:** keep notes local and make any external export explicit.
- **Satisfying to finish:** preserve the pen-like completion interaction as the
  app's signature moment.
- **Quiet when idle:** remain available without adding visual noise or Dock clutter.

### Menu Bar Experience

Posteight runs as a compact macOS menu bar utility. There is no workspace window:
the status item is the only permanent surface, and its icon carries the
remaining-task count. The popover is the control center for quick capture,
showing every note, the daily log, the trash, and quitting. Floating notes remain
the main working surface; the popover should not become a second full editor.

The status item shows progress as a fraction — remaining over total by default,
or done over total. Clicking it opens the popover, which is also where settings
live: the settings entry opens a modal dialog over whatever is on screen.

Settings stay deliberately small: what the status item counts, whether notes
float above other apps, and whether Posteight keeps a Dock icon. The Dock icon is
on by default, so a running Posteight can be reached from the Dock and
Command-Tab, and clicking it brings every note back. Turning it off leaves a
menu-bar-only app. Hiding all notes and a manual meeting mode are still to come.

### Design Direction: Folded Card

The selected visual foundation is **Folded Card**: a warm, matte task card with a
single folded top-right corner as Posteight's signature silhouette.

- Treat each note as one continuous piece of paper, without an app-like title bar.
- Use the folded corner, not glassmorphism or a grid pattern, as the primary visual
  identity.
- Keep texture close to subtle natural paper fibers rather than a visible
  decorative pattern.
- Use a restrained palette of ivory, blush, sage, mist, butter, and lilac paper.
- Keep the checklist visually dominant and reveal editing controls on hover.
- Name each card in its header — `Posteight 1`, `2`, `3` by default, renamed freely — so a
  note can stand for a category such as 업무 or 학업. Stickers repeat that idea as symbols.
- Keep the menu bar and popover compact, native, and mostly monochrome.
- Use motion sparingly; the pen strike-through remains the signature completion
  moment.

The folded-card shell is implemented in the current prototype, and the app icon
reuses the same silhouette: a butter-ivory card with the folded top-right corner
and one struck-through line. Typography,
spacing, hover behavior, and the menu bar experience will continue to be
refined one decision at a time.

### Product Priorities

1. Reliable local persistence and exact window restoration across relaunches,
   displays, and Spaces
2. Global show/hide control, hide-on-lock behavior, and a dependable manual
   meeting mode
3. Menu bar quick capture and keyboard-first checklist interaction
4. A lightweight daily flow for completion, optional rollover, and explicit
   Markdown export

Full collaboration, accounts, cloud sync, AI features, and deep third-party
integrations are outside the current focus.

## Current Prototype Features

- Independent floating windows that can be moved and resized anywhere
- Matte folded-card surfaces with subtle paper grain and hover editing controls
- Checklists with animated pen strike-through effects
- Paper colors, pen colors, pen styles, and category stickers
- Local persistence for note content, position, size, and appearance
- Trash with restore and permanent-delete actions
- Per-note "Notion log" toggle
- Daily work log preview and clipboard export as Markdown

## Install

Posteight requires **macOS 14 (Sonoma) or later** on **Apple silicon**. Intel Macs
are not supported; `ARCHS` is pinned to `arm64`.

With Homebrew:

```bash
brew install --cask hmjlon/posteight/posteight
```

Or download the latest `.dmg` from [Releases](https://github.com/hmjlon/posteight/releases)
and drag Posteight to Applications.

### First launch

Posteight is not notarized by Apple yet, so macOS blocks it the first time it runs.

1. Open Posteight. macOS shows a warning and refuses to launch it.
2. Open **System Settings > Privacy & Security**.
3. Scroll down and click **Open Anyway**.

This is a one-time step per install. From a terminal, the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/Posteight.app
```

Notarization needs a paid Apple Developer Program membership. Until that is in
place, this step is unavoidable for anyone but the person who built the app.

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

## Releasing

Releases are built by CI, not by hand. Pushing a `v*` tag runs
[`release.yml`](.github/workflows/release.yml), which stamps the version from the
tag, builds the Release configuration, packages a `.dmg`, and publishes it to
GitHub Releases with its checksum:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The tag is the only source of truth for the version. `Packaging/Info.plist` reads
`$(MARKETING_VERSION)`, so never hardcode a version there.

Every push to `main` and every pull request runs [`ci.yml`](.github/workflows/ci.yml):
`swift test` for the unit tests, and `xcodebuild` for the real `.app` bundle.

`Product > Archive` in Xcode still works for a local one-off build.

## Project Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
- `Tests/PosteightTests/`: store and persistence tests
- `Posteight.xcodeproj`: Xcode app target and build settings
- `Packaging/Info.plist`: macOS bundle metadata
- `.github/workflows/`: CI and release automation

## Landing Page

The landing page lives in its own repository: [posteight-landing](https://github.com/hmjlon/posteight-landing).

## License

Proprietary. See [LICENSE](LICENSE). This is not open source.

## Current Scope

This prototype targets macOS 14 or later and stores notes locally in `~/Library/Application Support/Posteight/`. Notion synchronization is not implemented yet; the current integration surface is Markdown preview and export.
