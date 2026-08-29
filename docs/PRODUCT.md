# Product Direction

Posteight began with a simple workplace problem: paper sticky notes keep today's
tasks visible, but their contents remain exposed on a shared desk. Traditional
task managers are private, but the next action often disappears inside another
app.

Posteight combines the useful parts of both:

> Private sticky notes for your Mac — visible on your terms.

The product is intended for people who work on a Mac in open offices, shared
workspaces, or screen-sharing-heavy environments. Notes should remain easy for
the owner to see during work and easy to hide when the situation changes.

## Experience Principles

- **Quick to place:** capture a task without leaving the current workflow.
- **Hard to forget:** keep independent memo windows where each part of the work happens.
- **Easy to hide:** provide clear controls for hiding and restoring memo windows.
- **Private by default:** keep notes local and make any external export explicit.
- **Satisfying to finish:** preserve the pen-like completion interaction as the
  app's signature moment.
- **Quiet when idle:** remain available without adding visual noise or Dock clutter.

## Menu Bar Experience

Posteight runs as a compact macOS menu bar utility. There is no workspace window:
the status item is the only permanent surface, and its icon carries the
remaining-task count. The popover is the control center for quick capture,
opening memo windows, the daily log, the trash, and quitting. The floating
memos remain the main working surfaces; the popover should not become a second
full editor.

The status item is one folded card with the count written on it — remaining by
default, or done. The card fills from the bottom as today's items get done, and
its ink keeps moving while anything is left, so a glance says both how much is
left and that there is still something running. The two days with no number
worth reading get a face instead: nothing on the list, and nothing left on it.
Clicking it opens the popover, which is also where settings live: the settings
entry opens a modal dialog over whatever is on screen.

Settings stay deliberately small: what the status item counts, whether notes
float above other apps, and whether Posteight keeps a Dock icon. The Dock icon is
on by default, so a running Posteight can be reached from the Dock and
Command-Tab, and clicking it brings the memo windows back. Turning it off leaves a
menu-bar-only app. Hiding all notes and a manual meeting mode are still to come.

## Design Direction: Tabbed Memo

The selected visual foundation is **Tabbed Memo**: every independent memo window
has one warm, matte surface under its own compact macOS-style tab bar. A memo owns
its position, size, colour, appearance, tabs, and selected tab. Each tab owns its
editable name, content title, and checklist; the selected tab and memo body read
as one continuous surface.

- Give the tab bar its own consistent height and layout instead of floating small
  indexes over the memo.
- Keep the tab strip fixed to the memo width: reserve the trailing controls, then
  divide the remaining width equally across that memo's tabs without horizontal scrolling.
- Use calm rounded tab shoulders and a continuous active surface, without folded
  corners, triangular decoration, glassmorphism, or a visible grid pattern.
- Keep texture close to subtle natural paper fibers rather than a visible
  decorative pattern.
- Use a restrained palette of ivory, blush, sage, mist, butter, and lilac paper.
- Keep the checklist visually dominant and reveal editing controls on hover.
- Keep memo IDs and tab IDs separate. A new memo starts with `메모 1`; its local `+`
  adds `메모 2`, `메모 3`, and so on only to that window, and activates the new tab.
- A tab click switches content. Clicking the already-active tab again edits its name
  inline; Enter or focus loss commits a non-blank name.
- Make the active tab full-height and continuous with its memo color; keep inactive
  tabs slightly shorter and quieter, like background tabs in a compact browser.
- Keep the menu bar and popover compact, native, and mostly monochrome.
- Use motion sparingly; the pen strike-through remains the signature completion
  moment.

The app icon keeps the original folded-paper mark, while the working window uses
the cleaner tabbed shell. Typography, spacing, hover behavior, and the menu bar
experience will continue to be refined one decision at a time.

## Product Priorities

1. Reliable local persistence and exact window restoration across relaunches,
   displays, and Spaces
2. Global show/hide control, hide-on-lock behavior, and a dependable manual
   meeting mode
3. Menu bar quick capture and keyboard-first checklist interaction
4. A lightweight daily flow for completion, optional rollover, and explicit
   Markdown export

Full collaboration, accounts, cloud sync, AI features, and deep third-party
integrations are outside the current focus.

This is the source of truth for product positioning, experience principles, menu bar
behaviour, design direction, priorities, and non-goals. Change it in the same commit that
changes the behaviour it describes.
