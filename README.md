# Posteight

**Private sticky notes for your Mac — visible on your terms.**

[![Latest release](https://img.shields.io/github/v/release/hmjlon/posteight?label=download)](https://github.com/hmjlon/posteight/releases/latest)

Posteight keeps today's checklist out on the desktop, in small independent windows you can
put where the work actually happens — and hide when someone walks over.

English · [한국어](README.ko.md)

![Posteight notes floating on the macOS desktop](docs/images/posteight-desktop-en.jpg)

## Install

### Requirements

| | |
| --- | --- |
| macOS | 14 (Sonoma) or later |
| Mac | Apple silicon only — `ARCHS` is pinned to `arm64`, so Intel Macs are not supported |
| Interface language | Korean or English, switchable in Settings |

### Homebrew

```bash
brew install --cask hmjlon/tap/posteight && xattr -dr com.apple.quarantine /Applications/Posteight.app
```

The second half is what lets the app open at all — see [First launch](#first-launch).
`brew upgrade` picks up later versions from the same tap, and needs that same `xattr` line
again each time.

### Download

Or download the latest `.dmg` from [Releases](https://github.com/hmjlon/posteight/releases),
open it, and drag **Posteight** to **Applications**.

### First launch

Posteight is not notarized by Apple yet. Both installs mark the app as quarantined, and
macOS blocks a quarantined app that it cannot verify. Clearing that flag is the shortest
way through — run this before opening Posteight for the first time:

```bash
xattr -dr com.apple.quarantine /Applications/Posteight.app
```

**Without a terminal**, go through System Settings instead. The steps have to follow each
other:

1. Open Posteight. macOS shows a warning and refuses to launch it.
2. **Right away**, open **System Settings → Privacy & Security** and scroll down to Security.
3. Click **Open Anyway** and authenticate.

Apple shows that button for about an hour after the blocked launch, and not before it. If
it is not there, open Posteight once more and go straight back to Privacy & Security.
Control-clicking the app and choosing **Open** is not a way around this either — macOS 15
removed that shortcut.

Either way, it comes back on every update, including `brew upgrade`. Posteight is signed
ad-hoc, so its signature changes with each build and macOS cannot tell the new version is
the same app you already approved.

Notarization needs a paid Apple Developer Program membership. Until that is in place, this
step is unavoidable for anyone but the person who built the app.

## Using Posteight

### Memo windows

<img src="docs/images/posteight-note-en.png" alt="A memo window with two tabs: a pinned task with a note, a completed task struck through, and a task with a reminder" width="300">

Each memo is its own floating window that remembers where you put it, across displays too.
Inside, a compact tab bar holds up to ten lists. Tabs share the width; when the memo is at its
narrowest, or holds too many tabs for each to stay clickable, the bar folds into the current tab
and a menu of the rest.

- Multiple independent, floating, resizable memo windows; a new one opens on the screen you are working on
- Per-memo tabs, renamed inline by clicking the active tab again. Drop a memo onto another to merge their tabs
- Checklists with an animated pen strike-through on completion
- Paper and pen colors, nib, per-tab icons, and the memo's font and text size, all set from the pencil case
- Closing a memo window — the close button or Esc — only hides it; the memo stays
- Trash with content previews, restore, and permanent delete, emptying itself after 30 days

### Menu bar

<img src="docs/images/posteight-menubar.png" alt="The Posteight status item, an infinity loop that traces itself as items get done" width="44">

Posteight has no main window. The status item is the only permanent surface: the 8 of
Posteight drawn as a small infinity loop, with the number of remaining or finished tasks
beside it — or no number at all. The loop traces itself as items get done and completes when
nothing is left. Clicking it opens the popover — a new memo, search, showing or hiding every
memo at once, the trash, locking the app when app lock is on, settings, and quit.

Settings covers the language, what the status item counts, whether notes stay in front of
other apps and out of screen shares and screenshots, whether reminders show task text, app
lock, the default font, storage and backups, and whether Posteight keeps a Dock icon. The
Dock icon is on by default, so a running Posteight can be reached from the Dock and
Command-Tab, and clicking it brings the memo windows back. Turning it off leaves a
menu-bar-only app.

### Search and organize

- Choose **Search Notes…** in the menu bar to search names, titles, tasks, and details across all tabs. Click a result to open the matching location in its memo.
- Drag task handles to reorder, or use the context menu to move tasks to another memo. Pin tasks to the top or sort by completion state.
- Schedule reminders for individual tasks. Notifications require permission in the installed app. They show a short notice instead of the task text unless you turn on **Settings → Reminders → Show task text in notifications**.
- Set the default font and text size in Settings, or pick a different font and size for one memo from its pencil case. Import your own TTF, OTF, or TTC font files.

### Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Command-N | New memo |
| Command-T | New tab in the current memo |
| Command-Delete | Move the current tab to the Trash, after confirming |
| Command-Z / Shift-Command-Z | Undo / redo across the whole memo |
| Command-A, then Command-C | Select and copy the current tab |
| Esc | Hide the memo |
| Command-, | Settings |

The memo shortcuts also work while a Korean input source is active. While you are editing a
field, Command-A selects within that field only.

### Storage errors and backups

If saved files cannot be read or previous notes cannot be migrated, editing and saving pause to protect the originals. The menu bar and **Settings → Storage and Backup** show the error. Resolve the cause and select **Try Again**. Edits that fail to save remain in memory while the app is open; resolve save errors before quitting.

Successfully loaded notes are backed up to `backup.json` before the first save after launch. **Back Up Current Notes** replaces that backup with the current contents. **Restore Backup…** replaces notes and trash with the backup, archiving the original files in a `BeforeRestore-…` folder. A restore interrupted by quitting resumes on the next launch.

Backups contain notes and trash, but not settings or font files. They stay in the same storage folder on this Mac and do not replace an external backup against disk failure. Backups and archived originals can retain deleted content beyond the trash's 30-day retention period. Delete unneeded `backup.json` and `BeforeRestore-…` folders through **Settings → App → Open Folder**.

### Language

<img src="docs/images/posteight-settings-en.png" alt="Posteight settings, with the language options at the top" width="380">

Posteight reads in Korean or English, and follows your Mac's language until you pick one.
**Settings → Language** switches every string the app draws itself — the popover, the memo
controls, the trash — with no relaunch; open memo windows change as you click.
What you typed stays exactly as you typed it: note text, tab names, and titles are yours, not
translated.

The menus macOS draws itself — File, Edit, Window — still follow the system language.

### Where your notes live

Posteight runs in the App Sandbox, so your notes live inside its own container —
`~/Library/Containers/com.younjiyoung.posteight/Data/Library/Application Support/Posteight/`.
File permissions restrict reading and writing to your user account. Files are not encrypted; these permissions do not prevent access by other programs running as the same user.
Settings → App → Open Folder takes you there. Notes from versions before the sandbox are
copied over once, on first launch, and the old folder is left untouched.

There is no account, no sync, and no telemetry. Export is explicit: Command-A selects the
current tab in a memo window and Command-C copies it to the clipboard, marked so clipboard
managers keep it out of their history.

Enable **Settings → App lock** to lock all of Posteight from the menu bar. Unlocking uses Touch ID
or your Mac login password, so Posteight stores no separate password. While locked, the app hides
memos, Trash, and task counts. Enabling app lock also keeps task text out of
notifications, and a relaunched app stays locked until you authenticate. This is a screen lock;
it does not encrypt the stored note files.

Locking the screen puts the visible memos away, and unlocking brings them back where they
were; memos you hid yourself stay hidden either way. Memo windows are also left out of
screen shares, recordings, and screenshots — handing your screen to a meeting does not
hand over the memos. Turn that off in **Settings → Notes** when the memos are what you
mean to show. Neither asks for an extra permission.

This is visual privacy, not a security-vault promise. Posteight can reduce accidental
exposure when you step away or share a screen, but it cannot prevent someone nearby from
reading content that is currently visible on an unlocked display.

## License

Proprietary. See [LICENSE](LICENSE). This is not open source.

---

Building Posteight, or changing how it behaves? [AGENTS.md](AGENTS.md) is the contributor guide:
the stack, the entry point and window routing, the code structure, build paths, persistence rules,
the release flow, and commit conventions.
