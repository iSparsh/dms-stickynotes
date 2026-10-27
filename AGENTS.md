# Repository Guidelines

## Layout

- `plugin.json` registers `stickyNotes` as a Dux Shell 2.0 desktop plugin.
- `src/StickyNotes.qml` implements the stack, the peeled-off sheets (drawn on one full-screen, input-masked bottom-layer surface) and the work-area probe.
- `src/StickyNotesSettings.qml` holds the per-instance settings (notes folder, handwriting font, text size).
- Notes default to `~/.local/share/sticky-notes/notes.json`; the folder is created with `mkdir -p` and the file on first save.
- Use Dux widgets (`qs.DCommon.Widgets`) and `Theme` tokens for interface chrome; only the paper palette and ink are fixed colors.
- Dux caches plugin folders: after adding a new QML file, restart Dux (`systemctl --user restart dms`) before it can load.

## Development

Requires Dux Shell 2.0 and Qt's QML tools. Link the repository to `~/.config/dms/plugins/stickyNotes` and reload with `dms ipc call plugin-scan rescan stickyNotes`; errors appear in `journalctl --user -u dms`.

## Checks

```sh
qmlformat -i src/*.qml
```

Run `qmlformat` before submitting QML changes. Include screenshots for visible changes.

## Commits

Use short, imperative subjects such as `Add note persistence`.

## Privacy

The notes file is personal data. Never commit it, log its contents, or include it in screenshots; use demo notes and restore the original file afterwards.
