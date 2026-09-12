"""Exercise release preparation against real Git histories in temporary repos."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CompanionReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="riff-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / ".github").mkdir()
        shutil.copy(ROOT / ".github/companion-cliff.toml", self.repo / ".github")
        self.run_command("git", "init", "-b", "main")
        self.run_command("git", "config", "user.name", "Release test")
        self.run_command("git", "config", "user.email", "release-test@example.invalid")
        self.commit("feat(companion): initial soundboard", "Companion/app.cs")

    def run_command(self, *args, env=None):
        return subprocess.run(
            args, cwd=self.repo, env=env, check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).stdout.strip()

    def commit(self, message, path):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a") as file:
            file.write(message + "\n")
        self.run_command("git", "add", path)
        self.run_command("git", "commit", "-m", message)

    def prepare(self):
        output = self.repo / "outputs.txt"
        output.write_text("")
        env = dict(os.environ, GITHUB_OUTPUT=str(output))
        self.run_command("bash", str(ROOT / "scripts/prepare-companion-release.sh"), env=env)
        return dict(line.split("=", 1) for line in output.read_text().splitlines())

    def test_first_release_has_semver_and_changelog(self):
        outputs = self.prepare()
        self.assertEqual(outputs["tag"], "companion-v0.1.0")
        self.assertEqual(outputs["version"], "0.1.0")
        changelog = (self.repo / "artifacts/companion-release/CHANGELOG.md").read_text()
        self.assertIn("## 0.1.0 - ", changelog)
        self.assertIn("### Added", changelog)
        self.assertIn("Initial soundboard", changelog)
        self.assertNotIn("Unreleased", changelog)

    def test_semantic_bumps_only_use_companion_changes(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        for message, expected in [
            ("fix(companion): repair playback", "0.1.1"),
            ("feat(companion): add output selection", "0.2.0"),
            ("feat(companion)!: replace pairing protocol", "1.0.0"),
            ("fix(companion): migrate state\n\nBREAKING CHANGE: old state needs conversion", "2.0.0"),
            ("Update Windows packaging", "2.0.1"),
        ]:
            with self.subTest(message=message):
                self.commit("feat(ipad)!: change tablet layout", "Riff/View.swift")
                self.commit(message, "Companion/app.cs")
                outputs = self.prepare()
                self.assertEqual(outputs["version"], expected)
                self.run_command("git", "tag", outputs["tag"])

    def test_ipad_docs_and_release_reruns_do_not_build(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        self.assertEqual(self.prepare(), {"has_changes": "false"})
        self.commit("feat(ipad)!: new tablet experience", "Riff/View.swift")
        self.commit("docs: update overview", "README.md")
        self.run_command("git", "tag", "ipad-v9.0.0")
        self.assertEqual(self.prepare(), {"has_changes": "false"})

    def test_shared_assets_and_build_inputs_trigger_patch_releases(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        for index, path in enumerate([
            "Shared/Sounds/test.wav", "scripts/build-windows.ps1",
            "Riff/Resources/sound-packs.json",
            "docs/licenses/notice.txt", "Directory.Build.props",
        ], start=1):
            with self.subTest(path=path):
                self.commit("chore: update bundled input", path)
                outputs = self.prepare()
                self.assertEqual(outputs["version"], f"0.1.{index}")
                self.run_command("git", "tag", outputs["tag"])

    def test_release_tag_on_empty_merge_is_preserved(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        self.run_command("git", "checkout", "-b", "startup-fix")
        self.commit("fix(companion): repair startup", "Companion/startup.cs")
        self.run_command("git", "tag", "companion-v0.1.1")
        self.run_command("git", "checkout", "main")
        self.commit("feat(companion): add sound library", "Companion/library.cs")
        self.run_command("git", "cherry-pick", "startup-fix")
        self.run_command("git", "merge", "--no-ff", "startup-fix", "-m", "chore: merge startup fix")
        self.assertEqual(self.run_command("git", "diff", "HEAD^", "HEAD"), "")
        self.run_command("git", "tag", "companion-v0.2.0")
        self.assertEqual(self.prepare(), {"has_changes": "false"})
        self.commit("feat(companion): add offline decks", "Companion/decks.cs")
        self.assertEqual(self.prepare()["version"], "0.3.0")
        folder = self.repo / "artifacts/companion-release"
        history = (folder / "CHANGELOG.md").read_text()
        notes = (folder / "release-notes.md").read_text()
        self.assertIn("## 0.2.0 - ", history)
        self.assertIn("Add offline decks", notes)
        self.assertNotIn("Add sound library", notes)
        self.assertNotIn("Repair startup", notes)

    def test_release_tag_on_ipad_commit_is_preserved(self):
        self.commit("feat(ipad)!: replace tablet layout", "Riff/View.swift")
        self.run_command("git", "tag", "companion-v0.1.0")
        self.assertEqual(self.prepare(), {"has_changes": "false"})
        self.commit("fix(companion): repair playback", "Companion/app.cs")
        self.assertEqual(self.prepare()["version"], "0.1.1")

    def test_existing_version_on_another_branch_fails(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        self.run_command("git", "checkout", "-b", "other-release")
        self.commit("fix(companion): repair startup", "Companion/startup.cs")
        self.run_command("git", "tag", "companion-v0.1.1")
        self.run_command("git", "checkout", "main")
        self.commit("fix(companion): repair playback", "Companion/app.cs")
        with self.assertRaises(subprocess.CalledProcessError) as error:
            self.prepare()
        self.assertIn("Release tag companion-v0.1.1 already exists", error.exception.stderr)

    def test_full_changelog_keeps_history_but_release_notes_are_current(self):
        self.run_command("git", "tag", "companion-v0.1.0")
        self.commit("fix(companion): repair playback", "Companion/app.cs")
        self.commit("feat(ipad): new tablet layout", "Riff/View.swift")
        self.prepare()
        folder = self.repo / "artifacts/companion-release"
        history = (folder / "CHANGELOG.md").read_text()
        notes = (folder / "release-notes.md").read_text()
        self.assertIn("Initial soundboard", history)
        self.assertIn("Repair playback", history)
        self.assertNotIn("Initial soundboard", notes)
        self.assertIn("Repair playback", notes)
        self.assertNotIn("New tablet layout", history)


if __name__ == "__main__":
    unittest.main()
