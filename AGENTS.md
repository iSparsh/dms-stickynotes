# Repository Guidelines

## Layout

- `plugin.json` registers `stickyNotes` as a Dux Shell 2.0 desktop plugin.
- `src/StickyNotes.qml` implements the stack, the peeled-off sheets (drawn on one full-screen, input-masked bottom-layer surface) and the work-area probe.
- `src/init_store.py` creates `~/Documents/sticky-notes/notes.json` without replacing an existing file.
- `tests/` holds the Python tests for the store initializer.

## Development

Requires Python 3, Dux Shell 2.0, Quickshell and Qt's QML tools. Link the repository to `~/.config/dms/plugins/stickyNotes` and reload with `dms ipc call plugin-scan rescan stickyNotes`; errors appear in `journalctl --user -u dms`.

## Checks

```sh
python3 -m unittest discover -s tests -v
qmlformat -i src/StickyNotes.qml
```

Run `qmlformat` before submitting QML changes. Include screenshots for visible changes.

## Commits

Use short, imperative subjects such as `Add note persistence`.

## Privacy

The notes file is personal data. Never commit it, log its contents, or include it in screenshots; use demo notes and restore the original file afterwards.
