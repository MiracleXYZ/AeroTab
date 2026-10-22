import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("update_homebrew", Path(__file__).parents[1] / "update-homebrew.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class HomebrewReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cask = self.root / "tap/Casks/aerotab.rb"

    def release(self, version="0.4.0"):
        lines = []
        for arch in ("arm64", "x86_64"):
            archive = self.root / f"AeroTab-{version}-{arch}.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("AeroTab.app/Contents/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "dev.miraclexyz.AeroTab",
                    "CFBundleShortVersionString": version,
                    "LSMinimumSystemVersion": "26.0",
                }))
            lines.append(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}")
        (self.root / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n")
        return {"tag_name": f"v{version}", "draft": False, "prerelease": False}

    def test_published_release_and_repeat_are_idempotent(self):
        release = self.release()
        self.assertTrue(sync.update_cask(release, self.root, self.cask))
        self.assertIn('version "0.4.0"', self.cask.read_text())
        self.assertIn('depends_on macos: ">= :tahoe"', self.cask.read_text())
        self.assertFalse(sync.update_cask(release, self.root, self.cask))

    def test_corrupt_archive_preserves_existing_cask(self):
        release = self.release()
        sync.update_cask(release, self.root, self.cask)
        original = self.cask.read_bytes()
        (self.root / "AeroTab-0.4.0-arm64.zip").write_bytes(b"corrupt download")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            sync.update_cask(release, self.root, self.cask)
        self.assertEqual(self.cask.read_bytes(), original)

    def test_drafts_prereleases_and_unsafe_tags_are_rejected(self):
        for changes in ({"draft": True}, {"prerelease": True}, {"tag_name": "v0.4.0-beta"},
                        {"tag_name": "v0.4.0/../../other"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                sync.stable_version(self.release() | changes)
        self.assertFalse(self.cask.exists())

    def test_older_release_does_not_downgrade_tap(self):
        sync.update_cask(self.release("0.10.0"), self.root, self.cask)
        original = self.cask.read_bytes()
        self.assertFalse(sync.update_cask(self.release("0.9.0"), self.root, self.cask))
        self.assertEqual(self.cask.read_bytes(), original)

    def test_missing_architecture_checksum_is_rejected(self):
        release = self.release()
        checksum_file = self.root / "SHA256SUMS.txt"
        checksum_file.write_text(checksum_file.read_text().splitlines()[0] + "\n")
        with self.assertRaisesRegex(ValueError, "both architectures"):
            sync.update_cask(release, self.root, self.cask)
        self.assertFalse(self.cask.exists())

    def test_mislabeled_release_is_rejected(self):
        release = self.release()
        with self.assertRaisesRegex(ValueError, "identity or version"):
            with patch.object(sync.plistlib, "loads", return_value={
                "CFBundleShortVersionString": "0.3.0", "CFBundleIdentifier": "dev.miraclexyz.AeroTab",
            }):
                sync.update_cask(release, self.root, self.cask)
        self.assertFalse(self.cask.exists())


if __name__ == "__main__":
    unittest.main()
