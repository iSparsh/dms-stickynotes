import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("store", Path(__file__).resolve().parents[1] / "src/init_store.py")
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class StoreTests(unittest.TestCase):
    def test_creates_empty_store_in_documents(self):
        with tempfile.TemporaryDirectory() as home:
            path = store.initialize(home)
            self.assertEqual(path, Path(home) / "Documents/sticky-notes/notes.json")
            self.assertEqual(json.loads(path.read_text()), {"version": 1, "notes": []})

    def test_never_overwrites_existing_notes_even_if_invalid(self):
        with tempfile.TemporaryDirectory() as home:
            path = store.initialize(home)
            path.write_text("user data, even if invalid", encoding="utf-8")
            store.initialize(home)
            self.assertEqual(path.read_text(), "user data, even if invalid")


if __name__ == "__main__":
    unittest.main()
