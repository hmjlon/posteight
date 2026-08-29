# Posteight Contributor Guide

## Project Overview

Posteight is a macOS SwiftUI sticky-note checklist app. It keeps today's work visible on screen and stores notes locally for the current prototype.

## Product and Design Direction

Before changing product behavior, UX, or visual design, read [docs/PRODUCT.md](docs/PRODUCT.md).
Treat it as the current source of truth for product positioning, experience principles, menu bar
behavior, design direction, priorities, and non-goals. When those decisions change, update that
file in the same change.

## Repository Structure

- `Sources/Posteight/`: SwiftUI views, models, and local persistence
- `Tests/PosteightTests/`: unit tests for the store's pure logic and its save path
- `Posteight.xcodeproj`: Xcode app target; builds the real `.app` bundle
- `Package.swift`: Swift Package Manager configuration, for fast command-line builds
- `Packaging/Info.plist`: macOS app bundle metadata, shared by both build paths
- `docs/PRODUCT.md`: product and design direction — the source of truth for behaviour decisions
- `docs/images/`: README screenshots
- `README.md` / `README.ko.md`: for people installing the app, not for people building it

The landing page is not in this repository and does not exist yet; when it does, link it here.

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

A distributable dmg comes from pushing a `v*` tag on `release`; see `Releasing` below.

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

## Language

Posteight draws its own UI in Korean or English, switched in Settings with no relaunch. Korean is
the source language, and the Korean string itself is the lookup key.

- Every user-visible string goes through `L("한국어")`, or `Lf("메모 %d", n)` when it has a
  placeholder. String literals left bare ship untranslated.
- Add the English entry to `englishStrings` in `Sources/Posteight/Strings.swift` **in the same
  change**. A missing key falls back to the Korean text, so an untranslated string does not fail
  the build, does not crash, and does not announce itself — it just shows up in Korean in an
  English window.
- `Tests/PosteightTests/LocalizationTests.swift` checks that every entry is non-empty, differs
  from its key, and keeps the same `%d`/`%@` count in both languages. It cannot see a string you
  never added to the table, so the entry is on you.
- Pure and `nonisolated` code — `PosteightStore`, the model types, anything static — takes
  `language: AppLanguage` as a parameter and defaults to `.korean`. It must never reach for
  `AppSettings.shared`; that is what made `addNote` name new tabs after the machine's system
  language instead of the app's setting.
- Views may call the `@MainActor` `L(_:)`, which does read `AppSettings.shared`. That only works
  because **every window's root view holds `@ObservedObject var settings = AppSettings.shared`**
  — `MenuBarPanelView`, `StickyNoteWindowView`, `TrashView`, `DailyLogPreviewView`,
  `PencilCaseView`, `SettingsView`, `MenuBarLabel`. A new root that forgets it keeps the language
  it was first drawn in. Child views inherit the rebuild from their root and need nothing.
- A value SwiftUI has to diff — a `Picker` option label, anything inside a `ForEach` — takes the
  language explicitly through `title(in:)` on `PenStyle`, `MenuBarCountStyle`, `StickerOption`,
  or `AppLanguage`. Reading the singleton there is invisible to SwiftUI and the label sticks at
  whatever it was first built with.
- Never localize a string that is compared against saved data. `"새 포스트잇"` in
  `PosteightStore.compacted` is what older builds actually wrote to disk; translating it breaks
  the migration. Note text, tab names, and titles are the user's own words and stay as typed.
- The menus macOS draws itself (File, Edit, Window) are AppKit's, not Posteight's. They follow
  the system language against `CFBundleLocalizations` in `Packaging/Info.plist`, which lists
  `en` and `ko` — drop a language from that list and its menus fall back to English. They can
  never follow the in-app setting, because AppKit picks them once at launch.

### A local green run is not proof

This project is developed on a Korean Mac and CI runs on an English runner. Anything that reads
the system language behaves differently in the two places, so a locale bug passes locally and
only fails after a push — that is exactly how `addNote` shipped naming new tabs `Memo 1` on the
runner and `메모 1` here.

Reproduce the runner before pushing anything that touches language:

```bash
POSTEIGHT_SYSTEM_LANGUAGE=en swift test
```

`AppLanguage.resolved` honours that variable in place of `Locale.preferredLanguages`, so the
whole suite runs as if the machine were English. Run it plain as well — both have to pass.

The variable is a reproduction aid, not a fix. The fix is that nothing outside a view reads the
current language at all: `PosteightStore` and the model types take `language:` as a parameter
and default to `.korean`, which is what keeps the test suite deterministic in the first place.

## Releasing

Releases are built by CI, not by hand. Pushing a `v*` tag runs
[`release.yml`](.github/workflows/release.yml), which stamps the version from the
tag, builds the Release configuration, packages a `.dmg`, and publishes it to
GitHub Releases with its checksum:

```bash
git switch release
git tag v0.2.0
git push origin v0.2.0
```

The tag is the only source of truth for the version. `Packaging/Info.plist` reads
`$(MARKETING_VERSION)`, so never hardcode a version there.

Day-to-day work happens on `dev`; `release` only receives merges from `dev`, and
tags are cut there. [`ci.yml`](.github/workflows/ci.yml) runs `swift test` for the
unit tests and `xcodebuild` for the real `.app` bundle, on every push to `dev` or
`release` and on every pull request into `release`. Documentation-only commits are
skipped.

`Product > Archive` in Xcode still works for a local one-off build.

## Git Workflow

- Commit to `dev` directly. This project does not use per-feature branches.
- `release` only receives merges from `dev`. Version tags are cut on `release`.
- Keep commits focused on one feature or change.
- Run `swift test` before every commit.
- Do not commit `.build/` or `dist/`; both are generated locally and ignored by Git.

## Commit Messages

An English Conventional Commit prefix, everything else in Korean.

```
type(scope): 무엇을 바꿨는지 한 줄

왜 그랬는지, 무엇이 어긋나 있었는지, 어떻게 확인했는지.
```

- Subject: `type(scope):` plus a Korean summary. Types are `feat`, `fix`, `docs`,
  `test`, `chore`, `refactor`, `ci`; the scope is optional and lowercase
  (`fix(menubar):`). One line, no trailing period. Prefer noun endings
  (`... 수정`, `... 추가`) over `~한다`, and join two changes with `+` or `—`
  instead of blurring them into one vague phrase.
- Body: Korean prose, separated from the subject by a blank line. Open with the
  defect or motivation and its reach — what was wrong, on which path, what the
  user saw. Then what changed, as `-` bullets when there is more than one thing.
  Close with the evidence: the measurement, the test that fails without the
  change, `swift test` results, related commit hashes and dates.
- The body explains why, not a file-by-file diff summary. Record the traps and
  the roads not taken (SwiftUI rendering limits, ordering constraints) so the
  next change does not walk back into them.
- Keep the `Co-Authored-By:` trailer when an agent wrote the change.
