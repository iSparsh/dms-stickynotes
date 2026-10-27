#!/usr/bin/env python3
"""Create the notes directory and initial file without replacing existing data."""
import json
import os
from pathlib import Path
import sys


def initialize(home: str) -> Path:
    directory = Path(home) / "Documents" / "sticky-notes"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "notes.json"
    try:
        with path.open("x", encoding="utf-8") as stream:
            json.dump({"version": 1, "notes": []}, stream, ensure_ascii=False)
            stream.write("\n")
    except FileExistsError:
        pass
    return path


if __name__ == "__main__":
    try:
        initialize(os.environ["HOME"])
    except (OSError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
