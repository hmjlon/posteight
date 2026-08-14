# Posteight

Posteight is a macOS sticky-note checklist app prototype for keeping today's work visible on screen.

## First Prototype

- Multiple square sticky notes on one floating workspace
- Pink note as the default visual style
- Checklist rows with round completion buttons
- Pen strike animation when a task is completed
- Pencil case panel for paper color, pen color, pen style, and stickers
- Per-note "Notion log" toggle
- Daily log preview as Markdown for the next Notion integration step

## Run

Open the app project in Xcode and hit Run:

```bash
xed Posteight.xcodeproj
```

For a quick compile check without building the app bundle:

```bash
swift build
```

## Landing Page

The landing page lives in its own repository: [posteight-landing](https://github.com/hmjlon/posteight-landing).

## Tests

```bash
swift test
```

## License

Proprietary. See [LICENSE](LICENSE). This is not open source.

## Current Scope

This version focuses on the local macOS experience and interaction design. The Notion API connection is intentionally left as a later feature after the daily log format feels right.
