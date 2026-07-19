"""The app bundles a copy of the watcher so it can launch it with no install.

Guard against drift: the bundled copy must be byte-identical to the source.
"""
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "bridge", "watch_claude.py")
BUNDLED = os.path.join(ROOT, "app", "Sources", "KhosrowKit", "Resources", "watch_claude.py")


class TestWatchBundledCopy(unittest.TestCase):
    def test_bundled_copy_matches_source(self):
        self.assertTrue(os.path.exists(BUNDLED), "bundled watch_claude.py is missing")
        with open(SRC, "rb") as a, open(BUNDLED, "rb") as b:
            self.assertEqual(
                a.read(), b.read(),
                "app/Sources/KhosrowKit/Resources/watch_claude.py is out of sync with "
                "bridge/watch_claude.py — re-copy it.")


if __name__ == "__main__":
    unittest.main()
