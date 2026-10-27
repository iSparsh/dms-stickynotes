# Repository Guidelines

## Layout

- `plugin.json` registers `stickyNotes` as a Dux Shell 2.0 desktop plugin.
- `src/StickyNotes.qml` implements the stack, the peeled-off sheets (drawn on one full-screen, input-masked bottom-layer surface) and the work-area probe.
- Notes are stored in `~/Documents/sticky-notes/notes.json`; the folder is created with `mkdir -p` and the file on first save.

## Development

Requires Dux Shell 2.0 and Qt's QML tools. Link the repository to `~/.config/dms/plugins/stickyNotes` and reload with `dms ipc call plugin-scan rescan stickyNotes`; errors appear in `journalctl --user -u dms`.

## Checks

```sh
qmlformat -i src/StickyNotes.qml
```

Run `qmlformat` before submitting QML changes. Include screenshots for visible changes.

## Commits

Use short, imperative subjects such as `Add note persistence`.

## Privacy

The notes file is personal data. Never commit it, log its contents, or include it in screenshots; use demo notes and restore the original file afterwards.
